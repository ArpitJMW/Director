# Idempotent seeds. Run with `bin/rails db:seed`.

# --- Initial templates (spec §24) -------------------------------------------
# Each template is configuration + design language, not a fixed script.
TEMPLATES = [
  {
    slug: "dark-documentary",
    name: "Dark Documentary",
    category: "documentary",
    description: "High-contrast cinematic look for serious, narrative-driven topics.",
    config: {
      typography: { heading: "Playfair Display", body: "Inter", scale: 1.15 },
      colors: { background: "#0a0a0a", text: "#f5f5f5", accent: "#c8a24a" },
      caption_rules: { position: "lower-third", max_lines: 2, animation: "fade-up" },
      animation_rules: { default: "ken_burns", intensity: 0.12 },
      transition_rules: { default: "fade", duration: 0.6 },
      audio_rules: { music_bed_level: 0.12, ducking: true },
      scene_presets: { intro: "quote_card", outro: "quote_card" },
      thumbnail_style: { treatment: "grain-vignette", title_weight: 800 }
    }
  },
  {
    slug: "modern-tech",
    name: "Modern Tech",
    category: "explainer",
    description: "Clean, bright, product-style visuals for technology and software topics.",
    config: {
      typography: { heading: "Space Grotesk", body: "Inter", scale: 1.0 },
      colors: { background: "#0f172a", text: "#e2e8f0", accent: "#38bdf8" },
      caption_rules: { position: "center-bottom", max_lines: 2, animation: "pop" },
      animation_rules: { default: "scale", intensity: 0.08 },
      transition_rules: { default: "slide", duration: 0.4 },
      audio_rules: { music_bed_level: 0.15, ducking: true },
      scene_presets: { intro: "text_animation", outro: "text_animation" },
      thumbnail_style: { treatment: "flat-gradient", title_weight: 700 }
    }
  },
  {
    slug: "historical-documentary",
    name: "Historical Documentary",
    category: "documentary",
    description: "Warm, archival tone with map and timeline emphasis for history topics.",
    config: {
      typography: { heading: "Cormorant Garamond", body: "Lora", scale: 1.2 },
      colors: { background: "#1c1917", text: "#f5f0e6", accent: "#b08968" },
      caption_rules: { position: "lower-third", max_lines: 2, animation: "fade" },
      animation_rules: { default: "pan", intensity: 0.1 },
      transition_rules: { default: "fade", duration: 0.8 },
      audio_rules: { music_bed_level: 0.1, ducking: true },
      scene_presets: { emphasis: %w[map timeline] },
      thumbnail_style: { treatment: "sepia-frame", title_weight: 700 }
    }
  },
  {
    slug: "cartoon-explainer",
    name: "Cartoon Explainer",
    category: "explainer",
    description: "Playful, colorful, character-friendly style for light educational content.",
    config: {
      typography: { heading: "Baloo 2", body: "Nunito", scale: 1.05 },
      colors: { background: "#fffdf7", text: "#2b2b2b", accent: "#ff6b6b" },
      caption_rules: { position: "center-bottom", max_lines: 2, animation: "bounce" },
      animation_rules: { default: "scale", intensity: 0.15 },
      transition_rules: { default: "zoom", duration: 0.35 },
      audio_rules: { music_bed_level: 0.18, ducking: true },
      scene_presets: { intro: "text_animation" },
      thumbnail_style: { treatment: "sticker-outline", title_weight: 800 }
    }
  },
  {
    slug: "minimal-educational",
    name: "Minimal Educational",
    category: "educational",
    description: "Restrained, text-forward layout that keeps focus on the explanation.",
    config: {
      typography: { heading: "Inter", body: "Inter", scale: 1.0 },
      colors: { background: "#ffffff", text: "#111827", accent: "#2563eb" },
      caption_rules: { position: "center", max_lines: 3, animation: "fade" },
      animation_rules: { default: "none", intensity: 0.0 },
      transition_rules: { default: "cut", duration: 0.0 },
      audio_rules: { music_bed_level: 0.08, ducking: true },
      scene_presets: { emphasis: %w[chart diagram] },
      thumbnail_style: { treatment: "clean-type", title_weight: 600 }
    }
  }
].freeze

TEMPLATES.each do |attrs|
  template = Template.find_or_initialize_by(slug: attrs[:slug])
  template.assign_attributes(name: attrs[:name], description: attrs[:description], category: attrs[:category])
  template.save!

  unless template.latest_version&.config == attrs[:config].deep_stringify_keys
    template.publish_version!(config: attrs[:config], changelog: "Seed import")
  end
end

puts "Seeded #{Template.count} templates (#{TemplateVersion.count} versions)."
