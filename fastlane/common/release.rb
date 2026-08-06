require "json"
require "net/http"
require "shellwords"
require "uri"

module VizorRelease
  module_function

  DEFAULT_WALLET_LINK_BACKEND_URL = "https://functions.vizor.cash".freeze

  def shell_escape(value)
    Shellwords.escape(value.to_s)
  end

  def workspace_root
    File.expand_path("../..", __dir__)
  end

  def wallet_link_backend_url
    url = ENV["VIZOR_WALLET_LINK_BACKEND_URL"].to_s.strip
    url.empty? ? DEFAULT_WALLET_LINK_BACKEND_URL : url
  end

  def release_tag_info(tag)
    match = /\A(?:release|mobile)\/v(?<base_version>\d+\.\d+\.\d+)(?<prerelease_suffix>-(?:rc|internal)\.\d+)?\z/.match(tag.to_s)
    UI.user_error!("Unsupported release tag format: #{tag}") unless match

    prerelease_suffix = match[:prerelease_suffix].to_s
    prerelease_channel = prerelease_suffix[/\A-(\D+)\./, 1].to_s
    {
      base_version: match[:base_version],
      asset_version: "#{match[:base_version]}#{prerelease_suffix}",
      prerelease_channel: prerelease_channel,
      prerelease_number: prerelease_suffix[/\.(\d+)\z/, 1]&.to_i,
      is_prerelease: !prerelease_suffix.empty?,
      is_internal: prerelease_channel == "internal"
    }
  end

  def update_test_target_tag
    ENV["VIZOR_UPDATE_TEST_TARGET_TAG"].to_s.strip
  end

  def update_test_enabled?
    !update_test_target_tag.empty?
  end

  def sparkle_test_delta_source_tag
    ENV["VIZOR_SPARKLE_TEST_DELTA_SOURCE_TAG"].to_s.strip
  end

  def validate_update_test_tags!(current_tag)
    target_tag = update_test_target_tag
    source_tag = sparkle_test_delta_source_tag
    return if target_tag.empty? && source_tag.empty?

    if target_tag.empty?
      UI.user_error!("VIZOR_UPDATE_TEST_TARGET_TAG is required when VIZOR_SPARKLE_TEST_DELTA_SOURCE_TAG is set")
    end

    current = release_tag_info(current_tag)
    target = release_tag_info(target_tag)
    unless current.fetch(:prerelease_channel) == "rc" && target.fetch(:prerelease_channel) == "rc"
      UI.user_error!("Update-test releases must use release/vX.Y.Z-rc.N tags")
    end
    unless current.fetch(:base_version) == target.fetch(:base_version)
      UI.user_error!("Update-test target #{target_tag} must use the same base version as #{current_tag}")
    end
    if target.fetch(:prerelease_number) < current.fetch(:prerelease_number)
      UI.user_error!("Update-test target #{target_tag} must not precede #{current_tag}")
    end

    return if source_tag.empty?

    unless current_tag == target_tag
      UI.user_error!("Sparkle RC delta sources are accepted only while building the update-test target #{target_tag}")
    end
    source = release_tag_info(source_tag)
    unless source.fetch(:prerelease_channel) == "rc" && source.fetch(:base_version) == current.fetch(:base_version)
      UI.user_error!("Sparkle RC delta source #{source_tag} must be an RC of #{current.fetch(:base_version)}")
    end
    unless source.fetch(:prerelease_number) < current.fetch(:prerelease_number)
      UI.user_error!("Sparkle RC delta source #{source_tag} must precede #{current_tag}")
    end
  end

  def update_test_release_base_url(repository: ENV.fetch("RELEASE_REPOSITORY"))
    return "" unless update_test_enabled?

    "https://github.com/#{repository}/releases/download/#{update_test_target_tag}"
  end

  def release_build_number
    build_number = ENV["RELEASE_BUILD_NUMBER"].to_s.strip
    UI.user_error!("RELEASE_BUILD_NUMBER must be a positive integer") unless build_number.match?(/\A[1-9]\d*\z/)
    build_number
  end

  def release_boolean_env(key)
    ENV[key].to_s.downcase == "true"
  end

  def release_tag
    tag = ENV["RELEASE_TAG"].to_s.strip
    return tag unless tag.empty?

    ref_type = ENV.fetch("GITHUB_REF_TYPE")
    UI.user_error!("RELEASE_TAG is required when GITHUB_REF_TYPE is not 'tag'") unless ref_type == "tag"
    ENV.fetch("GITHUB_REF_NAME")
  end

  def assert_prerelease_env_matches!(tag_info, tag)
    return if ENV["GITHUB_RELEASE_PRERELEASE"].to_s.strip.empty?

    env_prerelease = release_boolean_env("GITHUB_RELEASE_PRERELEASE")
    return if env_prerelease == tag_info.fetch(:is_prerelease)

    UI.user_error!("GITHUB_RELEASE_PRERELEASE=#{env_prerelease} does not match release tag #{tag}")
  end

  def http_get(uri, headers: {}, limit: 5)
    UI.user_error!("Too many redirects fetching #{uri}") if limit <= 0

    request = Net::HTTP::Get.new(uri)
    headers.each { |key, value| request[key] = value }

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      http_get(URI(response["location"]), headers: headers, limit: limit - 1)
    else
      UI.user_error!("HTTP GET failed for #{uri}: #{response.code} #{response.message}")
    end
  end

  def github_api_json(url)
    JSON.parse(
      http_get(
        URI(url),
        headers: {
          "Authorization" => "Bearer #{ENV.fetch("GITHUB_TOKEN")}",
          "Accept" => "application/vnd.github+json",
          "User-Agent" => "vizor-fastlane",
          "X-GitHub-Api-Version" => "2022-11-28"
        }
      )
    )
  end

  def github_release_page_url(repository:, tag:)
    "https://github.com/#{repository}/releases/tag/#{tag}"
  end

  def github_release_download_base_url(repository:, tag:)
    "https://github.com/#{repository}/releases/download/#{tag}/"
  end

  def github_release_download_url(repository:, tag:, asset_name:)
    "#{github_release_download_base_url(repository: repository, tag: tag)}#{asset_name}"
  end
end
