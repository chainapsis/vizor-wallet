require "minitest/autorun"
require_relative "../fastlane/common/sparkle_compatibility"

class SparkleCompatibilityTest < Minitest::Test
  URL = "https://example.test/Vizor-macos.dmg".freeze

  def validate(requirement, extra_items: "")
    xml = <<~XML
      <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        #{extra_items}
        <item>#{requirement}<enclosure url="#{URL}"/></item>
      </channel></rss>
    XML
    VizorSparkleCompatibility.validate_minimum_system_version!(xml, archive_url: URL, minimum_version: "12.0")
  end

  def test_accepts_current_app_minimum
    validate("<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>")
  end

  def test_rejects_missing_lower_or_unrecognized_requirement
    ["", "<sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>",
     "<minimumSystemVersion>12.0</minimumSystemVersion>"].each do |requirement|
      assert_raises(ArgumentError) { validate(requirement) }
    end
  end

  def test_does_not_accept_an_older_items_requirement
    assert_raises(ArgumentError) do
      validate("", extra_items: '<item><sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion><enclosure url="https://example.test/old.dmg"/></item>')
    end
  end

  def test_rejects_ambiguous_current_update
    assert_raises(ArgumentError) do
      validate("<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>", extra_items: "<item><enclosure url=\"#{URL}\"/></item>")
    end
  end
end
