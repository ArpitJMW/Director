# Task 7 Part 4 — Image Lab. Example:
#   TOPICS="How UPI changed payments in India|How the printing press changed the world" \
#   SHOTS=3 VARIANTS=old,new PROVIDER=cloudflare OUT=tmp/image_lab/run1 \
#   bin/rails image_lab:run
# Paid runs need PROVIDER=gemini-paid, GEMINI_PAID_API_KEY, and PAID_IMAGE_CALL_CAP.
namespace :image_lab do
  desc "Render old vs new image prompts for the given topics (no production assets touched)"
  task run: :environment do
    load Rails.root.join("lib", "image_lab", "run.rb").to_s
    topics = ENV.fetch("TOPICS").split("|").map(&:strip)
    shots = ENV.fetch("SHOTS", "3").to_i
    variants = ENV.fetch("VARIANTS", "old,new").split(",")
    provider = ENV.fetch("PROVIDER", "cloudflare")
    out = ENV.fetch("OUT", Rails.root.join("tmp", "image_lab", Time.current.strftime("%Y%m%d-%H%M%S")).to_s)

    paid = provider.end_with?("-paid")
    restore = { "ALLOW_PAID_PROVIDERS" => ENV["ALLOW_PAID_PROVIDERS"], "PAID_IMAGE_CALL_CAP" => ENV["PAID_IMAGE_CALL_CAP"] }
    if paid
      ENV["ALLOW_PAID_PROVIDERS"] = "true"
      ENV["PAID_IMAGE_CALL_CAP"] = ENV.fetch("PAID_IMAGE_CALL_CAP", "8")
    end
    begin
      Providers::PaidImageCap.reset!
      result = ImageLab.run(topics: topics, shots: shots, variants: variants, provider: provider, out_dir: out)
      puts "run_dir=#{result[:run_dir]}"
      puts "images=#{result[:calls]} total_cost_usd=#{result[:total_cost_usd]}"
    rescue ImageLab::Failure, Providers::PaidImageCap::Exhausted => e
      puts "STOPPED: #{e.message}"
    rescue => e
      # A 429 stops the run cleanly; any other error is a real failure.
      puts "STOPPED on #{e.class}: #{e.message.to_s.truncate(300)}"
      exit 1 unless e.message.to_s.include?("429")
    ensure
      restore.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end
end

# Task 7.3 — fixtures: plan once per topic, then compile and render without re-planning.
namespace :image_lab do
  def image_lab_fixture_dir = ENV.fetch("FIXTURES", Rails.root.join("tmp", "image_lab", "fixtures").to_s)

  desc "Plan one fixture per topic (script, scenes, shots, look, setting) and save it as JSON"
  task fixture: :environment do
    load Rails.root.join("lib", "image_lab", "run.rb").to_s
    load Rails.root.join("lib", "image_lab", "fixture.rb").to_s
    topics = ENV.fetch("TOPICS").split("|").map(&:strip)
    dir = ENV.fetch("OUT", image_lab_fixture_dir)
    topics.each do |topic|
      slug = topic.parameterize.first(40)
      data = ImageLab::Fixture.build(topic: topic, out_path: File.join(dir, "#{slug}.json"))
      puts "fixture #{slug}: #{data[:shots].size} shots, look=#{data[:look].present?} setting=#{data[:setting].present?}"
    end
  end

  desc "Compile the prompts for every fixture (compile call only); writes compiled.json, prompts.txt and an audit"
  task compile: :environment do
    load Rails.root.join("lib", "image_lab", "run.rb").to_s
    load Rails.root.join("lib", "image_lab", "fixture.rb").to_s
    dir = image_lab_fixture_dir
    out = ENV.fetch("OUT", Rails.root.join("tmp", "image_lab", "compiled").to_s)
    FileUtils.mkdir_p(out)
    compiled = Dir.glob(File.join(dir, "*.json")).sort.map do |path|
      data = JSON.parse(File.read(path))
      result = ImageLab::Fixture.compile(data)
      puts "#{data['topic']}: " + result[:shots].map { |s| "#{s[:id]}=#{s[:source]}" }.join(", ")
      result.merge(fixture: File.basename(path))
    end
    File.write(File.join(out, "compiled.json"), JSON.pretty_generate(compiled))
    File.write(File.join(out, "prompts.txt"), compiled.flat_map { |c|
      c[:shots].map { |s| "[#{c[:topic]}] #{s[:id]} (#{s[:framing]}, #{s[:source]}, #{s[:prompt].to_s.split.size} words)\n#{s[:prompt]}\n" }
    }.join("\n"))
    puts "wrote #{out}/compiled.json and prompts.txt"
  end

  desc "Render OLD vs NEW for every fixture using the compiled prompts; writes rows.json, prompts.txt and the contact sheet"
  task images: :environment do
    load Rails.root.join("lib", "image_lab", "run.rb").to_s
    load Rails.root.join("lib", "image_lab", "fixture.rb").to_s
    compiled_path = ENV.fetch("COMPILED", Rails.root.join("tmp", "image_lab", "compiled", "compiled.json").to_s)
    compiled = JSON.parse(File.read(compiled_path), symbolize_names: true)
    fixtures = Dir.glob(File.join(image_lab_fixture_dir, "*.json")).sort
    out = ENV.fetch("OUT", Rails.root.join("tmp", "image_lab", "images").to_s)
    FileUtils.mkdir_p(out)
    adapter = ImageLab.build_adapter(ENV.fetch("PROVIDER", "cloudflare"))
    rows = []
    begin
      fixtures.each do |path|
        data = JSON.parse(File.read(path))
        entry = compiled.find { |c| c[:fixture] == File.basename(path) }
        raise ImageLab::Failure, "no compiled entry for #{File.basename(path)}" unless entry

        rows.concat(ImageLab::Fixture.render(data, entry[:shots], adapter, out))
      end
    rescue => e
      puts "STOPPED on #{e.class}: #{e.message.to_s.truncate(300)}"
      File.write(File.join(out, "rows.json"), JSON.pretty_generate(rows))
      exit 1
    end
    File.write(File.join(out, "rows.json"), JSON.pretty_generate(rows))
    File.write(File.join(out, "prompts.txt"), rows.map { |r|
      "[#{r[:topic]}] #{r[:unit]} #{r[:variant].upcase} (#{r[:prompt_source]}, #{r[:prompt_words]} words)\n#{r[:prompt]}\n"
    }.join("\n"))
    puts "rendered #{rows.size} images into #{out}"
  end
end
