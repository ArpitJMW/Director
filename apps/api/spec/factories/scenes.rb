FactoryBot.define do
  factory :scene do
    project
    narration { Faker::Lorem.paragraph }
    visual_type { "image" }
    visual_prompt { Faker::Lorem.sentence }
    duration_seconds { 6 }
    animation { "ken_burns" }
    transition { "fade" }
  end
end
