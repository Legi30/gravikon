# frozen_string_literal: true

require "test_helper"

class GalaxyVisualizerTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp", "visualizer_test_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@dir)
    @galaxy_path = @dir.join("galaxy_data.json")
    File.write(@galaxy_path, JSON.generate(
      "black_hole" => { "name" => "Sagittarius Omega", "mass" => 8.2e36, "x" => 400, "y" => 400 },
      "systems" => [ { "id" => "vis_single", "x" => 250, "y" => 400 }, { "id" => "vis_binary", "x" => 600, "y" => 400 } ]
    ))

    planets = ->(count) { Array.new(count) { |i| { "name" => "P#{i}", "type" => "planet", "x" => 500 + i * 30, "y" => 400, "radius" => 2.0e6 } } }
    write_system_data("vis_single", [ { "name" => "Sun", "type" => "star", "x" => 400, "y" => 400, "radius" => 7.0e7 } ] + planets.call(9))
    write_system_data("vis_binary", [
      { "name" => "A", "type" => "star", "x" => 364, "y" => 400, "radius" => 6.0e7 },
      { "name" => "B", "type" => "star", "x" => 436, "y" => 400, "radius" => 5.0e7 }
    ] + planets.call(1))

    colors = { "vis_single" => "#14a594", "vis_binary" => "#b38f00" }
    GalaxyVisualizer.new(@galaxy_path.to_s, colors: colors).to_svg(@dir.join("galaxy.svg").to_s)
    @svg = Nokogiri::XML(File.read(@dir.join("galaxy.svg")))
    @svg.remove_namespaces!
  end

  teardown do
    FileUtils.rm_rf(@dir)
    %w[vis_single vis_binary].each { |id| FileUtils.rm_f(GalaxyService.system_data_path(id)) }
  end

  test "markers show about half of the planets, at least one" do
    assert_equal 4, marker("vis_single").css(".mini-planet").size
    assert_equal 1, marker("vis_binary").css(".mini-planet").size
  end

  test "markers are drawn in light tints of the system colour" do
    single = marker("vis_single")
    assert_equal "#14a594", single["data-system-color"]
    assert_equal System.tint("#14a594", 0.75), single.at_css(".system-core")["fill"]
    assert_equal System.tint("#14a594", 0.45), single.at_css(".system-label")["fill"]
  end

  test "a binary marker draws two stars circling the centre" do
    binary = marker("vis_binary")
    assert_equal "true", binary["data-binary"]
    assert_equal 2, binary.css(".mini-binary circle").size
    assert_equal "false", marker("vis_single")["data-binary"]
  end

  test "miniature bodies carry their orbit for the tilted landing map" do
    planets = marker("vis_single").css(".mini-planet")
    assert planets.all? { |planet| planet["data-ring"].to_f.positive? && planet["data-period"].to_f.positive? }
    assert planets.all? { |planet| planet["data-angle"] }

    stars = marker("vis_binary").css(".mini-binary circle")
    assert_equal [ 0.0, Math::PI.round(4) ], stars.map { |star| star["data-angle"].to_f }
  end

  private

  def marker(id)
    @svg.at_css(".system-marker[data-system-id='#{id}']")
  end
end
