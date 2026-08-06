require "minitest/autorun"

module UI
  module_function

  def user_error!(message)
    raise ArgumentError, message
  end
end

require_relative "release"

class VizorReleaseTest < Minitest::Test
  UPDATE_ENV_KEYS = %w[
    VIZOR_UPDATE_TEST_TARGET_TAG
    VIZOR_SPARKLE_TEST_DELTA_SOURCE_TAG
  ].freeze

  def teardown
    UPDATE_ENV_KEYS.each { |key| ENV.delete(key) }
  end

  def test_stable_release_keeps_update_test_disabled
    VizorRelease.validate_update_test_tags!("release/v0.0.47")

    refute VizorRelease.update_test_enabled?
    assert_equal "", VizorRelease.update_test_release_base_url(repository: "chainapsis/vizor-wallet")
  end

  def test_rc_pair_uses_exact_target_release
    ENV["VIZOR_UPDATE_TEST_TARGET_TAG"] = "release/v0.0.47-rc.1"
    ENV["VIZOR_SPARKLE_TEST_DELTA_SOURCE_TAG"] = "release/v0.0.47-rc.0"

    VizorRelease.validate_update_test_tags!("release/v0.0.47-rc.1")

    assert VizorRelease.update_test_enabled?
    assert_equal(
      "https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.47-rc.1",
      VizorRelease.update_test_release_base_url(repository: "chainapsis/vizor-wallet")
    )
  end

  def test_update_test_rejects_stable_release
    ENV["VIZOR_UPDATE_TEST_TARGET_TAG"] = "release/v0.0.47-rc.1"

    error = assert_raises(ArgumentError) do
      VizorRelease.validate_update_test_tags!("release/v0.0.47")
    end
    assert_includes error.message, "must use release/vX.Y.Z-rc.N"
  end

  def test_delta_source_must_precede_target
    ENV["VIZOR_UPDATE_TEST_TARGET_TAG"] = "release/v0.0.47-rc.1"
    ENV["VIZOR_SPARKLE_TEST_DELTA_SOURCE_TAG"] = "release/v0.0.47-rc.1"

    error = assert_raises(ArgumentError) do
      VizorRelease.validate_update_test_tags!("release/v0.0.47-rc.1")
    end
    assert_includes error.message, "must precede"
  end
end
