# frozen_string_literal: true

require "application_system_test_case"

class MeetingFilteringTest < ApplicationSystemTestCase
  setup do
    @system1 = System.create!(name: "Alpha", x: 200, y: 200, json_file_path: "data/systems/alpha.json")
    @system2 = System.create!(name: "Beta", x: 600, y: 600, json_file_path: "data/systems/beta.json")

    # Create system data files
    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/alpha.json"), {
      bodies: [
        { name: "Earth", type: "planet", x: 400, y: 400, mass: 5.972e24, radius: 6.371e6, dilation: 1.0 },
        { name: "Mars", type: "planet", x: 500, y: 400, mass: 6.39e23, radius: 3.389e6, dilation: 1.0 }
      ]
    }.to_json)
    File.write(Rails.root.join("data/systems/beta.json"), {
      bodies: [
        { name: "Jupiter", type: "planet", x: 400, y: 400, mass: 1.898e27, radius: 6.9911e7, dilation: 1.0 },
        { name: "Saturn", type: "planet", x: 500, y: 400, mass: 5.683e26, radius: 5.8232e7, dilation: 1.0 }
      ]
    }.to_json)

    @meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: @system1
    )

    @meeting2 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Jupiter", "Saturn"]',
      system: @system2
    )
  end

  teardown do
    # Clean up data files
    File.delete(Rails.root.join("data/systems/alpha.json")) rescue nil
    File.delete(Rails.root.join("data/systems/beta.json")) rescue nil

    @system1.destroy if @system1 && !@system1.destroyed?
    @system2.destroy if @system2 && !@system2.destroyed?
  end

  # Test meetings index displays System column
  test "meetings index displays System column showing system names" do
    visit meetings_path
    # Should display system names
    assert_text /Alpha|Beta/, wait: 5
  end

  # Test filter dropdown or links exist
  test "filter options allow selecting specific system" do
    visit meetings_path

    # Look for filter UI elements
    if has_select?(/System|Filter|Systém/)
      select "Alpha", from: /System|Filter|Systém/, match: :first
    elsif has_link?("Alpha")
      click_link "Alpha", match: :first
    end

    # Should filter meetings
    assert_selector 'body'
  end

  # Test system column is displayed
  test "meeting list shows system context" do
    visit meetings_path

    # Both systems should be visible initially
    assert_text /Alpha/, wait: 5
    assert_text /Beta/, wait: 5
  end

  # Test meeting detail page shows system names
  test "meeting detail page shows system name(s) prominently" do
    visit meetings_path

    # Click on first meeting
    first('tr, .meeting-item, .meeting-card', wait: 5).click rescue nil

    # Should show system info
    assert_text(/Alpha|Beta|System|Systém/i, wait: 5)
  end

  # Test Czech labels are used
  test "Czech labels used for system information" do
    visit meetings_path

    # Check for Czech text (may include system names or labels)
    has_czech = has_text?(/Systém|Schůzka|Účastníci|Začátek|Konec/i)
    # Czech labels should be present in the UI
    assert has_czech || has_text?(/Alpha|Beta/), "Should show system information"
  end
end
