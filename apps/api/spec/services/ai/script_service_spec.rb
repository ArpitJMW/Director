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
end
