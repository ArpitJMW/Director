module Media
  # Turns a scene's bare visual_prompt into a rich, provider-ready image prompt:
  # subject + the project's visual style + camera/quality direction + an "avoid"
  # clause. Keeps a deterministic per-project seed so scenes look like one film.
  class ImagePromptBuilder
    # style key => (positive descriptors, things to avoid)
    STYLES = {
      "cinematic" => [
        "cinematic film still, anamorphic lens, shallow depth of field, dramatic natural lighting, color-graded, highly detailed, 4k",
        "text, watermark, logo, caption, low quality, blurry, deformed, extra limbs, cartoon, 3d render"
      ],
      "photorealistic" => [
        "photorealistic photograph, DSLR, 50mm lens, natural lighting, sharp focus, realistic textures, high dynamic range, 4k",
        "illustration, painting, cartoon, cgi, text, watermark, deformed, extra limbs, oversaturated"
      ],
      "wildlife_documentary" => [
        "wildlife documentary still, shot on a 400mm telephoto lens, golden-hour light, shallow depth of field, National Geographic style, photorealistic, ultra detailed",
        "illustration, cartoon, cgi, text, watermark, people, deformed animal anatomy, extra limbs"
      ],
      "documentary" => [
        "documentary photograph, available light, candid, 35mm, realistic, muted color grade, high detail",
        "staged, cartoon, illustration, text, watermark, oversaturated, deformed"
      ],
      "3d_animation" => [
        "stylised 3d animated film still, Pixar-like rendering, soft global illumination, expressive, vibrant, high detail",
        "photorealistic, text, watermark, low-poly, uncanny, deformed"
      ],
      "illustration" => [
        "digital illustration, painterly, clean linework, rich color palette, dramatic lighting, concept-art quality",
        "photo, photorealistic, text, watermark, jpeg artifacts, deformed"
      ],
      "anime" => [
        "anime key visual, cel shading, detailed background art, dynamic composition, studio-quality",
        "photorealistic, 3d render, text, watermark, deformed, extra fingers"
      ],
      "watercolor" => [
        "loose watercolor painting, visible brush strokes, soft edges, textured paper, muted natural palette",
        "photo, 3d render, hard edges, text, watermark, deformed"
      ]
    }.freeze

    DEFAULT_STYLE = "cinematic".freeze

    def initialize(scene:, project:)
      @scene = scene
      @project = project
    end

    # @return [Hash] { prompt:, negative_prompt:, seed: }
    def call
      style_key = STYLES.key?(@project.visual_style) ? @project.visual_style : DEFAULT_STYLE
      positive, avoid = STYLES.fetch(style_key)

      base = @scene.visual_prompt.to_s.strip
      subject = @project.niche.presence
      base = "#{subject}: #{base}" if subject && !base.downcase.include?(subject.downcase)

      {
        prompt: [ base, positive ].reject(&:blank?).join(". "),
        negative_prompt: avoid,
        seed: project_seed
      }
    end

    private

    def project_seed
      @project.image_seed || begin
        seed = Digest::SHA256.hexdigest(@project.public_id)[0, 8].to_i(16) % 2_147_483_647
        @project.update_column(:image_seed, seed)
        seed
      end
    end
  end
end
