# frozen_string_literal: true

require "test_helper"

class PlanetarySystemTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp", "planetary_test_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@dir)
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "binary stars and their planets orbit the common centre" do
    svg = render([
      { "name" => "A", "type" => "star", "x" => 364, "y" => 400, "radius" => 6.0e7 },
      { "name" => "B", "type" => "star", "x" => 436, "y" => 400, "radius" => 5.0e7 },
      { "name" => "Pluven", "type" => "planet", "x" => 520, "y" => 400, "radius" => 2.5e6 }
    ])

    stars = svg.css(".celestial-body[data-type='star']")
    assert_equal 2, stars.size
    stars.each do |star|
      assert_equal "", star["data-parent"]
      assert_equal 36.0, star["data-orbit-radius"].to_f
      assert_equal PlanetarySystem::BINARY_STAR_PERIOD.to_f, star["data-orbital-period"].to_f
      assert star["r"].to_f <= PlanetarySystem::BINARY_STAR_DISPLAY_RADIUS
    end

    planet = svg.at_css(".celestial-body[data-type='planet']")
    assert_equal "", planet["data-parent"]
    assert_equal 400.0, planet["data-parent-x"].to_f
    assert_equal 120.0, planet["data-orbit-radius"].to_f
    # One shared ring for the pair, one for the planet
    assert_equal 2, svg.css(".orbit-path").size
  end

  test "a single star stays still and parents its planets" do
    svg = render([
      { "name" => "Sun", "type" => "star", "x" => 400, "y" => 400, "radius" => 7.0e7 },
      { "name" => "Pluven", "type" => "planet", "x" => 520, "y" => 400, "radius" => 2.5e6 }
    ])

    assert_equal 0.0, svg.at_css(".celestial-body[data-type='star']")["data-orbit-radius"].to_f
    assert_equal "Sun", svg.at_css(".celestial-body[data-type='planet']")["data-parent"]
  end

  private

  def render(bodies)
    json = @dir.join("system.json")
    File.write(json, JSON.generate("system_id" => "planetary_test", "bodies" => bodies))
    output = @dir.join("system.svg")
    PlanetarySystem.generate(json_path: json.to_s, system_id: "planetary_test", output_path: output.to_s)
    Nokogiri::XML(File.read(output)).tap(&:remove_namespaces!)
  end
end
