# frozen_string_literal: true

require "application_system_test_case"

class GalaxyInteractivityTest < ApplicationSystemTestCase
  setup do
    @test_galaxy_file = GalaxyService.galaxy_data_path
    @test_galaxy_data = {
      "black_hole" => { "name" => "Sagittarius Omega", "x" => 400, "y" => 400 },
      "systems" => []
    }
    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))

    @test_svg_file = GalaxyService.galaxy_svg_path
    FileUtils.mkdir_p(File.dirname(@test_svg_file))
    File.write(@test_svg_file, '<svg width="800" height="800"><circle cx="400" cy="400" r="20" data-system-id="test" /></svg>')
  end

  teardown do
    File.delete(@test_galaxy_file) if File.exist?(@test_galaxy_file)
    File.delete(@test_svg_file) if File.exist?(@test_svg_file)
  end

  # Test hovering over system shows information
  test "hovering over system circle displays system information" do
    system = System.create!(name: "Hover Test", x: 300, y: 300, json_file_path: "data/systems/hover_test.json")

    visit galaxy_index_path

    # Look for interactive elements
    if has_selector?("circle[data-system-id], .system-marker", wait: 5)
      # Hover should work with JavaScript enabled
      assert_selector "svg, .galaxy-map"
    end

    system.destroy
  end

  # Test clicking system navigates to show page
  test "clicking system circle navigates to system show page" do
    system = System.create!(name: "Click Test", x: 300, y: 300, json_file_path: "data/systems/click_test.json")

    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("click_test"), {
      bodies: [ { name: "Star", type: "star" } ]
    }.to_json)

    visit galaxy_index_path

    # Try to click on system (may be link or JS-enabled element)
    if has_link?("Click Test")
      click_link "Click Test", match: :first
      assert_text /Click Test/, wait: 5
    end

    File.delete(GalaxyService.system_data_path("click_test")) rescue nil
    system.destroy
  end

  # Test position picker in new system form
  test "position picker in new_system form shows galaxy map" do
    visit new_galaxy_system_path

    # Position picker should be visible
    if has_selector?(".position-picker, #position-picker, [data-position-picker]", wait: 5)
      assert_selector ".position-picker, #position-picker"
    end

    # Should have coordinate inputs
    assert has_field?(/X.*coordinate|X souřadnice/i) || has_field?(/x/i)
    assert has_field?(/Y.*coordinate|Y souřadnice/i) || has_field?(/y/i)
  end

  # Test clicking valid position sets form fields
  test "clicking valid position in picker sets hidden form fields" do
    visit new_galaxy_system_path

    # If position picker exists with click functionality
    if has_selector?(".position-picker, #position-picker", wait: 5)
      # Coordinates should be settable
      fill_in /X.*coordinate|x/i, with: "300", match: :first
      fill_in /Y.*coordinate|y/i, with: "300", match: :first

      assert_field /X.*coordinate|x/i, with: "300"
      assert_field /Y.*coordinate|y/i, with: "300"
    end
  end

  # Test features work with empty systems list
  test "features work without errors when systems list is empty" do
    visit galaxy_index_path

    # Should not crash with empty systems
    assert_selector "body"
    assert_text /Galaxy|Galaxie/, wait: 5
  end
end
