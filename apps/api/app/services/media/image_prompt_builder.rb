module Media
  # Turns a scene's (or shot's) bare visual_prompt into a rich, provider-ready
  # image prompt: subject hard-anchored at the front, then the shot brief, then
  # environment, then the visual-style descriptors. Negative constraints are kept
  # SEPARATE (never folded into the positive prompt — some models read "no text"
  # as "text"). Deterministic per-project seed so scenes look like one film.
  class ImagePromptBuilder
    # style key => (positive descriptors, base things to avoid)
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
        "wildlife documentary still, shot on a 400mm telephoto lens, natural light, shallow depth of field, National Geographic style, photorealistic, ultra detailed, realistic animal anatomy",
        "illustration, cartoon, cgi, text, watermark, people, deformed animal anatomy, extra limbs, fused bodies, extra legs, extra ears"
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

    # Fixed, unconditional additions (Phase 1 Task 2.5). Cloudflare's FLUX
    # schnell endpoint silently DROPS negative_prompt entirely (confirmed by
    # reading Providers::Image::CloudflareAdapter#generate — the payload for
    # any "flux" model is only { prompt:, steps: }, nothing else survives the
    # request), so a "no nudity"/"no text" instruction only works if it's
    # written into the POSITIVE prompt text itself. These two positive clauses
    # are added to every prompt regardless of style; the matching negative
    # concepts are still appended to negative_prompt too, for any provider
    # that does honour it.
    SAFETY_POSITIVE = "fully clothed, modest attire, no nudity, no gore, no violence, family-friendly, safe for all audiences".freeze
    # Task 4.3 Part 4: broadened past "signage/captions/labels" after a real
    # render still produced a legible engraved nameplate on a machine (not a
    # sign/page/poster — the SUBJECT itself carrying incidental text) and a
    # pamphlet with fabricated Devanagari-look glyphs — the model doesn't only
    # invent gibberish Latin letters, it invents gibberish in ANY script it
    # associates with "old writing", so the clause now says script/language
    # generally rather than just "text"/"letters" (which read as Latin-only).
    NO_TEXT_POSITIVE = "no readable text, no legible writing, no letters, no writing of any script or language, " \
      "no engravings, no nameplates, no inscriptions, no signage, no captions, no labels visible".freeze
    SAFETY_NEGATIVE = "nudity, nude, topless, explicit content, gore, violence, disturbing imagery".freeze
    NO_TEXT_NEGATIVE = "text, writing, letters, characters, script, engraving, nameplate, inscription, signage, label".freeze

    # Map the per-scene content_type vocabulary onto a STYLES key.
    CONTENT_TYPE_STYLE = {
      "photorealistic" => "photorealistic",
      "cinematic" => "cinematic",
      "documentary" => "documentary",
      "wildlife" => "wildlife_documentary",
      "wildlife_documentary" => "wildlife_documentary",
      "cartoon" => "illustration",
      "2d_animation" => "illustration",
      "illustration" => "illustration",
      "watercolour" => "watercolor",
      "watercolor" => "watercolor",
      "3d_render" => "3d_animation",
      "3d_animation" => "3d_animation",
      "anime" => "anime",
      "historical" => "documentary"
    }.freeze

    # @param scene [Scene] required (the shot's scene, or a scene rendered directly)
    # @param project [Project]
    # @param shot [Shot, nil] when generating for a specific shot
    # @param brief_override [String, nil] a rewritten positive brief from a QA
    #   repair (Task 6.1 Part B); replaces the planner's brief for this call only.
    # @param setting_first [Boolean] put the project setting at the very start
    #   of the prompt (used by repairs, so the era anchors the whole image).
    # Task 6.2 Part 3 — a compiled prompt (from ImagePromptCompiler) replaces the
    # whole old assembly; its own constraints are positive, so only a short
    # positive safety clause is appended.
    COMPILED_SAFETY = "fully clothed, family-friendly, natural anatomy, clean unmarked surfaces".freeze

    def initialize(project:, scene: nil, shot: nil, brief_override: nil, setting_first: false, compiled_prompt: nil)
      @shot = shot
      @scene = scene || shot&.scene
      @brief_override = brief_override.presence
      @setting_first = setting_first
      @compiled_prompt = compiled_prompt.presence
      @project = project
      raise ArgumentError, "need a scene or a shot" if @scene.nil?
    end

    # @return [Hash] { prompt:, negative_prompt:, seed: }
    def call
      return compiled_call if @compiled_prompt

      positive, avoid = STYLES.fetch(style_key)

      # action_clause leads (right after subject) so the concrete thing the
      # narration describes gets prompt-front-position weight, instead of
      # trusting wherever the planner's own free-text `brief` happened to
      # mention it (Task 2.5 finding D: it was often buried mid-sentence).
      leading = @setting_first ? [ setting_clause ] : []
      segments = leading + [
        subject_anchor,
        action_clause,
        brief,
        environment_clause,
        framing_clause,
        (setting_clause unless @setting_first),
        SAFETY_POSITIVE,
        NO_TEXT_POSITIVE,
        positive
      ].map { |s| s.to_s.strip }.reject(&:blank?).uniq

      {
        prompt: segments.join(". "),
        negative_prompt: [ own_negative, avoid, SAFETY_NEGATIVE, NO_TEXT_NEGATIVE, setting_negative ]
                           .reject(&:blank?).join(", "),
        seed: project_seed
      }
    end

    private

    def compiled_call
      {
        prompt: "#{@compiled_prompt}, #{COMPILED_SAFETY}",
        negative_prompt: [ own_negative, SAFETY_NEGATIVE, NO_TEXT_NEGATIVE, setting_negative ].reject(&:blank?).join(", "),
        seed: project_seed
      }
    end

    def meta = @scene.metadata || {}

    # Task 6 Part C: the project's shared era/place/wardrobe, so every image
    # sits in the same world. Absent until Ai::SettingService has run.
    def project_setting = (@project.settings || {})["setting"].presence

    def setting_clause
      s = project_setting
      return nil unless s

      "Setting: #{s['era']}, #{s['place']}. Wardrobe and technology: #{s['wardrobe']}; #{s['technology']}"
    end

    def setting_negative = Array(project_setting&.dig("avoid")).join(", ").presence


    def style_key
      by_content = CONTENT_TYPE_STYLE[@scene.content_type.to_s.downcase] if @scene.content_type.present?
      by_content ||
        (@project.visual_style if STYLES.key?(@project.visual_style)) ||
        DEFAULT_STYLE
    end

    # The bare shot/scene brief written by the planner.
    def brief
      return @brief_override.to_s.strip if @brief_override

      (@shot&.visual_prompt.presence || @scene.visual_prompt).to_s.strip
    end

    # Force the subject to lead the prompt so the model can't drop it
    # ("close-up of an eye" -> a human eye). No-op if the brief already opens
    # with the subject.
    def subject_anchor
      subject = meta["subject"].to_s.strip
      subject = @project.niche.to_s.strip if subject.blank?
      return nil if subject.blank?
      return nil if brief.downcase.start_with?(subject.downcase[0, 24])

      subject
    end

    # Not deduped against `brief` the way subject/environment are — the point
    # is to guarantee the action appears EARLY regardless of where (or
    # whether prominently) the planner's own free-text brief mentions it.
    def action_clause
      (@shot&.action.presence || @scene.action).to_s.strip.presence
    end

    def environment_clause
      env = meta["environment"].to_s.strip
      return nil if env.blank?
      return nil if brief.downcase.include?(env.downcase[0, 24])

      env
    end

    def framing_clause
      f = @shot&.framing.presence || @scene.camera["framing"]
      st = @shot&.shot_type.presence || @scene.camera["shot_type"]
      [ st, f ].compact.map { |x| x.to_s.tr("_", " ") }.reject(&:blank?).uniq.join(", ").presence
    end

    def own_negative
      (@shot&.negative_prompt.presence || @scene.negative_prompt).to_s.strip
    end

    def project_seed
      @project.image_seed || begin
        seed = Digest::SHA256.hexdigest(@project.public_id)[0, 8].to_i(16) % 2_147_483_647
        @project.update_column(:image_seed, seed)
        seed
      end
    end
  end
end
