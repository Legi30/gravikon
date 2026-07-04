# frozen_string_literal: true

require "application_system_test_case"

class GalaxyNavigationTest < ApplicationSystemTestCase
  setup do
    # Create test galaxy data
    @test_galaxy_file = GalaxyService.galaxy_data_path
    @test_galaxy_data = {
      "black_hole" => { "name" => "Sagittarius Omega", "mass" => 8.2e36, "x" => 400, "y" => 400 },
      "systems" => []
    }
    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))

    # Create test SVG
    @test_svg_file = GalaxyService.galaxy_svg_path
    FileUtils.mkdir_p(File.dirname(@test_svg_file))
    File.write(@test_svg_file, '<svg width="800" height="800"><circle cx="400" cy="400" r="20" /></svg>')
  end

  teardown do
    File.delete(@test_galaxy_file) if File.exist?(@test_galaxy_file)
    File.delete(@test_svg_file) if File.exist?(@test_svg_file)
  end

  # Test galaxy index page loads and displays galaxy.svg
  test "galaxy index page loads and displays galaxy visualization" do
    visit galaxy_index_path
    assert_selector "h1", text: "Mapa galaxie"
    # SVG should be present
    assert_selector 'svg, img[src*="galaxy"]', wait: 5
  end

  # Test galaxy map shows central black hole
  test "galaxy map shows central black hole" do
    # Create a system so the galaxy stats are displayed
    system = System.create!(name: "Test System", x: 300, y: 300, json_file_path: "data/systems/test_bh.json")

    visit galaxy_index_path
    # Check for visual elements representing black hole (only shown when systems exist)
    assert_text "Sagittarius Omega", wait: 5

    system.destroy
  end

  # Test system show page displays system SVG
  test "system show page displays system visualization" do
    system = System.create!(name: "Test System", x: 300, y: 300, json_file_path: "data/systems/test.json")

    # Create system data and SVG
    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("test"), {
      bodies: [ { name: "Star", type: "star", x: 400, y: 400 } ]
    }.to_json)

    system_svg = GalaxyService.system_svg_path("test")
    FileUtils.mkdir_p(File.dirname(system_svg))
    File.write(system_svg, '<svg width="800" height="800"><circle cx="400" cy="400" r="10" /></svg>')

    visit galaxy_system_path(system)
    assert_selector "h1, h2", text: "Test System"
    assert_selector "svg, img", wait: 5

    # Cleanup
    File.delete(GalaxyService.system_data_path("test"))
    File.delete(system_svg)
    system.destroy
  end

  # Test breadcrumb navigation
  test "breadcrumb link returns to galaxy view" do
    system = System.create!(name: "Nav Test", x: 300, y: 300, json_file_path: "data/systems/nav_test.json")

    visit galaxy_system_path(system)

    # Wait for page to load and find breadcrumb link
    assert_link "Mapa galaxie", wait: 5
    click_link "Mapa galaxie", match: :first

    assert_current_path galaxy_index_path

    system.destroy
  end

  # Test Add New System button
  test "Add New System button links to new_system form" do
    visit galaxy_index_path
    click_link "Přidat novou soustavu", match: :first

    assert_selector "form", wait: 5
    assert_selector 'input[name*="name"], input[id*="name"]'
  end
end
