require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Meeting.delete_all
    System.delete_all
    Rails.cache.clear
  end

  # Create a System row plus its data file inside the isolated test root
  def create_system_with_bodies(name:, x:, y:, file_id:, body_names:)
    system = System.create!(name: name, x: x, y: y, json_file_path: "data/systems/#{file_id}.json")
    write_system_data(system, default_test_bodies(body_names))
    system
  end

  # === GET index ===

  test "should get index" do
    get meetings_url
    assert_response :success
  end

  test "should load all meetings in index" do
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    meeting2 = Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 60,
      avg_delay: 100
    )

    get meetings_url
    assert_response :success
    assert_not_nil assigns(:meetings)
    assert_includes assigns(:meetings), meeting1
    assert_includes assigns(:meetings), meeting2
  end

  # === GET new ===

  test "new redirects to system creation when no systems exist" do
    get new_meeting_url
    assert_redirected_to new_galaxy_system_path
  end

  test "new auto-selects the only system and loads its bodies" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])

    get new_meeting_url
    assert_response :success
    assert_equal system, assigns(:system)
    body_names = assigns(:bodies).map { |b| b["name"] }
    assert_includes body_names, "Sol"
    assert_includes body_names, "Earth"
    assert_includes body_names, "Mars"
  end

  test "new shows system selector when multiple systems exist" do
    create_system_with_bodies(name: "Alpha", x: 200, y: 200, file_id: "alpha", body_names: %w[Sol Earth Mars])
    create_system_with_bodies(name: "Beta", x: 600, y: 600, file_id: "beta", body_names: %w[Vega Jupiter Saturn])

    get new_meeting_url
    assert_response :success
    assert_select "h3", /Vyberte soustavu/
  end

  test "GET new with system_id parameter loads bodies from that system only" do
    create_system_with_bodies(name: "Alpha", x: 200, y: 200, file_id: "alpha", body_names: %w[Sol Earth Mars])
    system = create_system_with_bodies(name: "Beta", x: 600, y: 600, file_id: "beta", body_names: %w[Vega Jupiter Saturn])

    get new_meeting_url(system_id: system.id)
    assert_response :success
    body_names = assigns(:bodies).map { |b| b["name"] }
    assert_includes body_names, "Jupiter"
    assert_not_includes body_names, "Earth"
  end

  # === POST create ===

  test "should create meeting with valid data" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])

    assert_difference("Meeting.count", 1) do
      post meetings_url, params: {
        meeting: { start_time: "09:00", end_time: "10:00", topic: "Test meeting", system_id: system.id },
        participants: [ "Earth", "Mars" ]
      }
    end
    assert_redirected_to meetings_path
  end

  test "created meeting stores real duration scaled by dilation" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])

    post meetings_url, params: {
      meeting: { start_time: "10:00", end_time: "11:00", system_id: system.id },
      participants: [ "Earth", "Mars" ]
    }

    meeting = Meeting.last
    # 60 minutes × combined dilation (< 1.0) must land between 0 and 60
    assert meeting.local_avg_duration.positive?
    assert meeting.local_avg_duration <= 60.0
  end

  test "create without a system re-renders the form with an error" do
    create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])

    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: { start_time: "09:00", end_time: "10:00" },
        participants: [ "Earth", "Mars" ]
      }
    end
    assert_response :unprocessable_entity
  end

  test "create with fewer than two participants re-renders with an error" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])

    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: { start_time: "09:00", end_time: "10:00", system_id: system.id },
        participants: [ "Earth" ]
      }
    end
    assert_response :unprocessable_entity
  end

  # === GET edit / PATCH update ===

  test "should get edit" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: system
    )

    get edit_meeting_url(meeting)
    assert_response :success
  end

  test "update modifies the meeting in place without changing its id" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: system
    )
    original_id = meeting.id

    patch meeting_url(meeting), params: {
      meeting: { start_time: "11:00", end_time: "12:30", topic: "Upraveno", system_id: system.id },
      participants: [ "Earth", "Sol" ]
    }

    assert_redirected_to meetings_path
    meeting.reload
    assert_equal original_id, meeting.id
    assert_equal "11:00", meeting.start_time
    assert_equal "Upraveno", meeting.topic
    assert_includes meeting.participants_array, "Sol"
  end

  test "invalid update keeps the original meeting untouched" do
    system = create_system_with_bodies(name: "Solo", x: 200, y: 200, file_id: "solo_sys", body_names: %w[Sol Earth Mars])
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: system
    )

    assert_no_difference("Meeting.count") do
      patch meeting_url(meeting), params: {
        meeting: { start_time: "11:00", end_time: "12:00", system_id: system.id },
        participants: [ "Earth" ]
      }
    end

    assert_redirected_to edit_meeting_path(meeting)
    meeting.reload
    assert_equal "09:00", meeting.start_time
  end

  # === DELETE destroy ===

  test "should destroy meeting" do
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    assert_difference("Meeting.count", -1) do
      delete meeting_url(meeting)
    end
    assert_redirected_to meetings_path
  end

  # === Multi-System Support Tests ===

  test "GET index groups meetings by system and displays system names" do
    system1 = create_system_with_bodies(name: "Alpha", x: 300, y: 300, file_id: "alpha", body_names: %w[Sol Earth Mars])
    system2 = create_system_with_bodies(name: "Beta", x: 500, y: 500, file_id: "beta", body_names: %w[Vega Jupiter Saturn])

    Meeting.create!(start_time: "09:00", end_time: "10:00", participants: '["Earth", "Mars"]', system: system1)
    Meeting.create!(start_time: "09:00", end_time: "10:00", participants: '["Jupiter", "Saturn"]', system: system2)

    get meetings_url
    assert_response :success
    assert_select "body", /Alpha|Beta/
  end

  test "GET index row shows one lived-time bar per participant and a detail toggle" do
    system = create_system_with_bodies(name: "Alpha", x: 300, y: 300, file_id: "alpha", body_names: %w[Sol Earth Mars])
    meeting = Meeting.create!(start_time: "09:00", end_time: "10:30", participants: '["Sol", "Earth", "Mars"]', topic: "Kalibrace", system: system)

    get meetings_url
    assert_response :success

    assert_select "tr#meeting_#{meeting.id}.meeting-row" do
      assert_select ".meeting-time", "09:00–10:30"
      assert_select ".meeting-row-topic", "Kalibrace"
      assert_select ".lived-bars .lived-bar", 3
      assert_select "button.relativistic-toggle[aria-controls=?]", "relativistic-meeting_#{meeting.id}"
    end
    # The detail row spans every column of the meeting row
    assert_select "tr#relativistic-meeting_#{meeting.id} td[colspan='6']"
    assert_select "tr#relativistic-meeting_#{meeting.id} .rel-bar-dilation", 3
  end

  test "POST create with single-system participants sets is_inter_system=false" do
    system = create_system_with_bodies(name: "Sol System", x: 300, y: 300, file_id: "sol", body_names: %w[Sol Earth Mars])

    post meetings_url, params: {
      meeting: { start_time: "09:00", end_time: "10:00", system_id: system.id },
      participants: [ "Earth", "Mars" ]
    }

    meeting = Meeting.last
    assert_not meeting.is_inter_system
    assert_equal system.id, meeting.system_id
  end

  test "POST create with multi-system participants sets is_inter_system=true" do
    system1 = create_system_with_bodies(name: "Alpha", x: 200, y: 200, file_id: "alpha", body_names: %w[Sol Earth Mars])
    system2 = create_system_with_bodies(name: "Beta", x: 600, y: 600, file_id: "beta", body_names: %w[Vega Kepler Saturn])

    assert_difference("Meeting.count", 1) do
      post meetings_url, params: {
        meeting: { start_time: "09:00", end_time: "10:00", is_inter_system: "true" },
        participants: [ "Earth", "Kepler" ],
        participant_systems: { "Earth" => system1.id.to_s, "Kepler" => system2.id.to_s }
      }
    end

    meeting = Meeting.last
    assert meeting.is_inter_system
    assert_nil meeting.system_id
    assert_equal({ "Earth" => system1.id, "Kepler" => system2.id }, meeting.participant_systems_hash)
  end

  test "POST create validates participants exist in specified systems" do
    system = create_system_with_bodies(name: "Test", x: 300, y: 300, file_id: "test_validation", body_names: %w[Sol Earth Mars])

    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: { start_time: "09:00", end_time: "10:00", system_id: system.id },
        participants: [ "Earth", "NonExistent" ]
      }
    end
    assert_response :unprocessable_entity
  end

  test "strong parameters ignore unsafe attributes" do
    system = create_system_with_bodies(name: "Param Test", x: 300, y: 300, file_id: "param_test", body_names: %w[Sol Earth Mars])

    assert_nothing_raised do
      post meetings_url, params: {
        meeting: { start_time: "09:00", end_time: "10:00", system_id: system.id },
        participants: [ "Earth", "Mars" ],
        unsafe_param: "should be filtered"
      }
    end
  end
end
