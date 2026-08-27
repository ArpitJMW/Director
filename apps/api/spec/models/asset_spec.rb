require "rails_helper"

RSpec.describe Asset, type: :model do
  let(:project) { create(:project) }
  let(:png) { File.binread(Rails.root.join("spec/fixtures/files/sample.png")) }

  describe ".store!" do
    it "uploads and records size, checksum, dimensions and provenance" do
      asset = described_class.store!(
        project: project, asset_type: "image", io: StringIO.new(png),
        content_type: "image/png", source_type: "user_provided"
      )

      expect(asset.storage_key).to eq("projects/#{project.id}/#{asset.public_id}.png")
      expect(asset.byte_size).to eq(png.bytesize)
      expect(asset.checksum).to eq(Digest::SHA256.hexdigest(png))
      expect([ asset.width, asset.height ]).to eq([ 2, 2 ])
      expect(asset.ai_generated).to be(false)
      expect(Storage.service.exists?(key: asset.storage_key)).to be(true)
    end

    it "uses a scene-scoped key when a scene is given" do
      scene = create(:scene, project: project)
      asset = described_class.store!(
        project: project, scene: scene, asset_type: "image",
        io: StringIO.new(png), content_type: "image/png", source_type: "ai_generated"
      )
      expect(asset.storage_key).to include("scenes/#{scene.id}")
      expect(asset.ai_generated).to be(true)
    end

    it "creates no row if the upload fails" do
      failing = instance_double(Storage::DiskAdapter)
      allow(failing).to receive(:upload).and_raise(Storage::Service::Error, "boom")

      expect {
        expect {
          described_class.store!(
            project: project, asset_type: "image", io: StringIO.new(png),
            content_type: "image/png", source_type: "user_provided", storage: failing
          )
        }.to raise_error(Storage::Service::Error)
      }.not_to change(Asset, :count)
    end
  end

  it "#signed_url returns a fetchable url" do
    asset = described_class.store!(
      project: project, asset_type: "image", io: StringIO.new(png),
      content_type: "image/png", source_type: "user_provided"
    )
    expect(asset.signed_url).to start_with("/api/v1/files?")
  end
end
