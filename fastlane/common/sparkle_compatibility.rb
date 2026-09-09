require "rexml/document"

module VizorSparkleCompatibility
  SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle".freeze

  # Validate the current full update's requirement, not an older item's or
  # a delta's. Sparkle must not offer the new engine to unsupported macOS hosts.
  def self.validate_minimum_system_version!(xml, archive_url:, minimum_version:)
    raise ArgumentError, "Invalid app minimum macOS version" unless minimum_version.match?(/\A\d+(?:\.\d+){1,2}\z/)

    document = REXML::Document.new(xml)
    items = document.get_elements("rss/channel/item").select do |item|
      item.get_elements("enclosure").any? { |element| element.attributes["url"] == archive_url }
    end
    raise ArgumentError, "Expected one current full update in Sparkle appcast" unless items.length == 1

    requirements = items.first.elements.to_a.select do |element|
      element.name == "minimumSystemVersion" && element.namespace == SPARKLE_NAMESPACE
    end
    unless requirements.length == 1 && requirements.first.text.to_s.strip == minimum_version
      raise ArgumentError, "Sparkle minimumSystemVersion must match app minimum macOS #{minimum_version}"
    end
  end
end
