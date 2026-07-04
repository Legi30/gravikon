# frozen_string_literal: true

require "application_system_test_case"

class SystemDeletionTest < ApplicationSystemTestCase
  setup do
    @system = System.create!(name: "Delete Test", x: 300, y: 300, json_file_path: "data/systems/delete_test.json")

    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("delete_test"), {
      bodies: [ { name: "Star", type: "star" } ]
    }.to_json)

    @svg_file = GalaxyService.system_svg_path("delete_test")
    FileUtils.mkdir_p(File.dirname(@svg_file))
    File.write(@svg_file, "<svg></svg>")
  end

  teardown do
    File.delete(GalaxyService.system_data_path("delete_test")) rescue nil
    File.delete(@svg_file) rescue nil
  end

  # Test Delete System button appears
  test "Delete System button appears on system show page" do
    visit galaxy_system_path(@system)
    assert_button "Smazat", wait: 5
  end

  # Test deletion removes system from database
  test "deletion removes System database record" do
    visit galaxy_system_path(@system)

    # Wait for button to appear
    assert_button "Smazat", wait: 5

    # Accept confirmation dialog if present
    accept_confirm do
      click_button "Smazat", match: :first
    end

    # Should redirect to galaxy index
    assert_text "Mapa galaxie", wait: 10

    # System should be deleted
    assert_not System.exists?(@system.id)
  end

  # Test deletion removes files
  test "deletion removes data JSON file and SVG file" do
    data_file = GalaxyService.system_data_path("delete_test")
    svg_file = @svg_file

    assert File.exist?(data_file), "Data file should exist before deletion"
    assert File.exist?(svg_file), "SVG file should exist before deletion"

    visit galaxy_system_path(@system)

    # Wait for button to appear
    assert_button "Smazat", wait: 5

    accept_confirm do
      click_button "Smazat", match: :first
    end

    # Wait for deletion to complete
    sleep 1

    # Files should be deleted
    assert_not File.exist?(data_file), "Data file should be deleted"
    assert_not File.exist?(svg_file), "SVG file should be deleted"
  end

  # Test redirects to galaxy index after deletion
  test "redirects to galaxy index after successful deletion" do
    visit galaxy_system_path(@system)

    # Wait for button to appear
    assert_button "Smazat", wait: 5

    accept_confirm do
      click_button "Smazat", match: :first
    end

    assert_current_path galaxy_index_path, wait: 10
  end
end
