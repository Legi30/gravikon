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
    File.stub :read, lambda { |*args|
      file_read_called = true if args[0].to_s.include?("system_data.json")
      @mock_system_data
    } do
      get meetings_url
    end

    assert_response :success
    assert_not file_read_called, "File.read was called when cache should have been used"
  end

  # === GET new ===

  test "should get new" do
    File.stub :read, @mock_system_data do
      get new_meeting_url
    end
    assert_response :success
  end

  test "should load celestial bodies in new form" do
    File.stub :read, @mock_system_data do
      get new_meeting_url
      assert_not_nil assigns(:bodies)
      assert_includes assigns(:bodies), "Sol"
      assert_includes assigns(:bodies), "Earth"
      assert_includes assigns(:bodies), "Mars"
    end
  end

  # === POST create ===

  test "should create meeting with valid data" do
    File.stub :read, @mock_system_data do
      assert_difference("Meeting.count", 1) do
        post meetings_url, params: {
          start_time: "09:00",
          end_time: "10:00",
          topic: "Test meeting",
          participants: ["Earth", "Mars"]
        }
      end
    end
  end

  test "should redirect to meetings_path after create with HTML format" do
    File.stub :read, @mock_system_data do
      post meetings_url, params: {
        start_time: "09:00",
        end_time: "10:00",
        participants: ["Earth", "Mars"]
      }
      assert_redirected_to meetings_path
    end
  end

  test "should return turbo_stream response for create with turbo_stream format" do
    File.stub :read, @mock_system_data do
      post meetings_url, params: {
        start_time: "09:00",
        end_time: "10:00",
        participants: ["Earth", "Mars"]
      }, as: :turbo_stream

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
    end
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

    File.stub :read, @mock_system_data do
      get edit_meeting_url(meeting)
    end
    assert_response :success
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
    File.stub :read, @mock_system_data do
      get meetings_url
    end

    # Cache should now be populated
    cached_data = Rails.cache.read('system_data')
    assert_not_nil cached_data, "Cache was not populated"

    # Second request - should use cache
    file_read_count = 0
    File.stub :read, lambda { |*args|
      file_read_count += 1 if args[0].to_s.include?("system_data.json")
      @mock_system_data
    } do
      get meetings_url
    end

    assert_equal 0, file_read_count, "File was read when cache should have been used"
  end
end
