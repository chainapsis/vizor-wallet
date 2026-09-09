require "minitest/autorun"

# Load the production metadata helpers without running any Fastlane lanes.
def fastlane_version(*) = nil
def platform(*) = nil

module UI
  def self.user_error!(message)
    raise ArgumentError, message
  end
end

load File.expand_path("../fastlane/windows/Fastfile", __dir__)

class WindowsReleaseTest < Minitest::Test
  def setup
    @environment = ENV.to_h
    ENV.delete("VIZOR_WINDOWS_ARCH")
    ENV["RELEASE_TAG"] = "release/v1.2.3"
    ENV["RELEASE_BUILD_NUMBER"] = "123"
    ENV["RELEASE_REPOSITORY"] = "example/wallet"
    ENV["GITHUB_RELEASE_PRERELEASE"] = "false"
    ENV["VIZOR_WINDOWS_CODE_SIGN_PARAMS"] = "test-signing-parameters"
  end

  def teardown
    ENV.replace(@environment)
  end

  def test_default_x64_artifact_contract_even_on_arm_host
    ENV["PROCESSOR_ARCHITECTURE"] = "ARM64"
    { "mainnet" => "com.keplr.vizor", "testnet" => "com.keplr.vizor.testnet" }.each do |flavor, pack_id|
      metadata = windows_release_metadata(flavor: flavor)
      channel = "win-x64-#{flavor}"
      assert_equal "x64", metadata[:arch]
      assert_equal channel, metadata[:channel]
      assert_equal pack_id, metadata[:pack_id]
      assert_equal flavor == "mainnet" ? "Vizor" : "Vizor Testnet", metadata[:pack_title]
      assert_equal File.join("dist", "windows", "velopack", flavor), metadata[:output_dir_arg]
      assert_equal [
        "#{pack_id}-#{channel}-Setup.exe",
        "#{pack_id}-1.2.3-#{channel}-full.nupkg",
        "releases.#{channel}.json",
        "RELEASES-#{channel}",
        "assets.#{channel}.json",
        "releases.#{channel}.json.sig"
      ], windows_release_assets(metadata)
      assert_equal flavor == "mainnet" ? "test-signing-parameters" : "", windows_code_signing_params_for(metadata)
    end
  end

  def test_explicit_architectures_and_aliases_do_not_leave_cached_state
    { "ARM64" => "arm64", "aarch64" => "arm64", "amd64" => "x64",
      "x86_64" => "x64", "x64" => "x64", " " => "x64" }.each do |input, expected|
      ENV["VIZOR_WINDOWS_ARCH"] = input
      %w[mainnet testnet].each do |flavor|
        metadata = windows_release_metadata(flavor: flavor)
        assert_equal expected, metadata[:arch]
        assert_equal "win-#{expected}-#{flavor}", metadata[:channel]
        assert_equal "#{metadata[:pack_id]}-win-#{expected}-#{flavor}-Setup.exe", metadata[:setup_asset_name]
      end
    end
    ENV.delete("VIZOR_WINDOWS_ARCH")
    assert_equal "x64", windows_release_arch
  end

  def test_unknown_architecture_is_rejected
    ENV["VIZOR_WINDOWS_ARCH"] = "x86"
    assert_raises(ArgumentError) { windows_release_metadata }
  end

  def test_prerelease_signing_policy_is_unchanged_for_both_architectures
    ENV["RELEASE_TAG"] = "release/v1.2.3-rc.0"
    ENV["GITHUB_RELEASE_PRERELEASE"] = "true"
    %w[x64 arm64].each do |arch|
      ENV["VIZOR_WINDOWS_ARCH"] = arch
      %w[mainnet testnet].each do |flavor|
        metadata = windows_release_metadata(flavor: flavor)
        refute metadata[:update_enabled]
        assert_equal "", windows_code_signing_params_for(metadata)
        assert_equal 5, windows_release_assets(metadata).length
        assert_includes windows_release_assets(metadata), "#{metadata[:pack_id]}-1.2.3-rc.0-win-#{arch}-#{flavor}-full.nupkg"
      end
    end
  end

  def test_prerelease_clears_inherited_signing_and_restores_it_after_failure
    keys = %w[VIZOR_WINDOWS_CODE_SIGN_PARAMS VIZOR_WINDOWS_CODE_SIGN_PARALLEL VIZOR_WINDOWS_CODE_SIGN_EXCLUDE VIZOR_WINDOWS_SIGNTOOL_PATH]
    keys.each { |key| ENV[key] = "inherited-#{key}" }
    original = ENV.to_h
    assert_raises(RuntimeError) do
      with_windows_update_environment(update_enabled: false) do
        keys.each { |key| assert_equal "", ENV[key] }
        assert_equal "", ENV["VIZOR_UPDATE_FEED_SIGNING_KEY_B64"]
        raise "packaging failed"
      end
    end
    assert_equal original, ENV.to_h
    with_windows_update_environment(update_enabled: true) do
      keys.each { |key| assert_equal original[key], ENV[key] }
    end
    keys.each { |key| ENV.delete(key) }
    with_windows_update_environment(update_enabled: false) {}
    keys.each { |key| refute ENV.key?(key) }
  end
end
