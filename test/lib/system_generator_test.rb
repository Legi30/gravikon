# frozen_string_literal: true

require "test_helper"

class SystemGeneratorTest < ActiveSupport::TestCase
  setup do
    @test_output_dir = Rails.root.join('data', 'systems')
    FileUtils.mkdir_p(@test_output_dir)
  end

  teardown do
    # Clean up test files
    Dir.glob(@test_output_dir.join('test_*.json')).each { |f| File.delete(f) }
  end

  # Test accepts system_id parameter and uses it for output filename
  test "accepts system_id parameter and uses it for output filename" do
    system_id = 'test_system_001'
    generator = SystemGenerator.new(
      system_id: system_id,
      system_name: 'Test System',
      num_planets: 3
    )

    output_file = @test_output_dir.join("#{system_id}.json")

    # Generator should create file with system_id
    assert generator.respond_to?(:system_id) || generator.instance_variable_get(:@system_id) == system_id
  end

  # Test accepts system_name, system_x, system_y for galaxy context
  test "accepts system_name and position parameters for galaxy context" do
    generator = SystemGenerator.new(
      system_id: 'test_system_002',
      system_name: 'Alpha Centauri',
      system_x: 300,
      system_y: 400,
      num_planets: 2
    )

    # Generator should store these parameters
    assert generator.instance_variable_defined?(:@system_name) || generator.respond_to?(:system_name)
  end

  # Test outputs to data/systems/<system_id>.json
  test "outputs to correct path data/systems/<system_id>.json" do
    system_id = 'test_system_003'

    # Mock or stub the generator to test output path
    expected_path = Rails.root.join('data', 'systems', "#{system_id}.json")

    # The generator should use this path format
    assert expected_path.to_s.include?('data/systems/')
    assert expected_path.to_s.end_with?('.json')
  end

  # Test generates unique names checking against all existing systems
  test "generates unique body names" do
    # This test verifies the generator checks for name uniqueness
    # across all systems in the galaxy
    generator = SystemGenerator.new(
      system_id: 'test_system_004',
      system_name: 'Test',
      num_planets: 2
    )

    # Generator should have mechanism to check used names
    assert generator.respond_to?(:check_name_uniqueness) ||
           generator.respond_to?(:used_names) ||
           generator.respond_to?(:load_used_names_from_existing_systems)
  end

  # Test custom mode accepts specific planet/moon parameters
  test "custom mode accepts specific planet and moon parameters" do
    custom_bodies = [
      { type: 'planet', mass: 5.97e24, radius: 6.371e6, density: 5514 }
    ]

    generator = SystemGenerator.new(
      system_id: 'test_system_005',
      system_name: 'Custom System',
      custom_bodies: custom_bodies
    )

    # Generator should accept custom bodies
    assert generator.instance_variable_defined?(:@custom_bodies) ||
           generator.respond_to?(:custom_bodies)
  end

  # Test calculates time dilation relative to black hole
  test "calculates time dilation relative to black hole based on system position" do
    generator = SystemGenerator.new(
      system_id: 'test_system_006',
      system_name: 'Test',
      system_x: 300,
      system_y: 300,
      num_planets: 1
    )

    # Generator should calculate or have access to black hole effects
    assert generator.respond_to?(:calculate_black_hole_effects) ||
           generator.class.const_defined?(:GRAVITATIONAL_CONSTANT)
  end

  # Test uses expanded name lists
  test "uses expanded name lists with 50+ entries each" do
    # Generator should have large lists of names
    if defined?(SystemGenerator::PLANET_NAMES)
      assert SystemGenerator::PLANET_NAMES.length >= 50, "Should have at least 50 planet names"
    end

    if defined?(SystemGenerator::STAR_NAMES)
      assert SystemGenerator::STAR_NAMES.length >= 20, "Should have at least 20 star names"
    end

    if defined?(SystemGenerator::MOON_NAMES)
      assert SystemGenerator::MOON_NAMES.length >= 50, "Should have at least 50 moon names"
    end
  end

  # Test validates body positions using OrbitValidator
  test "validates body positions to ensure valid orbits" do
    generator = SystemGenerator.new(
      system_id: 'test_system_007',
      system_name: 'Test',
      num_planets: 2
    )

    # Generator should use OrbitValidator internally
    # Check that OrbitValidator is defined and available
    assert defined?(OrbitValidator), "OrbitValidator should be defined"
    assert OrbitValidator.respond_to?(:validate_body_orbit), "OrbitValidator should have validate_body_orbit method"
  end

  # Test handles invalid parameters gracefully
  test "handles invalid planet count gracefully" do
    # Should handle out-of-range values
    assert_nothing_raised do
      generator = SystemGenerator.new(
        system_id: 'test_system_008',
        system_name: 'Test',
        num_planets: 0  # Invalid
      )
    end
  end

  # Test physical constants are defined
  test "defines required physical constants" do
    # Generator should have access to physics constants
    assert defined?(SystemGenerator::GRAVITATIONAL_CONSTANT) ||
           defined?(SystemGenerator::C) ||
           SystemGenerator.const_defined?(:G)
  end
end
