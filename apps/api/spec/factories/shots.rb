FactoryBot.define do
  factory :shot do
    scene
    duration_seconds { 4 }
    shot_type { "static" }
    visual_type { "image" }
    visual_prompt { Faker::Lorem.sentence }
  end
end
