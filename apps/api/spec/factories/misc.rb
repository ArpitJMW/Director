FactoryBot.define do
  factory :source do
    project
    url { Faker::Internet.url }
    title { Faker::Book.title }
    publisher { Faker::Book.publisher }
    reliability { "medium" }
    provided_by { "research_engine" }
  end

  factory :template do
    sequence(:slug) { |n| "template-#{n}" }
    name { "Template #{Faker::Color.color_name.capitalize}" }
    category { "explainer" }
  end

  factory :template_version do
    template
    sequence(:version) { |n| n }
    config { { typography: { body: "Inter" }, colors: { text: "#000" } } }
  end

  factory :ai_generation do
    project
    kind { "script" }
    provider_kind { "llm" }
    provider { "anthropic" }
    model { "claude-sonnet-5" }
    status { "succeeded" }
    cost_usd { 0.01 }
  end

  factory :generation_job do
    project
    stage { "script" }
    queue { "script" }
  end

  factory :video_render do
    project
    width { 1920 }
    height { 1080 }
    fps { 30 }
  end

  factory :voice_generation do
    project
    provider { "elevenlabs" }
    voice_id { "rachel" }
    text { Faker::Lorem.paragraph }
    status { "pending" }
  end

  factory :preflight_report do
    project
    status { "review_required" }
    ai_disclosure { "review" }
  end
end
