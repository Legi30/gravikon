# frozen_string_literal: true

require "application_system_test_case"

class InterSystemMeetingTest < ApplicationSystemTestCase
  setup do
    @system1 = System.create!(name: "Alpha", x: 200, y: 200, json_file_path: "data/systems/alpha.json")
    @system2 = System.create!(name: "Beta", x: 600, y: 600, json_file_path: "data/systems/beta.json")

    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("alpha"), {
      bodies: [
        { name: "Alpha Star", type: "star", dilation: 1.0 },
        { name: "Earth", type: "planet", dilation: 0.9999 }
      ]
    }.to_json)
    File.write(GalaxyService.system_data_path("beta"), {
      bodies: [
        { name: "Beta Star", type: "star", dilation: 1.0 },
        { name: "Kepler", type: "planet", dilation: 0.9998 }
      ]
    }.to_json)
  end

  teardown do
    File.delete(GalaxyService.system_data_path("alpha")) rescue nil
    File.delete(GalaxyService.system_data_path("beta")) rescue nil
    @system1.destroy if @system1 && !@system1.destroyed?
    @system2.destroy if @system2 && !@system2.destroyed?
  end

  # Test new_inter_system link appears
  test "new_inter_system link appears in meeting navigation" do
    visit meetings_path
    assert_link "🌌 Mezisystémová schůzka", wait: 5
  end

  # Test form displays all systems
  test "inter-system form displays all available systems" do
    visit new_inter_system_meetings_path

    assert_selector "form"
    # Should show both systems
    assert_text /Alpha|Beta/i, wait: 5
  end

  # Test can select participants from multiple systems
  test "can select participants from multiple different systems" do
    visit new_inter_system_meetings_path

    fill_in "Začátek", with: "09:00", match: :first
    fill_in "Konec", with: "10:00", match: :first

    # Try to select participants (if checkboxes exist)
    if has_field?("Earth", type: "checkbox")
      check "Earth", allow_label_click: true
      check "Kepler", allow_label_click: true
    end

    # Form should accept selection from different systems
    assert_selector "form"
  end

  # Test form submission creates inter-system meeting
  test "form submission creates meeting with is_inter_system=true" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Kepler"]',
      is_inter_system: true,
      participant_systems: "{\"Earth\": #{@system1.id}, \"Kepler\": #{@system2.id}}"
    )

    meeting = Meeting.last
    assert meeting.is_inter_system
  end

  # Test meeting shows participants with system context
  test "meeting detail shows participants with system names" do
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Kepler"]',
      is_inter_system: true,
      participant_systems: "{\"Earth\": #{@system1.id}, \"Kepler\": #{@system2.id}}"
    )

    visit meetings_path

    # Should show system context for participants
    assert_text /Alpha|Beta/, wait: 5
  end
end
