module Media
  # Narration + timed captions for one scene (spec §14, §20 steps 11-12, §26).
  class VoiceGenerationService
    Error = Class.new(StandardError)

    def initialize(scene:, provider: Providers.voice)
      @scene = scene
      @project = scene.project
      @provider = provider
    end

    def generatable?
      @scene.narration.present?
    end

    def call
      return nil unless generatable?

      voice_id = @project.settings["voice_id"].presence || @provider.default_voice_id

      generation = nil
      result = AiGeneration.track!(
        project: @project, scene: @scene, kind: "voice", provider_kind: "voice",
        provider: @provider.name, model: @provider.default_model,
        request: { chars: @scene.narration.length, voice_id: voice_id }
      ) do |gen|
        generation = gen
        @provider.synthesize(text: @scene.narration, voice_id: voice_id)
      end

      audio = Asset.store!(
        project: @project, scene: @scene, asset_type: "audio",
        io: result.io, content_type: result.content_type,
        source_type: "ai_generated", provider: result.provider, model: result.model,
        duration_seconds: result.duration_seconds, ai_generation: generation
      )

      captions = CaptionService.build(text: @scene.narration, alignment: result.alignment)

      voice_generation = @project.voice_generations.create!(
        scene: @scene, script: @project.current_script,
        provider: result.provider, voice_id: voice_id, model: result.model,
        text: @scene.narration, audio_asset: audio, alignment: result.alignment,
        captions: captions, status: "succeeded",
        duration_seconds: result.duration_seconds, cost_usd: result.cost_usd,
        provider_request_id: result.provider_request_id, ai_generation_id: generation.id
      )

      SceneDurationService.reconcile!(scene: @scene, measured_duration: result.duration_seconds)

      # Supersede any earlier narration for this scene (latest wins).
      VoiceGeneration.where(scene_id: @scene.id).where.not(id: voice_generation.id).find_each do |old|
        old.audio_asset&.destroy
        old.destroy
      end

      voice_generation
    rescue => e
      GenerationLog.create!(
        project: @project, scene: @scene, level: "error",
        stage: "voice", message: "voice failed for #{@scene.key}: #{e.message}"
      )
      raise
    end
  end
end
