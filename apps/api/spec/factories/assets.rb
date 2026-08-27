FactoryBot.define do
  factory :asset do
    project
    asset_type { "image" }
    source_type { "ai_generated" }
    provider { "gemini" }
    model { "nano-banana" }
    prompt { Faker::Lorem.sentence }
    width { 1920 }
    height { 1080 }
    cost_usd { 0.002 }
  end
end
