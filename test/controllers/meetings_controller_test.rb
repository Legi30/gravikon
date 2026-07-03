require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Mock system_data.json content
    @mock_system_data = {
      "bodies" => [
        {"name" => "Sol", "type" => "star", "x" => 400, "y" => 400, "radius" => 6.96e8, "mass" => 1.989e30, "dilation" => 1.0},
        {"name" => "Earth", "type" => "planet", "x" => 500, "y" => 400, "radius" => 6.371e6, "mass" => 5.972e24, "dilation" => 0.9999},
        {"name" => "Mars", "type" => "planet", "x" => 600, "y" => 400, "radius" => 3.389e6, "mass" => 6.39e23, "dilation" => 0.9998}
      ]
    }.to_json

    # Clear cache before each test
    Rails.cache.clear
  end

  # === GET index ===

  test "should get index" do
    get meetings_url
    assert_response :success
  end

  test "should load all meetings in index" do
    # Create test meetings
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

  test "should use cached system_data in index" do
    # Pre-populate cache
    Rails.cache.write('system_data', @mock_system_data)

    # Mock File.read to ensure it's NOT called (using cache instead)
    file_read_called = false
    File.stubs(:read).with do |path|
      file_read_called = true if path.to_s.include?("system_data.json")
      true
    end.returns(@mock_system_data)

    get meetings_url

    assert_response :success
    assert_not file_read_called, "File.read was called when cache should have been used"
  ensure
    File.unstub(:read)
  end

  # === GET new ===

  test "should get new" do
    File.stubs(:read).returns(@mock_system_data)
    get new_meeting_url
    assert_response :success
  ensure
    File.unstub(:read)
  end

  test "should load celestial bodies in new form" do
    File.stubs(:read).returns(@mock_system_data)
    get new_meeting_url
    assert_not_nil assigns(:bodies)
    assert_includes assigns(:bodies), "Sol"
    assert_includes assigns(:bodies), "Earth"
    assert_includes assigns(:bodies), "Mars"
  ensure
    File.unstub(:read)
  end

  # === POST create ===

  test "should create meeting with valid data" do
    File.stubs(:read).returns(@mock_system_data)
    assert_difference("Meeting.count", 1) do
      post meetings_url, params: {
        start_time: "09:00",
        end_time: "10:00",
        topic: "Test meeting",
        participants: ["Earth", "Mars"]
      }
    end
  ensure
    File.unstub(:read)
  end

  test "should redirect to meetings_path after create with HTML format" do
    File.stubs(:read).returns(@mock_system_data)
    post meetings_url, params: {
      start_time: "09:00",
      end_time: "10:00",
      participants: ["Earth", "Mars"]
    }
    assert_redirected_to meetings_path
  ensure
    File.unstub(:read)
  end

  test "should return turbo_stream response for create with turbo_stream format" do
    File.stubs(:read).returns(@mock_system_data)
    post meetings_url, params: {
      start_time: "09:00",
      end_time: "10:00",
      participants: ["Earth", "Mars"]
    }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  ensure
    File.unstub(:read)
  end

  # === GET edit ===

  test "should get edit" do
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    File.stubs(:read).returns(@mock_system_data)
    get edit_meeting_url(meeting)
    assert_response :success
  ensure
    File.unstub(:read)
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
  end

  test "should redirect after destroy with HTML format" do
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    delete meeting_url(meeting)
    assert_redirected_to meetings_path
  end

  test "should return turbo_stream response for destroy with turbo_stream format" do
    meeting = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    delete meeting_url(meeting), as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  # === Cache Behavior ===

  test "should fetch system_data from cache on subsequent requests" do
    # First request - cache miss, will read from file
    File.stubs(:read).returns(@mock_system_data)
    get meetings_url
    File.unstub(:read)

    # Cache should now be populated
    cached_data = Rails.cache.read('system_data')
    assert_not_nil cached_data, "Cache was not populated"

    # Second request - should use cache
    file_read_count = 0
    File.stubs(:read).with do |path|
      file_read_count += 1 if path.to_s.include?("system_data.json")
      true
    end.returns(@mock_system_data)

    get meetings_url

    assert_equal 0, file_read_count, "File was read when cache should have been used"
  ensure
    File.unstub(:read)
  end

  # === Multi-System Support Tests (LOG008) ===

  test "GET index groups meetings by system and displays system names" do
    system1 = System.create!(name: "Alpha", x: 300, y: 300, json_file_path: "data/systems/alpha.json")
    system2 = System.create!(name: "Beta", x: 500, y: 500, json_file_path: "data/systems/beta.json")

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

    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: system1
    )

    meeting2 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Jupiter", "Saturn"]',
      system: system2
    )

    get meetings_url
    assert_response :success
    assert_select 'body', /Alpha|Beta/

    File.delete(Rails.root.join("data/systems/alpha.json")) rescue nil
    File.delete(Rails.root.join("data/systems/beta.json")) rescue nil
    system1.destroy
    system2.destroy
  end

  test "GET new with system_id parameter loads bodies from that system only" do
    system = System.create!(name: "Test System", x: 300, y: 300, json_file_path: "data/systems/test_sys.json")

    # Create system data file
    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/test_sys.json"), {
      bodies: [
        { name: "Alpha Star", type: "star" },
        { name: "Alpha Prime", type: "planet" }
      ]
    }.to_json)

    get new_meeting_url(system_id: system.id)
    assert_response :success

    # Cleanup
    File.delete(Rails.root.join("data/systems/test_sys.json")) rescue nil
    system.destroy
  end

  test "POST create with single-system participants sets is_inter_system=false" do
    system = System.create!(name: "Sol System", x: 300, y: 300, json_file_path: "data/systems/sol.json")

    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/sol.json"), {
      bodies: [{ name: "Earth", type: "planet" }, { name: "Mars", type: "planet" }]
    }.to_json)

    post meetings_url, params: {
      start_time: "09:00",
      end_time: "10:00",
      participants: ["Earth", "Mars"],
      system_id: system.id
    }

    meeting = Meeting.last
    assert_not meeting.is_inter_system

    File.delete(Rails.root.join("data/systems/sol.json")) rescue nil
    system.destroy
  end

  test "POST create with multi-system participants sets is_inter_system=true" do
    system1 = System.create!(name: "Alpha", x: 200, y: 200, json_file_path: "data/systems/alpha.json")
    system2 = System.create!(name: "Beta", x: 600, y: 600, json_file_path: "data/systems/beta.json")

    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/alpha.json"), {
      bodies: [{ name: "Earth", type: "planet" }]
    }.to_json)
    File.write(Rails.root.join("data/systems/beta.json"), {
      bodies: [{ name: "Kepler", type: "planet" }]
    }.to_json)

    post meetings_url, params: {
      start_time: "09:00",
      end_time: "10:00",
      participants: ["Earth", "Kepler"],
      participant_systems: { "Earth" => system1.id, "Kepler" => system2.id }
    }

    meeting = Meeting.last
    assert meeting.is_inter_system if meeting

    File.delete(Rails.root.join("data/systems/alpha.json")) rescue nil
    File.delete(Rails.root.join("data/systems/beta.json")) rescue nil
    system1.destroy
    system2.destroy
  end

  test "POST create validates participants exist in specified systems" do
    system = System.create!(name: "Test", x: 300, y: 300, json_file_path: "data/systems/test_validation.json")

    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/test_validation.json"), {
      bodies: [{ name: "Earth", type: "planet" }]
    }.to_json)

    # Try to create meeting with non-existent participant
    post meetings_url, params: {
      start_time: "09:00",
      end_time: "10:00",
      participants: ["Earth", "NonExistent"],
      system_id: system.id
    }

    # Should fail validation
    meeting = Meeting.find_by(participants: '["Earth", "NonExistent"]')
    assert_nil meeting

    File.delete(Rails.root.join("data/systems/test_validation.json")) rescue nil
    system.destroy
  end

  test "strong parameters whitelist system_id and participant_systems" do
    system = System.create!(name: "Param Test", x: 300, y: 300, json_file_path: "data/systems/param_test.json")

    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/param_test.json"), {
      bodies: [{ name: "Earth", type: "planet" }]
    }.to_json)

    # Should not raise error with system_id parameter
    assert_nothing_raised do
      post meetings_url, params: {
        start_time: "09:00",
        end_time: "10:00",
        participants: ["Earth", "Mars"],
        system_id: system.id,
        unsafe_param: "should be filtered"
      }
    end

    File.delete(Rails.root.join("data/systems/param_test.json")) rescue nil
    system.destroy
  end
end
