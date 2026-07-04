# frozen_string_literal: true

require "test_helper"

class SecurityValidationsTest < ActiveSupport::TestCase
  def setup
    Rails.cache.clear

    # Create test galaxy data
    @test_galaxy_file = Rails.root.join('data', 'galaxy_data.json')
    @test_galaxy_data = {
      'black_hole' => { 'name' => 'Sagittarius Omega', 'mass' => 8.2e36, 'x' => 400, 'y' => 400 },
      'systems' => []
    }
    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))
  end

  def teardown
    File.delete(@test_galaxy_file) if File.exist?(@test_galaxy_file)
    Rails.cache.clear
  end

  # === Path Traversal Prevention Tests ===

  test "System model rejects path traversal in json_file_path" do
    system = System.new(
      name: "Evil System",
      x: 300,
      y: 300,
      json_file_path: "data/systems/../../etc/passwd"
    )

    assert_not system.valid?
    assert system.errors[:json_file_path].any? { |e| e.include?("..") }
  end

  test "System model rejects absolute paths in json_file_path" do
    system = System.new(
      name: "Absolute Path System",
      x: 300,
      y: 300,
      json_file_path: "/etc/passwd"
    )

    assert_not system.valid?
    assert system.errors[:json_file_path].any? { |e| e.include?("absolutní") || e.include?("absolute") }
  end

  test "System model rejects json_file_path not in data/systems/" do
    system = System.new(
      name: "Wrong Dir System",
      x: 300,
      y: 300,
      json_file_path: "other_dir/system.json"
    )

    assert_not system.valid?
    assert system.errors[:json_file_path].any? { |e| e.include?("data/systems") }
  end

  test "System model rejects json_file_path without .json extension" do
    system = System.new(
      name: "Wrong Extension",
      x: 300,
      y: 300,
      json_file_path: "data/systems/system.txt"
    )

    assert_not system.valid?
    assert system.errors[:json_file_path].any? { |e| e.include?(".json") }
  end

  test "System model rejects invalid filename characters in json_file_path" do
    system = System.new(
      name: "Invalid Chars",
      x: 300,
      y: 300,
      json_file_path: "data/systems/system@#$.json"
    )

    assert_not system.valid?
    assert system.errors[:json_file_path].any?
  end

  test "GalaxyService sanitizes system_id to prevent path traversal" do
    # Try to load with path traversal attempt
    data = GalaxyService.load_system_data('../../../etc/passwd')
    assert_nil data, "Should reject path traversal and return nil"
  end

  test "GalaxyService sanitizes system_id to reject directory separators" do
    data = GalaxyService.load_system_data('evil/path/system')
    assert_nil data, "Should reject directory separators"

    data = GalaxyService.load_system_data('evil\\path\\system')
    assert_nil data, "Should reject backslash separators"
  end

  # === Input Validation Tests ===

  test "System name validation enforces 3-50 character limit" do
    # Too short
    system = System.new(name: "AB", x: 300, y: 300)
    assert_not system.valid?

    # Too long
    system = System.new(name: "A" * 51, x: 300, y: 300)
    assert_not system.valid?

    # Just right
    system = System.new(name: "ABC", x: 300, y: 300)
    # May have other validation errors but not name length
    system.valid?
    length_errors = system.errors[:name].select { |e| e.include?("3-50") }
    assert_empty length_errors
  end

  test "System name validation allows only alphanumeric, spaces, hyphens" do
    # Invalid characters
    system = System.new(name: 'System@#$', x: 300, y: 300)
    assert_not system.valid?
    assert system.errors[:name].any? { |e| e.include?('alfanumerické') }

    # Valid characters
    system = System.new(name: 'Alpha-Beta 123', x: 300, y: 300)
    system.valid?
    format_errors = system.errors[:name].select { |e| e.include?('alfanumerické') }
    assert_empty format_errors
  end

  test "System coordinates validation enforces 0-800 range" do
    system = System.new(name: "Test", x: -10, y: 300)
    assert_not system.valid?
    assert system.errors[:x].any?

    system = System.new(name: "Test", x: 850, y: 300)
    assert_not system.valid?
    assert system.errors[:x].any?

    system = System.new(name: "Test", x: 300, y: -10)
    assert_not system.valid?
    assert system.errors[:y].any?

    system = System.new(name: "Test", x: 300, y: 850)
    assert_not system.valid?
    assert system.errors[:y].any?
  end

  test "System validates coordinates are finite numbers" do
    system = System.new(name: "Test", x: Float::NAN, y: 300)
    assert_not system.valid?
    assert system.errors[:x].any? { |e| e.include?("platné číslo") }

    system = System.new(name: "Test", x: Float::INFINITY, y: 300)
    assert_not system.valid?
    assert system.errors[:x].any? { |e| e.include?("platné číslo") }

    system = System.new(name: "Test", x: 300, y: Float::NAN)
    assert_not system.valid?
    assert system.errors[:y].any? { |e| e.include?("platné číslo") }
  end

  test "Meeting participants JSON validation prevents non-array" do
    meeting = Meeting.new(
      start_time: '09:00',
      end_time: '10:00',
      participants: '{"key": "value"}'
    )

    assert_not meeting.valid?
    assert meeting.errors[:participants].any? { |e| e.include?("pole") || e.include?("array") }
  end

  test "Meeting participants JSON validation requires at least 2 participants" do
    meeting = Meeting.new(
      start_time: '09:00',
      end_time: '10:00',
      participants: '["Earth"]'
    )

    assert_not meeting.valid?
    assert meeting.errors[:participants].any? { |e| e.include?("2") }
  end

  test "Meeting participant_systems validation prevents nested objects" do
    meeting = Meeting.new(
      start_time: '09:00',
      end_time: '10:00',
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: '{"Earth": {"nested": "object"}, "Mars": 2}'
    )

    # The before_validation callback should reject nested objects
    meeting.valid?
    # participant_systems should be set to nil by security check
    assert_nil meeting.participant_systems
  end

  test "Meeting participant_systems validation enforces size limits" do
    # Create oversized participant_systems (> 50 entries)
    large_hash = {}
    60.times { |i| large_hash["Body#{i}"] = 1 }

    meeting = Meeting.new(
      start_time: '09:00',
      end_time: '10:00',
      participants: '["Body0", "Body1"]',
      is_inter_system: true,
      participant_systems: large_hash.to_json
    )

    assert_not meeting.valid?
    assert meeting.errors[:participant_systems].any? { |e| e.include?("příliš mnoho") }
  end

  test "Meeting participant_systems validation enforces bytesize limit" do
    # Create large JSON (> 10KB)
    large_hash = {}
    500.times { |i| large_hash["VeryLongBodyName#{i}" * 10] = 1 }

    meeting = Meeting.new(
      start_time: '09:00',
      end_time: '10:00',
      participants: '["Body0", "Body1"]',
      is_inter_system: true,
      participant_systems: large_hash.to_json
    )

    assert_not meeting.valid?
    assert meeting.errors[:participant_systems].any? { |e| e.include?("velký") || e.include?("10KB") }
  end

  # === Numeric Parameter Validation Tests ===

  test "validates num_planets parameter range (1-10)" do
    skip "Controller-level validation - test in controller test"
    # This would be tested in GalaxyController tests
  end

  test "validates max_moons parameter range (0-5)" do
    skip "Controller-level validation - test in controller test"
    # This would be tested in GalaxyController tests
  end

  test "validates custom body mass range" do
    skip "Generator-level validation - test in SystemGenerator test"
    # This would be tested in SystemGenerator tests
  end

  # === Strong Parameters Tests ===

  test "strong parameters prevent mass assignment in controllers" do
    skip "Controller-level test - verify in controller tests"
    # This would be integration tested through controller tests
  end

  # === Rate Limiting Tests ===

  test "rate limiting is configured via Rack::Attack" do
    # Check if Rack::Attack is configured
    if defined?(Rack::Attack)
      # Rack::Attack should be configured in config/initializers/rack_attack.rb
      assert File.exist?(Rails.root.join('config', 'initializers', 'rack_attack.rb'))
    else
      skip "Rack::Attack not configured"
    end
  end

  # === Content Security Policy Tests ===

  test "Content Security Policy is configured" do
    # Check if CSP is configured
    initializer_file = Rails.root.join('config', 'initializers', 'content_security_policy.rb')
    if File.exist?(initializer_file)
      content = File.read(initializer_file)
      # Should not be entirely commented out
      assert content.include?("policy."), "CSP should be configured"
    else
      skip "CSP initializer not found"
    end
  end

  # === Filter Parameter Logging Tests ===

  test "sensitive parameters are filtered from logs" do
    # Check filter_parameters configuration
    config = Rails.application.config.filter_parameters
    assert config.any?, "Should have filter parameters configured"
  end

  # === Security Event Logging Tests ===

  test "security violations are logged with IP and User-Agent" do
    # Test that security violations create log entries
    # This would require log capture and analysis
    skip "Requires log capture mechanism"
  end

  # === System Uniqueness Validation ===

  test "prevents duplicate system names" do
    system1 = System.new(name: "Duplicate", x: 200, y: 200, json_file_path: "data/systems/duplicate1.json")
    system1.save(validate: false)

    system2 = System.new(name: "Duplicate", x: 600, y: 600, json_file_path: "data/systems/duplicate2.json")
    assert_not system2.valid?
    assert system2.errors[:name].any? { |e| e.include?("existuje") }

    system1.destroy
  end

  # === Orbit Collision Detection ===

  test "prevents systems from colliding with each other" do
    # This is tested through OrbitValidator
    galaxy_data = {
      'black_hole' => { 'x' => 400, 'y' => 400 },
      'systems' => [{ 'id' => 'sys1', 'x' => 300, 'y' => 300 }]
    }

    # Try to place system too close to existing one
    result = OrbitValidator.validate_system_orbit(305, 305, galaxy_data)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("systém") }
  end

  test "prevents systems from being too close to black hole" do
    galaxy_data = {
      'black_hole' => { 'x' => 400, 'y' => 400 },
      'systems' => []
    }

    # Try to place system too close to black hole
    result = OrbitValidator.validate_system_orbit(405, 405, galaxy_data)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("černé díř") }
  end

  # === Sanitization Tests ===

  test "System name is normalized (whitespace stripped and squeezed)" do
    system = System.new(name: "  Test    System  ", x: 300, y: 300)
    system.valid? # Triggers before_validation
    assert_equal "Test System", system.name
  end

  test "SVG output escapes user-generated content" do
    # Test that galaxy/system SVG generation escapes names properly
    # This prevents XSS in SVG rendering
    skip "Requires SVG generation and parsing"
  end
end
