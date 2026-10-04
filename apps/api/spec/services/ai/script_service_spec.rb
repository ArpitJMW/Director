require "rails_helper"

RSpec.describe Ai::ScriptService do
  let(:project) { create(:project, topic: "How aqueducts moved water", target_duration_seconds: 90) }

  it "creates a current script from the provider output" do
    expect { described_class.new(project: project).call }.to change(project.scripts, :count).by(1)

    script = project.reload.current_script
    expect(script.source_type).to eq("ai_generated")
    expect(script.title_options.size).to eq(3)
    expect(script.selected_title).to be_present
    expect(script.full_narration).to be_present
    expect(script.sections).to be_an(Array)
  end

  it "records an ai_generation with cost and tokens and links it to the script" do
    script = described_class.new(project: project).call

    generation = project.ai_generations.where(kind: "script").last
    expect(generation.status).to eq("succeeded")
    expect(generation.total_tokens).to be > 0
    expect(generation.provider).to eq("fake")
    expect(script.ai_generation).to eq(generation)
  end

  it "writes a log line" do
    described_class.new(project: project).call
    expect(project.generation_logs.where(stage: "script")).to be_present
  end

  it "honours a length stated in the topic text over the form default" do
    project.update!(topic: "Make a 30-40 second video about how aqueducts moved water")
    described_class.new(project: project).call
    expect(project.reload.target_duration_seconds).to eq(35)
  end

  it "raises and marks the generation failed on bad JSON" do
    bad = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
    allow(bad).to receive(:chat).and_return(
      Providers::LLM::Result.new(
        text: "not json", model: "fake-1", provider: "fake", stop_reason: "end_turn",
        usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
      )
    )

    expect {
      described_class.new(project: project, provider: bad).call
    }.to raise_error(Ai::ScriptService::Error, /did not parse/)

    expect(project.ai_generations.last.status).to eq("failed")
  end

  describe "word budget + condense pass (Phase 1 Task 4.2)" do
    def script_result(overrides)
      base = {
        title_options: %w[A B C], selected_title: "A", hook: "hi",
        story_angle: "angle", sections: [ { heading: "one", narration: overrides.fetch(:full_narration) } ],
        full_narration: overrides.fetch(:full_narration), estimated_duration_seconds: 45,
        creative_notes: "", claims: []
      }.merge(overrides)
      Providers::LLM::Result.new(
        text: base.to_json, model: "fake-1", provider: "fake", stop_reason: "end_turn",
        usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
      )
    end

    def stub_chat_sequence(provider, *results)
      call_count = 0
      allow(provider).to receive(:chat) do
        result = results[call_count] || results.last
        call_count += 1
        result
      end
    end

    let(:project) { create(:project, topic: "Topic", target_duration_seconds: 45) }
    let(:budget) { described_class.new(project: project).send(:word_budget) }

    it "computes the word budget from target_duration_seconds, the measured wps, and scene-boundary gaps (Task 6.1 Part C)" do
      # Task 6.1 Part C subtracts ~0.45s of boundary gap per estimated scene.
      expect(budget).to eq(87)
    end

    it "interpolates the budget into the script prompt" do
      provider = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      allow(provider).to receive(:chat).and_return(script_result(full_narration: "short narration"))

      described_class.new(project: project, provider: provider).call

      expect(provider).to have_received(:chat).with(hash_including(system: include("between 83 and #{budget} words")))
    end

    it "logs actual words vs budget and does NOT condense when under budget" do
      provider = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      short = ([ "word" ] * (budget - 5)).join(" ")
      allow(provider).to receive(:chat).and_return(script_result(full_narration: short))

      described_class.new(project: project, provider: provider).call

      expect(provider).to have_received(:chat).once
      log = project.generation_logs.where(stage: "script").order(:created_at).find { |l| l.message.include?("words vs") }
      expect(log.message).to include("#{budget - 5} words").and include("#{budget}-word budget")
      expect(project.reload.current_script.full_narration.split.size).to eq(budget - 5)
    end

    it "runs exactly ONE condense pass when narration exceeds budget by more than 10%, and keeps the condensed result" do
      provider = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      long = ([ "word" ] * (budget * 2)).join(" ")
      condensed = ([ "word" ] * (budget - 2)).join(" ")
      stub_chat_sequence(provider, script_result(full_narration: long), script_result(full_narration: condensed))

      script = described_class.new(project: project, provider: provider).call

      expect(provider).to have_received(:chat).twice
      expect(script.full_narration.split.size).to eq(budget - 2)
      expect(project.ai_generations.where(kind: "script_condense").last.status).to eq("succeeded")
      log = project.generation_logs.where(stage: "script").find { |l| l.message.include?("condense pass") }
      expect(log.message).to include("#{budget * 2} -> #{budget - 2}")
    end

    it "never runs a second condense pass even if the condensed draft is still over budget" do
      provider = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      long = ([ "word" ] * (budget * 3)).join(" ")
      still_long = ([ "word" ] * (budget * 2)).join(" ") # condense pass helped, but still over
      stub_chat_sequence(provider, script_result(full_narration: long), script_result(full_narration: still_long))

      script = described_class.new(project: project, provider: provider).call

      expect(provider).to have_received(:chat).twice # never a third call
      expect(script.full_narration.split.size).to eq(budget * 2)
    end

    it "keeps the original narration (and logs a warning) when the condense pass itself fails" do
      provider = instance_double(Providers::LLM::FakeAdapter, name: "fake", default_model: "fake-1")
      long = ([ "word" ] * (budget * 2)).join(" ")
      failing = Providers::LLM::Result.new(
        text: "not json", model: "fake-1", provider: "fake", stop_reason: "end_turn",
        usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: "x", raw: nil
      )
      stub_chat_sequence(provider, script_result(full_narration: long), failing)

      script = described_class.new(project: project, provider: provider).call

      expect(script.full_narration.split.size).to eq(budget * 2)
      log = project.generation_logs.where(stage: "script", level: "warn").last
      expect(log.message).to include("condense pass failed")
    end
  end
end

RSpec.describe Ai::ScriptService, "word budget (Task 6.1 Part C)" do
  it "subtracts scene-boundary gaps before converting seconds to words" do
    # 45s -> 8 estimated scenes -> 41.4s of speech -> 91.9 words -> 87 after the 0.95 margin
    expect(described_class.word_budget_for(45)).to eq(87)
  end

  it "grows with the target but never by the full target's worth" do
    expect(described_class.word_budget_for(60)).to be > described_class.word_budget_for(45)
    expect(described_class.word_budget_for(60)).to be < 60 * described_class::MEASURED_WORDS_PER_SECOND
  end
end

RSpec.describe Ai::ScriptService, "length range (Task 6.2 Part B)" do
  let(:project) { create(:project, topic: "Topic", target_duration_seconds: 45) }
  let(:budget) { 87 }

  def script_json(words)
    { title_options: [ "T" ], selected_title: "T", hook: "h", story_angle: "a",
      sections: [ { heading: "h", narration: "x" } ],
      full_narration: (1..words).map { |i| "w#{i}" }.join(" ") }.to_json
  end

  def counting_provider(reply)
    calls = []
    fake = double("llm", name: "fake", default_model: "fake-1")
    allow(fake).to receive(:chat) do |**kw|
      calls << kw
      Providers::LLM::Result.new(text: reply, model: "fake-1", provider: "fake", stop_reason: "stop",
                                 usage: { input_tokens: 1, output_tokens: 1 }, provider_request_id: nil, raw: nil)
    end
    [ fake, calls ]
  end

  it "runs ONE expand pass when the script is under 90% of the budget" do
    fake, calls = counting_provider(script_json(85))
    data = JSON.parse(script_json(60))

    described_class.new(project: project, provider: fake).send(:enforce_word_budget, data, budget)

    expect(calls.size).to eq(1)
    expect(calls.first[:system]).to include("expand")
  end

  it "accepts a script between 90% and 110% of the budget without another call" do
    fake, calls = counting_provider(script_json(80))
    data = JSON.parse(script_json(84))

    result = described_class.new(project: project, provider: fake).send(:enforce_word_budget, data, budget)

    expect(calls).to be_empty
    expect(result).to eq(data)
  end

  it "runs the condense pass above 110% of the budget, not the expand pass" do
    fake, calls = counting_provider(script_json(80))
    data = JSON.parse(script_json(120))

    described_class.new(project: project, provider: fake).send(:enforce_word_budget, data, budget)

    expect(calls.size).to eq(1)
    expect(calls.first[:system]).not_to include("expand")
  end

  it "keeps the short original and logs a warning when the expand call fails" do
    fake = double("llm", name: "fake", default_model: "fake-1")
    allow(fake).to receive(:chat).and_raise(StandardError.new("upstream down"))
    data = JSON.parse(script_json(60))

    result = described_class.new(project: project, provider: fake).send(:enforce_word_budget, data, budget)

    expect(result).to eq(data)
    expect(project.generation_logs.where(level: "warn").pluck(:message).join).to match(/expand pass failed/)
  end
end
