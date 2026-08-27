FactoryBot.define do
  factory :project do
    user
    title { "How #{Faker::Science.scientist} changed the world" }
    topic { Faker::Lorem.sentence }
    format { "youtube_long" }
    aspect_ratio { "16:9" }
    target_duration_seconds { 120 }
  end
end
