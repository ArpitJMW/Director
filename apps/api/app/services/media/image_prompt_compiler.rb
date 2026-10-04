module Media
  # Task 7.3: a rich image prompt per shot (prompt v3), written by one batched LLM
  # call per scene. The scene gets ONE subject sheet (the recurring person or
  # object, with fixed wardrobe and colours), stored on the scene and placed
  # verbatim in front of every shot, so the same subject is described the same way
  # in every frame.
  #
  # Checks are split in two:
  # - HARD (rejects that shot): the sheet not reused verbatim, text-bearing props,
  #   a shot size that differs from the planned framing, negation, a named style,
  #   or a length outside 60-140 words.
  # - SOFT (logged as a warning, prompt kept): motion-over-time words, "the camera",
  #   and stray words such as "letters" that do not ask for readable writing.
  #
  # A shot with a HARD failure gets ONE targeted retry, with its reasons in the
  # instruction. If the retry still fails, only that shot falls back to the old
  # ImagePromptBuilder prompt. The rest of the scene keeps its compiled prompts.
  class ImagePromptCompiler
    PROMPT_NAME = "image_prompt".freeze
    # The planning model is unchanged; this stage runs on the lighter model so the
    # compile calls do not spend the planning quota. Override with IMAGE_PROMPT_MODEL.
    MODEL = ENV.fetch("IMAGE_PROMPT_MODEL", "openai/gpt-oss-20b").freeze
    WORDS = (60..140).freeze
    NEGATION = /\b(no|not|without|avoid|avoids|never|nothing|free of)\b/i
    NAMED_STYLE = /\b(in the style of|inspired by|style of)\b|\bcinematic\b|\b4k\b|\banamorphic\b/i
    # Text-bearing props and readable writing: the image model would draw gibberish.
    HARD_TEXT = /\b(signage|signs?|menu boards?|menus?|newspapers?|posters?|nameplates?|banners?|labels?|pamphlets?|magazines?|inscriptions?|logos?|headlines?|emblems?|heraldic|maps?|documents?|(?:written|printed|open|text) pages?|screens? (?:showing|displaying)|lettering|readable|handwriting)\b/i
    # Stray words: logged, not rejected.
    SOFT_TEXT = /\b(letters?|characters?|script|writing|written|words?|text)\b/i
    # Motion over time cannot be shown by a still: logged, not rejected.
    SOFT_MOTION = /\b(camera|slowly|gently|gradually|begins? to|starts? to|continues?|over time|zooms?|moves?|weaves?|walks?|rushes?|pans? (?:left|right|across|up|down))\b/i
    SHOT_SIZE = {
      "wide" => "wide shot", "medium_wide" => "medium wide shot", "medium" => "medium shot",
      "close" => "close-up", "extreme_close" => "extreme close-up"
    }.freeze
    SIZE_TERMS = /\b(?:extreme close[- ]up|medium[- ]close[- ]up|medium[- ]wide shot|medium[- ]wide|medium shot|close[- ]up|wide shot|establishing shot|long shot)\b/i

    Result = Data.define(:prompt, :source, :prompt_version)

    def initialize(project:, scene:, provider: Providers.llm)
      @project = project
      @scene = scene
      @provider = provider
    end

    # @param units [Array<Hash>] { id:, subject:, action:, camera:, mood:, framing: }
    # @return [Hash] id => Result (prompt is nil for a shot that fell back)
    def call(units)
      return {} if units.empty?

      @prompt = Prompts.load(PROMPT_NAME)
      @sheet = stored_sheet
      first = ask(units, nil)
      @sheet ||= first[:sheet]
      return fallback_all(units, [ "no subject sheet in the reply" ]) if @sheet.blank?

      texts = assemble_all(first, @sheet, units)
      @raw_texts = texts
      hard = hard_by_shot(texts, units)
      @raw_pass = hard.values.count(&:empty?)
      @raw_reasons = hard.values.flatten
      @retried_ids = units.map { |u| u[:id] }.select { |id| hard[id].any? }

      if @retried_ids.any?
        retry_units = units.select { |u| @retried_ids.include?(u[:id]) }
        reply = ask(retry_units, retry_note(retry_units, hard))
        retry_units.each { |u| texts[u[:id]] = assemble(reply, @sheet, u) if reply[:prompts][u[:id]].present? }
        hard = hard_by_shot(texts, units)
      end

      save_sheet(@sheet) unless stored_sheet
      soft = units.to_h { |u| [ u[:id], hard[u[:id]].empty? ? soft_reasons(texts[u[:id]]) : [] ] }
      results = units.to_h do |u|
        id = u[:id]
        if hard[id].any?
          [ id, Result.new(prompt: nil, source: "fallback", prompt_version: @prompt.version) ]
        else
          [ id, Result.new(prompt: texts[id], source: "compiled", prompt_version: @prompt.version) ]
        end
      end
      record_outcome(units, hard, soft)
      results
    rescue => e
      fallback_all(units, [ "exception: #{e.message.to_s.truncate(160)}" ])
    end

    # Hard reasons for one prompt, or [] when it passes. Public for specs.
    def hard_reasons(text, unit, sheet = @sheet)
      id = unit[:id]
      return [ "#{id}: missing" ] if text.blank?

      reasons = []
      reasons << "#{id}: #{text.split.size} words (need #{WORDS.min}-#{WORDS.max})" unless WORDS.cover?(text.split.size)
      reasons << "#{id}: subject sheet not reused verbatim" if sheet.present? && !text.start_with?(sheet)
      reasons << "#{id}: negation '#{text[NEGATION]}'" if text =~ NEGATION
      reasons << "#{id}: named style '#{text[NAMED_STYLE]}'" if text =~ NAMED_STYLE
      reasons << "#{id}: text-bearing '#{text[HARD_TEXT]}'" if text =~ HARD_TEXT
      reasons << framing_reason(text, unit) if framing_reason(text, unit)
      reasons.compact
    end

    # Soft reasons: reported, never rejected. Public for specs.
    def soft_reasons(text)
      found = []
      found << "motion over time '#{text[SOFT_MOTION]}'" if text =~ SOFT_MOTION
      found << "stray word '#{text[SOFT_TEXT]}'" if text =~ SOFT_TEXT
      found
    end

    # Size from the planner is a fixed input: the prompt must state that size and
    # no other. Lens and depth of field may be added, the size may not change.
    def framing_reason(text, unit)
      planned = unit[:framing]
      return nil if planned.blank?

      stated = text.scan(SIZE_TERMS).map { |term| size_class(term) }.uniq
      return nil if stated == [ planned ]

      "#{unit[:id]}: shot size #{stated.empty? ? 'missing' : stated.join('/')}, planned #{planned}"
    end

    private

    def size_class(term)
      t = term.downcase
      return "extreme_close" if t.include?("extreme")
      return "medium_close" if t.match?(/medium[- ]close/)
      return "medium_wide" if t.match?(/medium[- ]wide/)
      return "medium" if t.include?("medium")
      return "close" if t.include?("close")

      "wide"
    end

    def hard_by_shot(texts, units)
      units.to_h { |u| [ u[:id], hard_reasons(texts[u[:id]], u, @sheet) ] }
    end

    def retry_note(units, hard)
      lines = units.map { |u| "- id #{u[:id]}: #{hard[u[:id]].join('; ')}" }
      [ "RETRY for these shots only. Rewrite each listed shot's text and fix the problem named for it.",
        "Keep the SHOT SIZE, keep the stored subject sheet, and reply with JSON only.",
        *lines ].join("\n")
    end

    def fallback_all(units, reasons)
      log("compiler reply broke the contract (#{Array(reasons).join('; ').truncate(300)}); the old prompt is used for this scene")
      record_outcome(units, units.to_h { |u| [ u[:id], reasons ] }, {})
      units.to_h { |u| [ u[:id], Result.new(prompt: nil, source: "fallback", prompt_version: @prompt&.version) ] }
    end

    # One chat call. The model is the lighter stage model on Groq; other
    # providers keep their own default.
    def ask(units, note)
      result = AiGeneration.track!(
        project: @project, scene: @scene, kind: "visual_prompt", provider_kind: "llm",
        provider: @provider.name, model: chat_model,
        request: { prompt_version: @prompt.version, shots: units.map { |u| u[:id] }, retry: note.present?,
                   sheet_reused: @sheet.present?, model: chat_model }
      ) do |gen|
        @generation = gen
        @provider.chat(system: @prompt.text, messages: [ { role: "user", content: user_prompt(units, note) } ],
                       max_tokens: 3000, **chat_options)
      end
      parse(result.text)
    end

    def chat_model = @provider.name == "groq" ? MODEL : @provider.default_model

    # Task 7.2: a short structured task does not need deep reasoning; "low"
    # cut the output from ~1,175 to ~600 tokens on the same call.
    def chat_options
      return {} unless @provider.name == "groq"

      { model: MODEL, reasoning_effort: "low" }
    end

    # The sheet goes in front of the shot text, byte for byte, so the wardrobe and
    # object descriptions are identical across the scene's shots.
    def assemble(reply, sheet, unit)
      text = reply[:prompts][unit[:id]].to_s.strip
      text.empty? ? "" : [ sheet, text ].join(" ")
    end

    def assemble_all(reply, sheet, units)
      units.to_h { |u| [ u[:id], assemble(reply, sheet, u) ] }
    end

    def stored_sheet
      meta = @scene.metadata || {}
      meta["subject_sheet"].presence if meta["subject_sheet_for"] == meta["subject"]
    end

    def save_sheet(sheet)
      meta = @scene.metadata || {}
      @scene.update!(metadata: meta.merge("subject_sheet" => sheet, "subject_sheet_for" => meta["subject"]))
    end

    def parse(text)
      data = JSON.parse(text.to_s.strip.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, ""))
      raise ArgumentError, "no prompts array" unless data.is_a?(Hash) && data["prompts"].is_a?(Array)

      prompts = data["prompts"].select { |e| e.is_a?(Hash) }.to_h do |e|
        [ e["id"].to_s, (e["text"] || e["prompt"]).to_s.strip ]
      end
      { sheet: data["sheet"].to_s.strip, prompts: prompts }
    end

    def user_prompt(units, note)
      look = (@project.settings || {})["look"]
      setting = (@project.settings || {})["setting"]
      sheet_line = if @sheet.present?
                     "STORED SUBJECT SHEET (reused as given; reply with \"sheet\": \"\"): #{@sheet}"
                   else
                     "No stored subject sheet yet: write \"sheet\" for this scene."
                   end
      shots = units.map do |u|
        size = SHOT_SIZE[u[:framing]] ? "\"#{SHOT_SIZE[u[:framing]]}\"" : "(choose a size)"
        "- id #{u[:id]}: SHOT SIZE #{size}; subject #{u[:subject]}; action #{u[:action]}; camera #{u[:camera]}; mood #{u[:mood]}"
      end
      [ "Respond with JSON only.", "LOOK: #{look.to_json}", "SETTING: #{setting.to_json}", sheet_line,
        "SHOTS:", *shots, note ].compact.join("\n")
    end

    # Reasons and raw texts live on the AI generation record, which outlives the
    # project (its project link is nullified, not deleted).
    def record_outcome(units, hard, soft)
      failed = units.map { |u| u[:id] }.select { |id| hard[id].any? }
      source = if failed.empty? then "compiled"
               elsif failed.size == units.size then "fallback"
               else "partial"
               end
      soft_notes = soft.transform_values { |list| list }.reject { |_, list| list.empty? }
      log("soft notes (kept): #{soft_notes.to_json.truncate(300)}") if soft_notes.any?
      log("#{failed.join(', ')} fell back after one targeted retry: #{failed.map { |id| hard[id].join('; ') }.join(' | ').truncate(300)}") if failed.any?
      return unless @generation

      @generation.update!(response: @generation.response.to_h.merge(
        "compile_source" => source, "compile_model" => chat_model,
        "compile_reasons" => failed.to_h { |id| [ id, hard[id] ] }, "compile_soft" => soft_notes,
        "raw_pass" => @raw_pass, "raw_reasons" => @raw_reasons, "retried_ids" => @retried_ids,
        "raw_texts" => @raw_texts
      ))
    end

    def log(message)
      GenerationLog.create!(project: @project, scene: @scene, level: "warn", stage: "assets",
                            message: "#{@scene.key}: #{message}")
    end
  end
end
