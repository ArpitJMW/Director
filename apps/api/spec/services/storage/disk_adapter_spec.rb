require "rails_helper"

RSpec.describe Storage::DiskAdapter do
  let(:adapter) { described_class.new(root: Rails.root.join("tmp/test_storage_adapter")) }
  let(:key) { "projects/1/ast_abc.txt" }

  after { FileUtils.rm_rf(Rails.root.join("tmp/test_storage_adapter")) }

  it "round-trips upload / download / delete" do
    adapter.upload(key: key, io: StringIO.new("hello"), content_type: "text/plain")
    expect(adapter.exists?(key: key)).to be(true)
    expect(adapter.download(key: key)).to eq("hello")

    adapter.delete(key: key)
    expect(adapter.exists?(key: key)).to be(false)
  end

  it "issues a signed url that verifies" do
    url = adapter.url(key: key, expires_in: 3600)
    query = Rack::Utils.parse_query(url.split("?").last)

    expect(url).to start_with("/api/v1/files?")
    expect(adapter.verify(key: query["key"], token: query["token"], expires: query["expires"])).to be(true)
    expect(adapter.verify(key: query["key"], token: "tampered", expires: query["expires"])).to be(false)
  end

  it "rejects an expired token" do
    url = adapter.url(key: key, expires_in: -10)
    query = Rack::Utils.parse_query(url.split("?").last)
    expect(adapter.verify(key: query["key"], token: query["token"], expires: query["expires"])).to be(false)
  end

  it "does not escape the storage root with a traversal key" do
    adapter.upload(key: "../../etc/pwned", io: StringIO.new("x"), content_type: "text/plain")
    expect(File).not_to exist(Rails.root.join("etc/pwned"))
  end
end
