require "test_helper"

class SystemsControllerTest < ActionDispatch::IntegrationTest
  # === GET show ===

  test "should get show" do
    get systems_url
    assert_response :success
  end

  # === POST regenerate - Basic Functionality ===

  test "should delete all meetings on regenerate" do
    # Create some test meetings first
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )

    assert_difference("Meeting.count", -Meeting.count) do
      post regenerate_system_url, params: { num_planets: 5, max_moons: 2 }
    end
  end

  test "should enqueue GenerateSystemJob on regenerate" do
    assert_enqueued_with(job: GenerateSystemJob, args: [5, 2]) do
      post regenerate_system_url, params: { num_planets: 5, max_moons: 2 }
    end
  end

  test "should redirect after regenerate" do
    post regenerate_system_url, params: { num_planets: 5, max_moons: 2 }
    assert_redirected_to systems_path
  end

  test "should show success notice after regenerate" do
    post regenerate_system_url, params: { num_planets: 5, max_moons: 2 }
    assert_match /generování soustavy/i, flash[:notice]
  end

  # === Parameter Validation ===

  test "should accept valid num_planets parameter" do
    post regenerate_system_url, params: { num_planets: 7, max_moons: 3 }
    assert_response :redirect
    assert_nil flash[:alert]
  end

  test "should handle missing num_planets with default" do
    post regenerate_system_url, params: { max_moons: 2 }
    assert_response :redirect
    # Should use default value and not error
  end

  test "should handle missing max_moons with default" do
    post regenerate_system_url, params: { num_planets: 5 }
    assert_response :redirect
    # Should use default value and not error
  end

  test "should handle invalid num_planets (non-integer)" do
    post regenerate_system_url, params: { num_planets: "invalid", max_moons: 2 }
    assert_response :redirect
    assert_match /neplatné parametry/i, flash[:alert]
  end

  test "should handle invalid max_moons (non-integer)" do
    post regenerate_system_url, params: { num_planets: 5, max_moons: "invalid" }
    assert_response :redirect
    assert_match /neplatné parametry/i, flash[:alert]
  end

  # === Parameter Clamping ===

  test "should clamp num_planets above maximum (11 -> 10)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [10, 2]) do
      post regenerate_system_url, params: { num_planets: 11, max_moons: 2 }
    end
  end

  test "should clamp num_planets below minimum (0 -> 1)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [1, 2]) do
      post regenerate_system_url, params: { num_planets: 0, max_moons: 2 }
    end
  end

  test "should clamp max_moons above maximum (6 -> 5)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [5, 5]) do
      post regenerate_system_url, params: { num_planets: 5, max_moons: 6 }
    end
  end

  test "should clamp max_moons below minimum (-1 -> 0)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [5, 0]) do
      post regenerate_system_url, params: { num_planets: 5, max_moons: -1 }
    end
  end

  # === Boundary Values ===

  test "should accept num_planets at lower boundary (1)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [1, 2]) do
      post regenerate_system_url, params: { num_planets: 1, max_moons: 2 }
    end
  end

  test "should accept num_planets at upper boundary (10)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [10, 2]) do
      post regenerate_system_url, params: { num_planets: 10, max_moons: 2 }
    end
  end

  test "should accept max_moons at lower boundary (0)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [5, 0]) do
      post regenerate_system_url, params: { num_planets: 5, max_moons: 0 }
    end
  end

  test "should accept max_moons at upper boundary (5)" do
    assert_enqueued_with(job: GenerateSystemJob, args: [5, 5]) do
      post regenerate_system_url, params: { num_planets: 5, max_moons: 5 }
    end
  end
end
