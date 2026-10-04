require "fileutils"
require "json"

# Task 7 Part 4: the Image Lab. For each topic it builds a throwaway project,
# plans one scene's shots, compiles the new prompts, and renders every shot with
# the OLD prompt and the NEW compiled prompt. Images are written to a run folder
# only; no Asset row is created, so no production project is touched. The
# throwaway project is destroyed at the end of each topic.
module ImageLab
  Failure = Class.new(StandardError)

  module_function

  # @return [Hash] { run_dir:, rows: [...], total_cost_usd:, calls: n }
  def run(topics:, shots:, variants:, provider:, out_dir:)
    FileUtils.mkdir_p(out_dir)
    adapter = build_adapter(provider)
    rows = []
    topics.each do |topic|
      rows.concat(run_topic(topic, shots, variants, adapter, out_dir))
    end
    File.write(File.join(out_dir, "rows.json"), JSON.pretty_generate(rows))
    {
      run_dir: out_dir,
      rows: rows,
      total_cost_usd: rows.sum { |r| r[:cost_usd].to_f }.round(4),
      calls: rows.size
    }
  end

  def build_adapter(provider)
    case provider
    when "cloudflare" then Providers::Image::CloudflareAdapter.new
    when "gemini-paid"
      key = ENV["GEMINI_PAID_API_KEY"].presence or raise Failure, "GEMINI_PAID_API_KEY is not set; the paid step is skipped"
      Providers::CappedImageAdapter.new(Providers::Image::GeminiAdapter.new(api_key: key, model: "gemini-3.1-flash-image"))
    else
      raise Failure, "unknown provider #{provider.inspect}"
    end
  end

  def run_topic(topic, shots, variants, adapter, out_dir)
    user = User.first
    project = Project.create!(user: user, title: "IMAGE LAB — #{topic.truncate(40)}", topic: topic,
                              format: "youtube_long", aspect_ratio: "16:9", target_duration_seconds: 45,
                              visual_style: "cinematic")
    begin
      Ai::ScriptService.new(project: project).call
      Ai::ScenePlannerService.new(project: project).call
      Ai::SettingService.new(project: project).call
      Ai::LookService.new(project: project).call
      scene = project.scenes.order(:position).find { |s| s.asset_strategy == "image" && s.visual_prompt.present? }
      raise Failure, "no image scene planned for #{topic}" unless scene

      Ai::ShotPlanner.new(scene: scene).call
      picked = scene.shots.order(:position).limit(shots).to_a
      picked = [ nil ] if picked.empty?
      units = picked.each_with_index.map do |shot, i|
        { id: shot&.key || "#{scene.key}_whole", subject: scene.metadata["subject"], shot: shot,
          action: shot&.action.presence || scene.action, camera: shot&.camera_movement || scene.camera&.dig("movement"),
          mood: scene.mood }
      end
      compiled = Media::ImagePromptCompiler.new(project: project, scene: scene).call(
        units.map { |u| u.slice(:subject, :action, :camera, :mood).merge(id: u[:id], framing: u[:shot]&.framing) }
      )

      slug = topic.parameterize.first(30)
      units.flat_map do |unit|
        variants.map do |variant|
          decision = compiled[unit[:id]]
          compiled_prompt = variant == "new" ? decision&.prompt : nil
          built = Media::ImagePromptBuilder.new(project: project, scene: scene, shot: unit[:shot],
                                                compiled_prompt: compiled_prompt).call
          result = adapter.generate(prompt: built[:prompt], negative_prompt: built[:negative_prompt],
                                    seed: built[:seed], aspect_ratio: "16:9")
          file = File.join(out_dir, "#{slug}__#{unit[:id]}__#{variant}.#{extension(result.content_type)}")
          File.binwrite(file, result.bytes)
          {
            topic: topic, unit: unit[:id], variant: variant, prompt: built[:prompt],
            prompt_source: variant == "new" ? (decision&.source || "none") : "old",
            prompt_words: built[:prompt].split.size, provider: result.provider, model: result.model,
            cost_usd: result.cost_usd.to_f, file: file
          }
        end
      end
    ensure
      project.destroy
    end
  end

  def extension(content_type)
    { "image/jpeg" => "jpg", "image/webp" => "webp" }.fetch(content_type.to_s, "png")
  end
end
