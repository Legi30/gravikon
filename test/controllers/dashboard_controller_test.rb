require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    Meeting.delete_all
    System.delete_all
    Rails.cache.clear

    # One real system with three bodies in the isolated test data root
    @system = System.create!(name: "Sol System", x: 200, y: 200, json_file_path: "data/systems/sol_dash.json")
    write_system_data(@system, [
      { "name" => "Sol", "type" => "star", "x" => 400, "y" => 400, "radius" => 6.96e8, "mass" => 1.989e30, "dilation" => 1.0 },
      { "name" => "Earth", "type" => "planet", "x" => 500, "y" => 400, "radius" => 6.371e6, "mass" => 5.972e24, "dilation" => 0.9999 },
      { "name" => "Mars", "type" => "planet", "x" => 600, "y" => 400, "radius" => 3.389e6, "mass" => 6.39e23, "dilation" => 0.9998 }
    ])
  end

  # === GET index ===

  test "should get index" do
    get dashboard_url
    assert_response :success
  end

  test "should load dashboard statistics with no meetings" do
    get dashboard_url

    assert_response :success
    assert_equal 0, assigns(:total_meetings)
    assert_equal 0, assigns(:avg_delay)
    assert_equal 0, assigns(:avg_duration)
    assert_equal 0, assigns(:total_time)
  end

  test "should calculate dashboard statistics with meetings" do
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

    get dashboard_url

    assert_response :success
    assert_equal 2, assigns(:total_meetings)
    assert_equal 110.0, assigns(:avg_delay) # (120 + 100) / 2
    assert_equal 75.0, assigns(:avg_duration) # (60 + 90) / 2
    assert_equal 150.0, assigns(:total_time) # 60 + 90
  end

  test "should calculate participant frequency" do
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

    get dashboard_url

    assert_response :success
    participant_freq = assigns(:participant_frequency)
    assert_equal 3, participant_freq["Earth"]
    assert_equal 2, participant_freq["Mars"]
    assert_equal 1, participant_freq["Sol"]
  end

  test "should calculate duration distribution" do
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

    get dashboard_url

    assert_response :success
    duration_dist = assigns(:duration_distribution)
    assert_equal 1, duration_dist["0-30 min"]
    assert_equal 1, duration_dist["31-60 min"]
    assert_equal 1, duration_dist["61-90 min"]
    assert_equal 0, duration_dist["91-120 min"]
    assert_equal 0, duration_dist["120+ min"]
  end

  test "should identify featured meetings" do
    Meeting.create!(
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

    get dashboard_url

    assert_response :success
    assert_equal meeting2.id, assigns(:longest_meeting).id
    assert_equal meeting3.id, assigns(:highest_delay_meeting).id
  end

  test "should load recent meetings" do
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

    get dashboard_url

    assert_response :success
    recent = assigns(:recent_meetings)
    assert_equal 2, recent.length
    # Most recent should be first
    assert_equal meeting2.id, recent.first.id
    assert_equal meeting1.id, recent.last.id
  end

  test "should count bodies across all systems" do
    get dashboard_url

    assert_response :success
    assert_equal 3, assigns(:total_bodies)
  end

  test "should handle missing system data file gracefully" do
    File.delete(@system.data_file_path)
    GalaxyService.clear_system_cache(@system.system_id)

    get dashboard_url

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

    get dashboard_url
    assert_response :success

    # Verify cache was populated
    cache_key = "dashboard_stats_v2_#{Meeting.maximum(:updated_at).to_i}"
    cached_data = Rails.cache.read(cache_key)
    assert_not_nil cached_data, "Dashboard stats were not cached"
    assert_equal 1, cached_data[:total_meetings]
  end

  test "should use cached dashboard statistics on subsequent requests" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    # First request - cache miss
    get dashboard_url
    assert_response :success

    cache_key = "dashboard_stats_v2_#{Meeting.maximum(:updated_at).to_i}"
    cached_stats = Rails.cache.read(cache_key)
    assert_not_nil cached_stats

    # Second request - should use cache (won't recalculate stats)
    get dashboard_url
    assert_response :success
    assert_equal cached_stats[:total_meetings], assigns(:total_meetings)
    assert_equal cached_stats[:avg_delay], assigns(:avg_delay)
  end

  test "should not cache featured meetings" do
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

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
