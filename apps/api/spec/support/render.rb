# Stub the external Remotion renderer in every spec — no headless Chrome, no
# network. Individual specs that need custom behaviour can re-stub.
RSpec.configure do |config|
  config.before do
    fake_mp4 = "\x00\x00\x00\x18ftypmp42".b + ("\x00".b * 1024)
    allow_any_instance_of(Video::RenderVideo).to receive(:call).and_return(
      { path: "/tmp/fake.mp4", render_seconds: 1.0, bytes: fake_mp4 }
    )
  end
end
