require "minitest/autorun"
require "fastlane"

# Run with: bundle exec ruby scripts/test_macos_signing.rb
# Parse the production Fastfile and call only its environment-validation lane.
# No signing, builds, or network requests are performed.
Fastlane::Actions.load_default_actions

class MacosSigningTest < Minitest::Test
  FASTFILE = Fastlane::FastFile.new(File.expand_path("../fastlane/macos/Fastfile", __dir__))
  SIGNING_KEYS = %w[MATCH_GIT_URL MATCH_PASSWORD MATCH_CERTIFICATE_PASSWORD MACOS_KEYCHAIN_PASSWORD].freeze

  def setup
    @environment = ENV.to_h
    SIGNING_KEYS.each { |key| ENV[key] = "offline-placeholder" }
    ENV["MATCH_READONLY"] = "false"
    ENV.delete("APP_STORE_CONNECT_API_KEY_JSON")
    @lane = FASTFILE.runner.lanes.fetch(:mac).fetch(:validate_signing_environment)
  end

  def teardown
    ENV.replace(@environment)
  end

  def test_readonly_lane_exits_without_an_api_key
    assert_nil @lane.call(readonly: true)
  end

  def test_readonly_lane_uses_environment_default
    ENV["MATCH_READONLY"] = "true"
    assert_nil @lane.call({})
  end

  def test_writable_lane_accepts_an_api_key
    ENV["APP_STORE_CONNECT_API_KEY_JSON"] = "offline-placeholder"
    assert_nil @lane.call(readonly: false)
  end

  def test_writable_lane_requires_an_api_key
    error = assert_raises(FastlaneCore::Interface::FastlaneError) { @lane.call({}) }
    assert_includes error.message, "APP_STORE_CONNECT_API_KEY_JSON is required"
  end

  def test_explicit_writable_option_overrides_readonly_environment
    ENV["MATCH_READONLY"] = "true"
    assert_raises(FastlaneCore::Interface::FastlaneError) { @lane.call(readonly: false) }
  end

  def test_both_modes_require_signing_configuration
    [true, false].each do |readonly|
      SIGNING_KEYS.each do |key|
        value = ENV.delete(key)
        begin
          error = assert_raises(KeyError) { @lane.call(readonly: readonly) }
          assert_equal key, error.key
        ensure
          ENV[key] = value
        end
      end
    end
  end
end
