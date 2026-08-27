# Isolate object storage per test run: a disk adapter rooted in tmp, wiped after.
RSpec.configure do |config|
  storage_root = Rails.root.join("tmp/test_storage")

  config.before do
    Storage.service = Storage::DiskAdapter.new(root: storage_root)
  end

  config.after(:suite) do
    FileUtils.rm_rf(storage_root)
  end

  config.after do
    Storage.reset!
  end
end
