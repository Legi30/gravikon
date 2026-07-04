# frozen_string_literal: true

require "test_helper"

class OrbitValidatorTest < ActiveSupport::TestCase
  setup do
    @galaxy_data = {
      "black_hole" => { "x" => 400, "y" => 400 },
      "systems" => [
        { "id" => "system1", "x" => 300, "y" => 300 },
        { "id" => "system2", "x" => 500, "y" => 500 }
      ]
    }
  end

  # Test validate_system_orbit accepts positions within 50-750 canvas range
  test "validate_system_orbit accepts positions within recommended range" do
    result = OrbitValidator.validate_system_orbit(200, 200, @galaxy_data)
    assert result[:valid], "Should accept position in recommended range: #{result[:errors]}"
    assert_empty result[:errors]
  end

  # Test validate_system_orbit rejects positions outside 0-800 absolute bounds
  test "validate_system_orbit rejects positions outside absolute bounds" do
    result = OrbitValidator.validate_system_orbit(-10, 300, @galaxy_data)
    assert_not result[:valid]
    assert result[:errors].any?

    result = OrbitValidator.validate_system_orbit(850, 300, @galaxy_data)
    assert_not result[:valid]
    assert result[:errors].any?
  end

  # Test validate_system_orbit enforces minimum distance from black hole
  test "validate_system_orbit enforces minimum distance from black hole" do
    # Position too close to black hole at (400, 400)
    result = OrbitValidator.validate_system_orbit(410, 410, @galaxy_data)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("černé díry") || e.include?("blízko") }
  end

  # Test validate_system_orbit detects collisions with existing systems
  test "validate_system_orbit detects collisions with existing systems" do
    # Position too close to system1 at (300, 300)
    result = OrbitValidator.validate_system_orbit(310, 310, @galaxy_data)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("kolize") || e.include?("systém") }
  end

  # Test validate_system_orbit with exclude_system_id option
  test "validate_system_orbit allows excluding specific system from collision check" do
    # Position at system1's location should fail normally
    result = OrbitValidator.validate_system_orbit(300, 300, @galaxy_data)
    assert_not result[:valid]

    # But should succeed when excluding system1
    result = OrbitValidator.validate_system_orbit(300, 300, @galaxy_data, exclude_system_id: "system1")
    assert result[:valid], "Should be valid when excluding self: #{result[:errors]}"
  end

  # Test returns {valid: true, errors: []} for valid positions
  test "returns correct structure for valid position" do
    result = OrbitValidator.validate_system_orbit(600, 200, @galaxy_data)
    assert_instance_of Hash, result
    assert result.key?(:valid)
    assert result.key?(:errors)
    assert_equal true, result[:valid]
    assert_instance_of Array, result[:errors]
    assert_empty result[:errors]
  end

  # Test returns {valid: false, errors: [...]} with Czech messages for invalid positions
  test "returns correct structure with Czech error messages for invalid position" do
    result = OrbitValidator.validate_system_orbit(410, 410, @galaxy_data)
    assert_instance_of Hash, result
    assert result.key?(:valid)
    assert result.key?(:errors)
    assert_equal false, result[:valid]
    assert_instance_of Array, result[:errors]
    assert_not_empty result[:errors]

    # Check that error messages are in Czech (contain Czech characters or known Czech words)
    czech_indicators = [ "musí", "je", "systém", "černé díry", "blízko", "kolize" ]
    has_czech = result[:errors].any? { |error|
      czech_indicators.any? { |indicator| error.include?(indicator) }
    }
    assert has_czech, "Error messages should be in Czech"
  end

  # Test configurable constants for margins and minimum distances
  test "uses configurable constants for validation" do
    assert_kind_of Numeric, OrbitValidator::MIN_DISTANCE_FROM_BLACK_HOLE
    assert_kind_of Numeric, OrbitValidator::MIN_DISTANCE_BETWEEN_SYSTEMS

    assert OrbitValidator::MIN_DISTANCE_FROM_BLACK_HOLE > 0
    assert OrbitValidator::MIN_DISTANCE_BETWEEN_SYSTEMS > 0
  end

  # Test validate_body_orbit ensures bodies stay within system bounds
  test "validate_body_orbit ensures bodies stay within canvas" do
    # Parent at system center (400, 400)
    parent_x = 400
    parent_y = 400

    # Test valid position: within canvas (30-770) and within max orbit radius (370 from center)
    # Position (200, 400) is 200 units from center, well within limits
    result = OrbitValidator.validate_body_orbit(200, 400, parent_x, parent_y)
    assert result[:valid], "Body within canvas and orbit radius should be valid"

    # Test invalid: outside canvas bounds (x < 30)
    result = OrbitValidator.validate_body_orbit(-10, 400, parent_x, parent_y)
    assert_not result[:valid], "Body outside canvas should be invalid"

    # Test invalid: outside canvas bounds (x > 770)
    result = OrbitValidator.validate_body_orbit(850, 400, parent_x, parent_y)
    assert_not result[:valid], "Body outside canvas should be invalid"
  end

  # Test handles edge case with empty systems array
  test "validate_system_orbit handles empty systems array" do
    empty_galaxy = {
      "black_hole" => { "x" => 400, "y" => 400 },
      "systems" => []
    }

    result = OrbitValidator.validate_system_orbit(200, 200, empty_galaxy)
    # Should only check distance from black hole, no collision with systems
    assert result[:valid], "Should be valid with no other systems: #{result[:errors]}"
  end

  # Test handles missing galaxy data gracefully
  test "validate_system_orbit handles nil galaxy data" do
    result = OrbitValidator.validate_system_orbit(200, 200, nil)
    # Should handle gracefully, either return valid or provide appropriate error
    assert_instance_of Hash, result
    assert result.key?(:valid)
    assert result.key?(:errors)
  end
end
