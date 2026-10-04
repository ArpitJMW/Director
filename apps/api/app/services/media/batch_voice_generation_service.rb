module Media
  # Narration + timed captions for every narrated scene in a project, via ONE
  # (or the fewest possible) provider call rather than one call per scene
  # (Phase 1 Task 2.4). Used instead of calling Media::VoiceGenerationService
  # once per scene when the configured provider declares
  # Providers::Voice::Base#supports_batch? — today that's Gemini TTS, whose
  # free tier returns HTTP 429 after ~1-2 per-scene calls.
  #
  # Produces the exact same per-scene Asset ("audio") + VoiceGeneration
  # records as the per-scene path, so Media::CaptionService, the render
  # manifest and the renderer need no changes — they don't know or care
  # whether a scene's narration came from its own call or a shared one.
  #
  # A single AiGeneration is recorded for the whole batch (kind: "voice",
  # request[:mode] = "batch") and every resulting VoiceGeneration links to it
  # via the same ai_generation_id column the per-scene path already uses for
  # its one-to-one link — a batch is just N links to one row instead of N
  # links to N rows.
  class BatchVoiceGenerationService
    Error = Class.new(StandardError)

    # @param scenes [Array<Scene>, nil] explicit unit list (e.g. Generation::
    #   VoiceJob passes only the scenes that still need audio, so a retry
    #   doesn't re-spend quota on scenes that already succeeded). Defaults to
    #   every narrated scene in the project when omitted.
    def initialize(project:, provider: Providers.voice, scenes: nil)
      @project = project
      @provider = provider
      @scenes = scenes
    end

    def scenes
      @scenes ||= @project.scenes.order(:position).select { |s| s.narration.present? }
    end

    def generatable?
      @provider.supports_batch? && scenes.any?
    end

    # @return [Array<VoiceGeneration>] only the scenes that actually got audio
    #   — a chunk that failed after retries (see GeminiTtsAdapter#synthesize_batch)
    #   is logged and simply absent here, exactly as a per-scene failure is
    #   absent from Media::VoiceGenerationService's per-scene results, rather
    #   than discarding every scene in the batch.
    def call
      return [] unless generatable?

      voice_id = @project.settings["voice_id"].presence || @provider.default_voice_id
      texts = scenes.map(&:narration)

      generation = nil
      results = AiGeneration.track!(
        project: @project, kind: "voice", provider_kind: "voice",
        provider: @provider.name, model: @provider.default_model,
        request: { mode: "batch", scenes: scenes.map(&:key), total_chars: texts.sum(&:length), voice_id: voice_id }
      ) do |gen|
        generation = gen
        @provider.synthesize_batch(texts: texts, voice_id: voice_id)
      end

      unless results.size == scenes.size
        raise Error, "provider returned #{results.size} result(s) for #{scenes.size} scene(s)"
      end

      scenes.zip(results).filter_map do |scene, result|
        if result.nil?
          GenerationLog.create!(
            project: @project, scene: scene, level: "warn", stage: "voice",
            message: "#{scene.key}: no audio from the batch call (its chunk failed after retries)"
          )
          next
        end
        store(scene, result, generation, voice_id)
      end
    rescue => e
      GenerationLog.create!(
        project: @project, level: "error", stage: "voice",
        message: "batch voice failed for #{scenes.map(&:key).join(', ')}: #{e.message}"
      )
      raise
    end

    private

    def store(scene, result, generation, voice_id)
      audio = Asset.store!(
        project: @project, scene: scene, asset_type: "audio",
        io: result.io, content_type: result.content_type,
        source_type: "ai_generated", provider: result.provider, model: result.model,
        duration_seconds: result.duration_seconds, ai_generation: generation
      )

      captions = CaptionService.build(text: scene.narration, alignment: result.alignment)

      voice_generation = @project.voice_generations.create!(
        scene: scene, script: @project.current_script,
        provider: result.provider, voice_id: voice_id, model: result.model,
        text: scene.narration, audio_asset: audio, alignment: result.alignment,
        captions: captions, status: "succeeded",
        duration_seconds: result.duration_seconds, cost_usd: result.cost_usd,
        provider_request_id: result.provider_request_id, ai_generation_id: generation.id
      )

      SceneDurationService.reconcile!(scene: scene, measured_duration: result.duration_seconds)

      # Supersede any earlier narration for this scene (latest wins) — same
      # rule Media::VoiceGenerationService applies per scene.
      VoiceGeneration.where(scene_id: scene.id).where.not(id: voice_generation.id).find_each do |old|
        old.audio_asset&.destroy
        old.destroy
      end

      voice_generation
    end
  end
end
