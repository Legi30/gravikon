# frozen_string_literal: true

require "application_system_test_case"

class SystemEditingTest < ApplicationSystemTestCase
  setup do
    @system = System.create!(name: "Edit Test System", x: 300, y: 300, json_file_path: "data/systems/edit_test.json")

    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("edit_test"), {
      bodies: [ { name: "Star", type: "star" } ]
    }.to_json)
  end

  teardown do
    File.delete(GalaxyService.system_data_path("edit_test")) if File.exist?(GalaxyService.system_data_path("edit_test"))
    @system.destroy if @system && !@system.destroyed?
  end

  # Test Edit System button appears
  test "Edit System button appears on system show page" do
    visit galaxy_system_path(@system)
    assert_link "Upravit", wait: 5
  end

  # Test edit form loads with current values
  test "edit_system form loads with current system values pre-populated" do
    visit edit_galaxy_system_path(@system)
    assert_selector "form"
    assert_field "Název soustavy", with: "Edit Test System"
  end

  # Test changing system name updates record
  test "changing system name updates System record" do
    visit edit_galaxy_system_path(@system)

    fill_in "Název soustavy", with: "Updated System Name", match: :first

    # Wait for button to become enabled
    assert_button "Uložit změny", disabled: false, wait: 5

    click_button "Uložit změny", match: :first

    @system.reload
    assert_equal "Updated System Name", @system.name
  end

  # Test form submission redirects back
  test "form submission redirects back to system show page" do
    visit edit_galaxy_system_path(@system)

    # Wait for button to become enabled
    assert_button "Uložit změny", disabled: false, wait: 5

    click_button "Uložit změny", match: :first

    # Should redirect to system show or galaxy index
    assert_current_path([ galaxy_system_path(@system), galaxy_index_path ].any?)
  end
end
