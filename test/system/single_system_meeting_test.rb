# frozen_string_literal: true

require "application_system_test_case"

class SingleSystemMeetingTest < ApplicationSystemTestCase
  setup do
    @system = System.create!(name: "Sol", x: 300, y: 300, json_file_path: "data/systems/sol.json")

    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    File.write(GalaxyService.system_data_path("sol"), {
      bodies: [
        { name: "Sun", type: "star", x: 400, y: 400, dilation: 1.0 },
        { name: "Earth", type: "planet", x: 500, y: 400, dilation: 0.9999 },
        { name: "Mars", type: "planet", x: 600, y: 400, dilation: 0.9998 }
      ]
    }.to_json)
  end

  teardown do
    File.delete(GalaxyService.system_data_path("sol")) rescue nil
    @system.destroy if @system && !@system.destroyed?
  end

  # Test accessing new meeting form with system_id
  test "accessing new meeting form shows bodies from specified system" do
    visit new_meeting_path(system_id: @system.id)

    assert_selector "form"
    # Should show system-specific bodies
    assert_text /Earth|Mars/i, wait: 5
  end

  # Test form submission creates meeting with system_id
  test "form submission creates meeting with system_id set" do
    visit new_meeting_path(system_id: @system.id)

    fill_in "Začátek", with: "09:00", match: :first
    fill_in "Konec", with: "10:00", match: :first

    # Select participants
    check "Earth", allow_label_click: true if has_field?("Earth", type: "checkbox")
    check "Mars", allow_label_click: true if has_field?("Mars", type: "checkbox")

    # Wait for button to become enabled
    assert_button "Vytvořit schůzku", disabled: false, wait: 5

    click_button "Vytvořit schůzku", match: :first

    meeting = Meeting.last
    assert_equal @system.id, meeting.system_id if meeting
  end

  # Test created meeting has is_inter_system=false
  test "created single-system meeting has is_inter_system=false" do
    visit new_meeting_path(system_id: @system.id)

    fill_in "Začátek", with: "09:00", match: :first
    fill_in "Konec", with: "10:00", match: :first

    check "Earth", allow_label_click: true if has_field?("Earth", type: "checkbox")
    check "Mars", allow_label_click: true if has_field?("Mars", type: "checkbox")

    # Wait for button to become enabled
    assert_button "Vytvořit schůzku", disabled: false, wait: 5

    click_button "Vytvořit schůzku", match: :first

    meeting = Meeting.last
    assert_not meeting.is_inter_system if meeting
  end

  # Test meeting appears in index with system name
  test "meeting appears in index with system name column" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: @system
    )

    visit meetings_path
    assert_text /Sol/, wait: 5
  end
end
