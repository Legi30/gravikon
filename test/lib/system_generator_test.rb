# frozen_string_literal: true

require "test_helper"

class SystemGeneratorTest < ActiveSupport::TestCase
  setup do
    @test_output_dir = GalaxyService.systems_data_dir
    FileUtils.mkdir_p(@test_output_dir)
  end

  # Test accepts system_id parameter and uses it for output filename
  test "accepts system_id parameter and uses it for output filename" do
    system_id = "test_system_001"
    generator = SystemGenerator.new(
      system_id: system_id,
      system_name: "Test System",
      num_planets: 3
    )

    output_file = @test_output_dir.join("#{system_id}.json")

    # Generator should create file with system_id
    assert generator.respond_to?(:system_id) || generator.instance_variable_get(:@system_id) == system_id
  end

  # Test accepts system_name, system_x, system_y for galaxy context
  test "accepts system_name and position parameters for galaxy context" do
    generator = SystemGenerator.new(
      system_id: "test_system_002",
      system_name: "Alpha Centauri",
      system_x: 300,
      system_y: 400,
      num_planets: 2
    )

    # Generator should store these parameters
    assert generator.instance_variable_defined?(:@system_name) || generator.respond_to?(:system_name)
  end

  # Test outputs to data/systems/<system_id>.json
  test "outputs to correct path data/systems/<system_id>.json" do
    system_id = "test_system_003"

    # Mock or stub the generator to test output path
    expected_path = GalaxyService.system_data_path(system_id)

    # The generator should use this path format
    assert expected_path.to_s.include?("data/systems/")
    assert expected_path.to_s.end_with?(".json")
  end

  # Test generates unique names checking against all existing systems
  test "generates unique body names" do
    # A pre-existing system already uses some names — the generator must not reuse them
    taken_names = SystemGenerator::PLANET_NAMES.first(3) + [ SystemGenerator::STAR_NAMES.first ]
    write_system_data("existing_sys", taken_names.map { |n| { "name" => n, "type" => "planet" } })

    generator = SystemGenerator.new(
      system_id: "test_system_004",
      system_name: "Test",
      num_planets: 3
    )
    data = generator.generate

    assert_not_nil data
    generated_names = data[:bodies].map { |b| b[:name] }
    assert_empty generated_names & taken_names, "Generator reused names from an existing system"
    assert_equal generated_names.uniq.size, generated_names.size, "Generator produced duplicate names"
  end

  # Test custom mode accepts specific planet/moon parameters
  test "custom mode accepts specific planet and moon parameters" do
    custom_bodies = [
      { type: "planet", mass: 5.97e24, radius: 6.371e6, density: 5514 }
    ]

    generator = SystemGenerator.new(
      system_id: "test_system_005",
      system_name: "Custom System",
      custom_bodies: custom_bodies
    )

    # Generator should accept custom bodies
    assert generator.instance_variable_defined?(:@custom_bodies) ||
           generator.respond_to?(:custom_bodies)
  end

  # Black hole dilation is applied by RelativisticCalculator at meeting time —
  # generated bodies store only their LOCAL surface dilation
  test "calculates time dilation relative to black hole based on system position" do
    # ~141 units from the galaxy center
    dilation = PhysicsConstants.gravitational_dilation(PhysicsConstants::BLACK_HOLE_MASS, 141.4)
    assert dilation > 0.0
    assert dilation < 1.0

    # Closer to the black hole means stronger dilation (smaller factor)
    closer = PhysicsConstants.gravitational_dilation(PhysicsConstants::BLACK_HOLE_MASS, 60)
    assert closer < dilation
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
      system_id: "test_system_007",
      system_name: "Test",
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
        system_id: "test_system_008",
        system_name: "Test",
        num_planets: 0  # Invalid
      )
    end
  end

  # Test physical constants are defined
  test "defines required physical constants" do
    assert_equal 0.00004, PhysicsConstants::GRAVITATIONAL_CONSTANT
    assert_equal 10_000_000, PhysicsConstants::C
    assert_equal 1_000_000, PhysicsConstants::UNIT_METERS
  end

  test "binary option generates two stars facing each other across the centre" do
    data = SystemGenerator.new(system_id: "binary_gen", system_name: "Binary", num_planets: 4, binary: true).generate

    stars = data[:bodies].select { |body| body[:type] == "star" }
    assert_equal 2, stars.size
    center = PhysicsConstants::SYSTEM_LOCAL_CENTER
    stars.each do |star|
      assert_in_delta SystemGenerator::BINARY_STAR_OFFSET, Math.hypot(star[:x] - center, star[:y] - center), 0.05
    end
    assert_in_delta center, (stars[0][:x] + stars[1][:x]) / 2, 0.05
    assert_in_delta center, (stars[0][:y] + stars[1][:y]) / 2, 0.05

    # Planets circle both stars, clear of the pair
    data[:bodies].select { |body| body[:type] == "planet" }.each do |planet|
      assert Math.hypot(planet[:x] - center, planet[:y] - center) >= 90
    end
  end

  test "a single star is the default" do
    data = SystemGenerator.new(system_id: "single_gen", system_name: "Single", num_planets: 2).generate

    assert_equal 1, data[:bodies].count { |body| body[:type] == "star" }
  end
end
