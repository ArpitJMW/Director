require "fileutils"
require "json"

# Task 7.3: planned fixtures. A topic's script, scene plan, shot plan, look and
# setting are built ONCE and saved as JSON. The compiler tests and the image runs
# then load the fixture and spend only the compile call (about 1.5k tokens),
# instead of re-planning the whole project (about 14k tokens) on every test.
#
# Build (spends the planning quota, once per topic):
#   bin/rails image_lab:fixture TOPICS="How UPI changed payments in India|..." OUT=tmp/image_lab/fixtures
# Compile from the fixtures (compile call only, on the lighter stage model):
#   bin/rails image_lab:compile FIXTURES=tmp/image_lab/fixtures OUT=tmp/image_lab/compiled
# Render old vs new (images only, reuses the compiled prompts):
#   bin/rails image_lab:images FIXTURES=... COMPILED=... OUT=... PROVIDER=cloudflare
module ImageLab
  module Fixture
    FORMAT = { format: "youtube_long", aspect_ratio: "16:9", target_duration_seconds: 45, visual_style: "cinematic" }.freeze
    STRIPPED_META = %w[subject_sheet subject_sheet_for].freeze

    module_function

    # Builds one fixture file on the planning model, then destroys the project.
    def build(topic:, out_path:)
      project = Project.create!(user: User.first, title: "IMAGE LAB fixture — #{topic.truncate(30)}", topic: topic, **FORMAT)
      begin
        Ai::ScriptService.new(project: project).call
        Ai::ScenePlannerService.new(project: project).call
        Ai::SettingService.new(project: project).call
        Ai::LookService.new(project: project).call
        scene = project.scenes.order(:position).find { |s| s.asset_strategy == "image" && s.visual_prompt.present? }
        raise Failure, "no image scene planned for #{topic}" unless scene

        Ai::ShotPlanner.new(scene: scene).call
        data = {
          topic: topic, built_at: Time.current.iso8601,
          look: project.settings["look"], setting: project.settings["setting"],
          scene: scene_json(scene), shots: scene.shots.order(:position).limit(3).map { |s| shot_json(s) }
        }
        FileUtils.mkdir_p(File.dirname(out_path))
        File.write(out_path, JSON.pretty_generate(data))
        data
      ensure
        project.destroy
      end
    end

    # Recreates a throwaway project, scene and shots from a fixture. Caller destroys the project.
    def materialize(data)
      project = Project.create!(user: User.first, title: "IMAGE LAB materialized — #{data['topic'].to_s.truncate(30)}",
                                topic: data["topic"], settings: { "look" => data["look"], "setting" => data["setting"] }, **FORMAT)
      s = data["scene"]
      scene = project.scenes.create!(
        key: s["key"], position: s["position"], duration_seconds: s["duration_seconds"], purpose: s["purpose"],
        narration: s["narration"], action: s["action"], mood: s["mood"], visual_prompt: s["visual_prompt"],
        negative_prompt: s["negative_prompt"], content_type: s["content_type"], visual_type: s["visual_type"],
        asset_strategy: s["asset_strategy"], animation: s["animation"], camera: s["camera"] || {},
        metadata: s["metadata"] || {}
      )
      shots = data["shots"].map do |sh|
        scene.shots.create!(
          key: sh["key"], position: sh["position"], duration_seconds: sh["duration_seconds"], action: sh["action"],
          camera_movement: sh["camera_movement"], framing: sh["framing"], shot_type: sh["shot_type"],
          negative_prompt: sh["negative_prompt"], metadata: sh["metadata"] || {}
        )
      end
      [ project, scene, shots ]
    end

    # Compiles every shot of one fixture (the compile call only). Returns the decisions and the
    # AI generation records, read before the throwaway project is destroyed.
    def compile(data)
      project, scene, shots = materialize(data)
      begin
        results = Media::ImagePromptCompiler.new(project: project, scene: scene).call(units_for(scene, shots))
        generations = AiGeneration.where(project_id: project.id, kind: "visual_prompt").order(:id).map do |g|
          { model: g.model, prompt_tokens: g.prompt_tokens, completion_tokens: g.completion_tokens,
            response: g.response.to_h.slice("compile_source", "compile_reasons", "compile_soft", "raw_pass",
                                             "raw_reasons", "retried_ids", "raw_texts", "compile_model") }
        end
        {
          topic: data["topic"], subject_sheet: scene.reload.metadata["subject_sheet"],
          shots: shots.map do |sh|
            decision = results[sh.key]
            { id: sh.key, framing: sh.framing, source: decision&.source, prompt: decision&.prompt }
          end,
          generations: generations
        }
      ensure
        project.destroy
      end
    end

    # Renders OLD (builder prompt) and NEW (compiled prompt, or the builder prompt when the
    # compile fell back) for every shot of one fixture. Images only; no Asset rows.
    def render(data, compiled, adapter, out_dir, variants: %w[old new])
      project, scene, shots = materialize(data)
      begin
        slug = data["topic"].parameterize.first(30)
        shots.flat_map do |shot|
          decision = compiled.find { |c| c[:id] == shot.key } || {}
          variants.map do |variant|
            compiled_prompt = variant == "new" ? decision[:prompt] : nil
            built = Media::ImagePromptBuilder.new(project: project, scene: scene, shot: shot, compiled_prompt: compiled_prompt).call
            result = adapter.generate(prompt: built[:prompt], negative_prompt: built[:negative_prompt],
                                      seed: built[:seed], aspect_ratio: "16:9")
            file = File.join(out_dir, "#{slug}__#{shot.key}__#{variant}.#{ImageLab.extension(result.content_type)}")
            File.binwrite(file, result.bytes)
            {
              topic: data["topic"], unit: shot.key, variant: variant, framing: shot.framing,
              prompt: built[:prompt], prompt_words: built[:prompt].split.size,
              prompt_source: variant == "new" ? (decision[:source] || "none") : "old",
              provider: result.provider, model: result.model, cost_usd: result.cost_usd.to_f, file: file
            }
          end
        end
      ensure
        project.destroy
      end
    end

    def units_for(scene, shots)
      shots.map do |sh|
        { id: sh.key, subject: scene.metadata["subject"], action: sh.action, camera: sh.camera_movement,
          mood: scene.mood, framing: sh.framing }
      end
    end

    def scene_json(scene)
      meta = (scene.metadata || {}).except(*STRIPPED_META)
      {
        key: scene.key, position: scene.position, duration_seconds: scene.duration_seconds.to_f,
        purpose: scene.purpose, narration: scene.narration, action: scene.action, mood: scene.mood,
        visual_prompt: scene.visual_prompt, negative_prompt: scene.negative_prompt, content_type: scene.content_type,
        visual_type: scene.visual_type, asset_strategy: scene.asset_strategy, animation: scene.animation,
        camera: scene.camera, metadata: meta
      }
    end

    def shot_json(shot)
      {
        key: shot.key, position: shot.position, duration_seconds: shot.duration_seconds.to_f, action: shot.action,
        camera_movement: shot.camera_movement, framing: shot.framing, shot_type: shot.shot_type,
        negative_prompt: shot.negative_prompt, metadata: shot.metadata || {}
      }
    end
  end
end
