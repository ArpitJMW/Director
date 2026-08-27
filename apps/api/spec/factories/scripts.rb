FactoryBot.define do
  factory :script do
    project
    selected_title { "The story of #{Faker::Space.planet}" }
    hook { Faker::Lorem.sentence }
    story_angle { Faker::Lorem.sentence }
    full_narration { Faker::Lorem.paragraphs(number: 3).join("\n\n") }
    estimated_duration_seconds { 120 }
    source_type { "ai_generated" }
  end
end
