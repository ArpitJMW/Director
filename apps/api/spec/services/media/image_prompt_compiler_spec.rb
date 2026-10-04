require "rails_helper"

RSpec.describe Media::ImagePromptCompiler do
  let(:project) { create(:project, settings: {}) }
  let(:scene) { create(:scene, project: project, action: "a scribe copies a page", metadata: { "subject" => "a scribe" }) }
  let(:compiler) { described_class.new(project: project, scene: scene, provider: double("llm", name: "fake", default_model: "fake-1")) }

  let(:sheet) { "A woman in her thirties with a slim build, shoulder-length black hair and warm brown skin wears a crisp white cotton shirt with rolled sleeves." }
  let(:unit) { { id: "s1", subject: "a scribe", action: "copies", camera: "static", mood: "calm", framing: "medium" } }

  # Shot text (sentences 1-5 of v3), about 60-70 words, with the given shot size.
  def body(size: "medium shot")
    "She holds a brass pen above a folded cloth on a wooden counter. " \
      "Behind her are a tiled wall, copper pans on hooks and a window with white linen curtains. " \
      "#{size}, eye level, 85mm lens, shallow depth of field. " \
      "Soft morning light falls from the left window onto her hands, with cool blue shadows on the counter. " \
      "Warm ivory and indigo palette, clean natural documentary style."
  end

  def long_body
    body + (" Extra detail about the pale room with a wooden floor and a shelf of tools." * 8)
  end

  def reply(prompts, sheet_text: sheet)
    Providers::LLM::Result.new(
      text: { sheet: sheet_text, prompts: prompts.map { |id, text| { id: id, text: text } } }.to_json,
      model: "fake-1", provider: "fake", stop_reason: "stop",
      usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: nil, raw: nil
    )
  end

  def llm_returning(*replies)
    llm = double("llm", name: "fake", default_model: "fake-1")
    allow(llm).to receive(:chat).and_return(*replies)
    llm
  end

  describe "hard checks (reject the shot)" do
    let(:checker) { described_class.new(project: project, scene: scene, provider: double("llm", name: "fake", default_model: "x")) }

    it "passes a complete prompt with the planned shot size" do
      expect(checker.hard_reasons("#{sheet} #{body}", unit, sheet)).to be_empty
    end

    it "rejects text-bearing props and readable writing" do
      expect(checker.hard_reasons("#{sheet} #{body} A menu board shows the prices.", unit, sheet).join).to match(/text-bearing/)
      expect(checker.hard_reasons("#{sheet} #{body} Newspaper folded on the counter.", unit, sheet).join).to match(/text-bearing/)
      expect(checker.hard_reasons("#{sheet} #{body} Bold lettering on the wall.", unit, sheet).join).to match(/text-bearing/)
      expect(checker.hard_reasons("#{sheet} #{body} A screen showing a headline.", unit, sheet).join).to match(/text-bearing/)
    end

    it "rejects a shot size that differs from the planned framing" do
      expect(checker.hard_reasons("#{sheet} #{body(size: 'close-up')}", unit, sheet).join).to match(/planned medium/)
      expect(checker.hard_reasons("#{sheet} #{body(size: 'medium close-up')}", unit, sheet).join).to match(/planned medium/)
    end

    it "rejects a text with no shot size when one is planned" do
      no_size = body.sub("medium shot, ", "")
      expect(checker.hard_reasons("#{sheet} #{no_size}", unit, sheet).join).to match(/shot size missing/)
    end

    it "rejects a subject sheet that is not reused verbatim" do
      expect(checker.hard_reasons("A different person. #{body}", unit, sheet).join).to match(/not reused verbatim/)
    end

    it "rejects length outside 60-140 words" do
      expect(checker.hard_reasons("#{sheet} #{long_body}", unit, sheet).join).to match(/words/)
      expect(checker.hard_reasons("a short line", unit, sheet).join).to match(/words/)
    end

    it "rejects negation and named styles" do
      expect(checker.hard_reasons("#{sheet} #{body} No smartphones.", unit, sheet).join).to match(/negation/)
      expect(checker.hard_reasons("#{sheet} #{body} Cinematic.", unit, sheet).join).to match(/named style/)
    end
  end

  describe "soft checks (logged, prompt kept)" do
    let(:checker) { described_class.new(project: project, scene: scene, provider: double("llm", name: "fake", default_model: "x")) }

    it "reports motion over time and stray words without rejecting the prompt" do
      text = "#{sheet} #{body} The camera slowly pushes in and the letters look sharp."
      expect(checker.hard_reasons(text, unit, sheet)).to be_empty
      expect(checker.soft_reasons(text).join).to match(/motion over time/).and match(/stray word 'letters'/)
    end
  end

  it "places the stored subject sheet verbatim in front of every shot in the scene" do
    llm = llm_returning(reply({ "s1" => body, "s2" => body(size: "close-up") }))
    units = [ unit, unit.merge(id: "s2", framing: "close") ]
    out = described_class.new(project: project, scene: scene, provider: llm).call(units)

    expect(out.values.map(&:source)).to all(eq("compiled"))
    expect(out["s1"].prompt).to start_with(sheet)
    expect(out["s2"].prompt).to start_with(sheet)
    expect(scene.reload.metadata["subject_sheet"]).to eq(sheet)
  end

  it "reuses the stored sheet on a later call, whatever the model writes for it" do
    scene.update!(metadata: scene.metadata.merge("subject_sheet" => sheet, "subject_sheet_for" => "a scribe"))
    llm = llm_returning(reply({ "s1" => body }, sheet_text: "A different person entirely."))
    out = described_class.new(project: project, scene: scene, provider: llm).call([ unit ])

    expect(out["s1"].prompt).to start_with(sheet)
    expect(out["s1"].prompt).not_to include("different person")
  end

  it "retries only the failing shot, with its reason, and keeps the passing shot" do
    retry_units = nil
    llm = double("llm", name: "fake", default_model: "fake-1")
    allow(llm).to receive(:chat) do |**args|
      user = args[:messages].first[:content]
      if user.include?("RETRY")
        retry_units = user
        reply({ "s2" => body(size: "close-up") })
      else
        reply({ "s1" => body, "s2" => "#{body(size: 'close-up')} A menu board shows prices." })
      end
    end
    out = described_class.new(project: project, scene: scene, provider: llm).call([ unit, unit.merge(id: "s2", framing: "close") ])

    expect(out["s1"].source).to eq("compiled")
    expect(out["s2"].source).to eq("compiled")
    expect(retry_units).to include("id s2").and include("text-bearing")
    expect(retry_units).not_to include("id s1:")
  end

  it "falls back only the shot whose retry still fails; the rest of the scene stays compiled" do
    bad = "#{body} A menu board shows prices."
    llm = double("llm", name: "fake", default_model: "fake-1")
    allow(llm).to receive(:chat).and_return(
      reply({ "s1" => body, "s2" => bad }),
      reply({ "s2" => bad })
    )
    out = described_class.new(project: project, scene: scene, provider: llm).call([ unit, unit.merge(id: "s2") ])

    expect(out["s1"].source).to eq("compiled")
    expect(out["s2"].source).to eq("fallback")
    expect(out["s2"].prompt).to be_nil
    gen = AiGeneration.where(project: project, kind: "visual_prompt").last
    expect(gen.response["compile_source"]).to eq("partial")
    expect(gen.response["compile_reasons"].keys).to eq([ "s2" ])
  end

  it "records raw pass, reasons, retried shots, soft notes and the model on the generation" do
    llm = llm_returning(reply({ "s1" => "#{body} A menu board shows prices." }), reply({ "s1" => "#{body} A menu board shows prices." }))
    described_class.new(project: project, scene: scene, provider: llm).call([ unit ])

    gen = AiGeneration.where(project: project, kind: "visual_prompt").last
    expect(gen.response["compile_source"]).to eq("fallback")
    expect(gen.response["raw_pass"]).to eq(0)
    expect(gen.response["raw_reasons"].join).to match(/text-bearing/)
    expect(gen.response["retried_ids"]).to eq([ "s1" ])
    expect(gen.model).to eq("fake-1")
  end

  it "uses the lighter stage model on Groq and records it" do
    groq = double("llm", name: "groq", default_model: "openai/gpt-oss-120b")
    expect(groq).to receive(:chat).with(hash_including(model: "openai/gpt-oss-20b", reasoning_effort: "low")).and_return(
      reply({ "s1" => body })
    )
    described_class.new(project: project, scene: scene, provider: groq).call([ unit ])

    expect(AiGeneration.where(project: project, kind: "visual_prompt").last.model).to eq("openai/gpt-oss-20b")
  end

  it "records the prompt version on the generation" do
    llm = llm_returning(reply({ "s1" => body }))
    out = described_class.new(project: project, scene: scene, provider: llm).call([ unit ])

    expect(out["s1"].prompt_version).to eq(3)
    expect(AiGeneration.where(project: project, kind: "visual_prompt").last.request["prompt_version"]).to eq(3)
  end

  it "falls back for every shot when the reply has no subject sheet" do
    llm = llm_returning(reply({ "s1" => body }, sheet_text: ""))
    out = described_class.new(project: project, scene: scene, provider: llm).call([ unit ])

    expect(out["s1"].source).to eq("fallback")
  end
end
