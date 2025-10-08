require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
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
    File.stub :read, @mock_system_data do
      get dashboard_url
    end
    assert_response :success
  end

  test "should load dashboard statistics with no meetings" do
    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    assert_equal 0, assigns(:total_meetings)
    assert_equal 0, assigns(:avg_delay)
    assert_equal 0, assigns(:avg_duration)
    assert_equal 0, assigns(:total_time)
  end

  test "should calculate dashboard statistics with meetings" do
    # Create test meetings
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    assert_equal 2, assigns(:total_meetings)
    assert_equal 110.0, assigns(:avg_delay) # (120 + 100) / 2
    assert_equal 75.0, assigns(:avg_duration) # (60 + 90) / 2
    assert_equal 150.0, assigns(:total_time) # 60 + 90
  end

  test "should calculate participant frequency" do
    # Create meetings with different participants
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 60,
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "11:00",
      end_time: "12:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 110
    )

    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    participant_freq = assigns(:participant_frequency)
    assert_equal 3, participant_freq["Earth"]
    assert_equal 2, participant_freq["Mars"]
    assert_equal 1, participant_freq["Sol"]
  end

  test "should calculate duration distribution" do
    # Create meetings with different durations
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 20, # 0-30 min
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 45, # 31-60 min
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "11:00",
      end_time: "12:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 75, # 61-90 min
      avg_delay: 110
    )

    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    duration_dist = assigns(:duration_distribution)
    assert_equal 1, duration_dist["0-30 min"]
    assert_equal 1, duration_dist["31-60 min"]
    assert_equal 1, duration_dist["61-90 min"]
    assert_equal 0, duration_dist["91-120 min"]
    assert_equal 0, duration_dist["120+ min"]
  end

  test "should identify featured meetings" do
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
      local_avg_duration: 120, # Longest
      avg_delay: 100
    )
    meeting3 = Meeting.create!(
      start_time: "16:00",
      end_time: "17:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 45,
      avg_delay: 200 # Highest delay
    )

    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    assert_equal meeting2.id, assigns(:longest_meeting).id
    assert_equal meeting3.id, assigns(:highest_delay_meeting).id
  end

  test "should load recent meetings" do
    # Create meetings with different timestamps
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    sleep 0.01 # Ensure different created_at timestamps
    meeting2 = Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    recent = assigns(:recent_meetings)
    assert_equal 2, recent.length
    # Most recent should be first
    assert_equal meeting2.id, recent.first.id
    assert_equal meeting1.id, recent.last.id
  end

  test "should load system data bodies" do
    File.stub :read, @mock_system_data do
      get dashboard_url
    end

    assert_response :success
    assert_not_nil assigns(:system_data)
    assert_equal 3, assigns(:total_bodies)
  end

  test "should handle missing system_data.json gracefully" do
    File.stub :read, lambda { |*args|
      raise Errno::ENOENT if args[0].to_s.include?("system_data.json")
    } do
      get dashboard_url
    end

    assert_response :success
    assert_equal 0, assigns(:total_bodies)
  end

  test "should cache dashboard statistics" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    File.stub :read, @mock_system_data do
      # First request - should cache
      get dashboard_url
      assert_response :success

      # Verify cache was populated
      cache_key = "dashboard_stats_v2_#{Meeting.maximum(:updated_at).to_i}"
      cached_data = Rails.cache.read(cache_key)
      assert_not_nil cached_data, "Dashboard stats were not cached"
      assert_equal 1, cached_data[:total_meetings]
    end
  end

  test "should use cached dashboard statistics on subsequent requests" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    File.stub :read, @mock_system_data do
      # First request - cache miss
      get dashboard_url
      assert_response :success

      # Manually verify cache key
      cache_key = "dashboard_stats_v2_#{Meeting.maximum(:updated_at).to_i}"
      cached_stats = Rails.cache.read(cache_key)
      assert_not_nil cached_stats

      # Second request - should use cache (won't recalculate stats)
      # This is tested by ensuring the stats are consistent
      get dashboard_url
      assert_response :success
      assert_equal cached_stats[:total_meetings], assigns(:total_meetings)
      assert_equal cached_stats[:avg_delay], assigns(:avg_delay)
    end
  end

  test "should not cache featured meetings" do
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    File.stub :read, @mock_system_data do
      # First request
      get dashboard_url
      assert_response :success
      assert_equal meeting1.id, assigns(:longest_meeting).id

      # Create a new longer meeting
      meeting2 = Meeting.create!(
        start_time: "14:00",
        end_time: "15:00",
        participants: '["Earth", "Sol"]',
        local_avg_duration: 120,
        avg_delay: 100
      )

      # Second request - should show NEW longest meeting (not cached)
      get dashboard_url
      assert_response :success
      assert_equal meeting2.id, assigns(:longest_meeting).id
    end
  end
end
