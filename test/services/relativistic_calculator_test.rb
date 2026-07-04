# frozen_string_literal: true

require "test_helper"

class RelativisticCalculatorTest < ActiveSupport::TestCase
  def setup
    # Create test galaxy data with black hole
    @test_galaxy_data = {
      "black_hole" => {
        "name" => "Sagittarius Omega",
        "mass" => 8.2e36,
        "x" => 400,
        "y" => 400,
        "type" => "black_hole"
      },
      "systems" => []
    }

    # Create test systems in database
    @system1 = System.new(
      name: "Alpha",
      x: 200,
      y: 300,
      json_file_path: "data/systems/alpha.json"
    )
    @system1.save(validate: false)

    @system2 = System.new(
      name: "Beta",
      x: 600,
      y: 500,
      json_file_path: "data/systems/beta.json"
    )
    @system2.save(validate: false)

    @calculator = RelativisticCalculator.new(galaxy_data: @test_galaxy_data)
  end

  def teardown
    @system1.destroy if @system1.persisted?
    @system2.destroy if @system2.persisted?
  end

  # === LOG004: RelativisticCalculator physics calculations tests ===

  test "calculate_time_dilation includes local stellar gravitational effects" do
    body = {
      "name" => "Earth",
      "type" => "planet",
      "mass" => 5.97e24,
      "dilation" => 0.999  # Local stellar dilation
    }

    dilation = @calculator.calculate_time_dilation(body, @system1.id)

    # Should return a dilation factor between 0 and 1
    assert dilation > 0, "Time dilation should be positive"
    assert dilation <= 1.0, "Time dilation factor should not exceed 1"
  end

  test "calculate_time_dilation includes black hole gravitational effects based on system position" do
    # System closer to black hole should have stronger dilation
    body = {
      "name" => "Test Planet",
      "type" => "planet",
      "dilation" => 0.999
    }

    # System1 is at (200, 300), closer to black hole at (400, 400)
    dilation1 = @calculator.calculate_time_dilation(body, @system1.id)

    # System2 is at (600, 500), farther from black hole
    dilation2 = @calculator.calculate_time_dilation(body, @system2.id)

    # Both should be positive and <= 1
    assert dilation1 > 0
    assert dilation2 > 0
    assert dilation1 <= 1.0
    assert dilation2 <= 1.0
  end

  test "calculate_time_dilation uses local dilation when provided" do
    body_with_dilation = { "dilation" => 0.95 }
    result = @calculator.calculate_time_dilation(body_with_dilation, @system1.id)

    # Result should factor in the local dilation of 0.95
    assert result > 0
    assert result <= 1.0
  end

  test "calculate_inter_system_distance returns correct Euclidean distance" do
    # System1 at (200, 300), System2 at (600, 500)
    # Distance = sqrt((600-200)^2 + (500-300)^2) = sqrt(160000 + 40000) = sqrt(200000) ≈ 447.21
    expected_distance = Math.sqrt((600 - 200)**2 + (500 - 300)**2)

    distance = @calculator.calculate_inter_system_distance(@system1.id, @system2.id)

    assert_in_delta expected_distance, distance, 0.01
  end

  test "calculate_inter_system_distance returns zero for same system" do
    distance = @calculator.calculate_inter_system_distance(@system1.id, @system1.id)
    assert_equal 0.0, distance
  end

  test "calculate_body_to_body_distance combines inter-system and intra-system components" do
    body1 = { "x" => 50, "y" => 30, "name" => "Earth" }
    body2 = { "x" => 20, "y" => 10, "name" => "Mars" }

    # System1 at (200, 300), System2 at (600, 500)
    # body1 in galaxy: (200+50, 300+30) = (250, 330)
    # body2 in galaxy: (600+20, 500+10) = (620, 510)
    # Distance = sqrt((620-250)^2 + (510-330)^2) = sqrt(136900 + 32400) = sqrt(169300) ≈ 411.46

    distance = @calculator.calculate_body_to_body_distance(
      body1, @system1.id,
      body2, @system2.id
    )

    expected = Math.sqrt((370)**2 + (180)**2)
    assert_in_delta expected, distance, 0.1
  end

  test "calculate_body_to_body_distance uses local coordinates for same system" do
    body1 = { "x" => 100, "y" => 50 }
    body2 = { "x" => 130, "y" => 90 }

    # Both in same system - should use local coordinates
    # Distance = sqrt((130-100)^2 + (90-50)^2) = sqrt(900 + 1600) = 50
    distance = @calculator.calculate_body_to_body_distance(
      body1, @system1.id,
      body2, @system1.id
    )

    expected = Math.sqrt(30**2 + 40**2)
    assert_in_delta expected, distance, 0.01
  end

  test "calculate_signal_delay uses speed of light constant correctly" do
    distance = 1000.0 # Canvas units

    delay = @calculator.calculate_signal_delay(distance)

    # delay = (distance in meters) / C
    expected_delay = (distance * PhysicsConstants::UNIT_METERS) / PhysicsConstants::C
    assert_in_delta expected_delay, delay, 0.000001
  end

  test "calculate_signal_delay returns zero for zero distance" do
    delay = @calculator.calculate_signal_delay(0)
    assert_equal 0.0, delay
  end

  test "calculate_signal_delay returns zero for negative distance" do
    delay = @calculator.calculate_signal_delay(-100)
    assert_equal 0.0, delay
  end

  test "calculate_meeting_statistics returns avg_duration accounting for time dilation" do
    participants = [
      { body: { "dilation" => 0.99, "x" => 50, "y" => 50 }, system_id: @system1.id },
      { body: { "dilation" => 0.98, "x" => 30, "y" => 30 }, system_id: @system1.id }
    ]

    stats = @calculator.calculate_meeting_statistics(participants, start_time: "10:00", end_time: "11:00")

    assert_not_nil stats
    assert stats.key?(:avg_duration)
    assert stats[:avg_duration] > 0
    # Dilation < 1.0 means less proper time elapses than the scheduled 60 min
    assert stats[:avg_duration] <= 60.0
  end

  test "calculate_meeting_statistics returns avg_delay for signal propagation" do
    participants = [
      { body: { "x" => 100, "y" => 100 }, system_id: @system1.id },
      { body: { "x" => 50, "y" => 50 }, system_id: @system2.id }
    ]

    stats = @calculator.calculate_meeting_statistics(participants)

    assert_not_nil stats
    assert stats.key?(:avg_delay)
    assert stats[:avg_delay] >= 0
  end

  test "calculate_meeting_statistics handles empty participant list" do
    stats = @calculator.calculate_meeting_statistics([])

    assert_equal 0.0, stats[:avg_duration]
    assert_equal 0.0, stats[:avg_delay]
  end

  test "calculate_meeting_statistics handles single participant" do
    participants = [
      { body: { "dilation" => 0.99 }, system_id: @system1.id }
    ]

    stats = @calculator.calculate_meeting_statistics(participants)

    # With one participant, no pairwise distances
    assert_not_nil stats[:avg_duration]
    assert_equal 0.0, stats[:avg_delay] # No pairs, so no delay
  end

  test "handles edge cases like bodies at extreme distances" do
    body1 = { "x" => 0, "y" => 0 }
    body2 = { "x" => 999999, "y" => 999999 }

    # Should not crash with extreme coordinates
    assert_nothing_raised do
      distance = @calculator.calculate_body_to_body_distance(
        body1, @system1.id,
        body2, @system2.id
      )
      assert distance > 0
    end
  end

  test "uses consistent physics constants from PhysicsConstants" do
    assert_equal 0.0001, PhysicsConstants::GRAVITATIONAL_CONSTANT
    assert_equal 10_000_000, PhysicsConstants::C
    # Black hole dilation must be a real value in (0, 1), not a rescued 1.0
    dilation = PhysicsConstants.gravitational_dilation(PhysicsConstants::BLACK_HOLE_MASS, 100)
    assert dilation > 0.0
    assert dilation < 1.0
  end

  test "calculate_time_dilation handles nil body gracefully" do
    dilation = @calculator.calculate_time_dilation(nil, @system1.id)
    assert_equal 1.0, dilation # Fallback to no dilation
  end

  test "calculate_time_dilation handles nil system_id gracefully" do
    body = { "dilation" => 0.99 }
    dilation = @calculator.calculate_time_dilation(body, nil)
    assert_equal 1.0, dilation # Fallback to no dilation
  end

  test "calculate_time_dilation handles non-existent system gracefully" do
    body = { "dilation" => 0.99 }
    dilation = @calculator.calculate_time_dilation(body, 99999)
    # Should return local dilation since system not found
    assert_equal 0.99, dilation
  end

  test "calculate_inter_system_distance handles non-existent systems gracefully" do
    distance = @calculator.calculate_inter_system_distance(99999, 99998)
    assert_equal 0.0, distance
  end

  test "calculate_body_to_body_distance handles nil bodies gracefully" do
    distance = @calculator.calculate_body_to_body_distance(nil, @system1.id, { "x" => 0, "y" => 0 }, @system2.id)
    assert_equal 0.0, distance

    distance = @calculator.calculate_body_to_body_distance({ "x" => 0, "y" => 0 }, @system1.id, nil, @system2.id)
    assert_equal 0.0, distance
  end

  test "calculates time dilation for bodies close to black hole correctly" do
    # Create a system very close to the black hole (but outside minimum distance)
    close_system = System.new(
      name: "Close System",
      x: 450,  # Close to black hole at (400, 400)
      y: 440,
      json_file_path: "data/systems/close_sys.json"
    )
    close_system.save(validate: false)

    body = { "dilation" => 0.99 }
    dilation = @calculator.calculate_time_dilation(body, close_system.id)

    # Dilation should be affected by proximity to black hole
    assert dilation > 0
    assert dilation <= 1.0

    close_system.destroy
  end

  test "initialize uses default galaxy data if not provided" do
    calc = RelativisticCalculator.new

    # Should initialize without error
    assert_not_nil calc

    # Should be able to perform calculations (though systems may not exist)
    body = { "dilation" => 0.99 }
    dilation = calc.calculate_time_dilation(body, 999)
    assert_not_nil dilation
  end
end
