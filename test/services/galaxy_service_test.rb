# frozen_string_literal: true

require "test_helper"

class GalaxyServiceTest < ActiveSupport::TestCase
  setup do
    @test_galaxy_file = Rails.root.join('data', 'galaxy_data.json')
    @backup_file = Rails.root.join('data', 'galaxy_data.json.backup')

    # Backup existing galaxy data if it exists
    if File.exist?(@test_galaxy_file)
      FileUtils.cp(@test_galaxy_file, @backup_file)
    end

    # Create test galaxy data
    @test_galaxy_data = {
      'black_hole' => {
        'name' => 'Sagittarius Omega',
        'mass' => 8.2e36,
        'x' => 400,
        'y' => 400,
        'type' => 'black_hole'
      },
      'systems' => [
        { 'id' => 'test_system_1', 'x' => 300.0, 'y' => 300.0 },
        { 'id' => 'test_system_2', 'x' => 500.0, 'y' => 500.0 }
      ]
    }

    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))

    # Clear cache before each test
    Rails.cache.clear
  end

  teardown do
    # Restore backup or delete test file
    if File.exist?(@backup_file)
      FileUtils.mv(@backup_file, @test_galaxy_file)
    elsif File.exist?(@test_galaxy_file)
      File.delete(@test_galaxy_file)
    end

    Rails.cache.clear
  end

  # Test load_galaxy_data reads and parses galaxy_data.json correctly
  test "load_galaxy_data reads and parses galaxy_data.json correctly" do
    data = GalaxyService.load_galaxy_data

    assert_not_nil data
    assert_equal 'Sagittarius Omega', data['black_hole']['name']
    assert_equal 400, data['black_hole']['x']
    assert_equal 400, data['black_hole']['y']
    assert_equal 2, data['systems'].length
    assert_equal 'test_system_1', data['systems'][0]['id']
    assert_equal 300.0, data['systems'][0]['x']
  end

  # Test load_galaxy_data caches result with Rails.cache.fetch
  test "load_galaxy_data caches result with Rails.cache.fetch" do
    # First call should hit the file
    data1 = GalaxyService.load_galaxy_data
    assert_not_nil data1

    # Modify the file
    modified_data = @test_galaxy_data.dup
    modified_data['black_hole']['name'] = 'Modified Name'
    File.write(@test_galaxy_file, JSON.pretty_generate(modified_data))

    # Second call should return cached data (not modified data)
    data2 = GalaxyService.load_galaxy_data
    assert_equal 'Sagittarius Omega', data2['black_hole']['name']
    assert_not_equal 'Modified Name', data2['black_hole']['name']
  end

  # Test add_system updates galaxy_data.json with new system reference
  test "add_system updates galaxy_data.json with new system reference" do
    result = GalaxyService.add_system('new_system', 600.0, 300.0)
    assert result, "add_system should return true"

    # Re-read file to verify it was updated
    data = JSON.parse(File.read(@test_galaxy_file))
    new_system = data['systems'].find { |s| s['id'] == 'new_system' }

    assert_not_nil new_system
    assert_equal 600.0, new_system['x']
    assert_equal 300.0, new_system['y']
  end

  # Test add_system invalidates galaxy_data cache
  test "add_system invalidates galaxy_data cache" do
    # Load and cache galaxy data
    GalaxyService.load_galaxy_data

    # Add new system
    GalaxyService.add_system('new_system', 600.0, 300.0)

    # Load again - should reflect the new system
    data = GalaxyService.load_galaxy_data
    new_system = data['systems'].find { |s| s['id'] == 'new_system' }
    assert_not_nil new_system, "Cache should be invalidated and new system should be visible"
  end

  # Test remove_system removes system from galaxy_data.json systems array
  test "remove_system removes system from galaxy_data.json systems array" do
    result = GalaxyService.remove_system('test_system_1')
    assert result, "remove_system should return true"

    # Re-read file to verify removal
    data = JSON.parse(File.read(@test_galaxy_file))
    removed_system = data['systems'].find { |s| s['id'] == 'test_system_1' }

    assert_nil removed_system
    assert_equal 1, data['systems'].length
  end

  # Test remove_system invalidates galaxy_data cache
  test "remove_system invalidates galaxy_data cache" do
    # Load and cache galaxy data
    GalaxyService.load_galaxy_data

    # Remove system
    GalaxyService.remove_system('test_system_1')

    # Load again - should reflect the removal
    data = GalaxyService.load_galaxy_data
    removed_system = data['systems'].find { |s| s['id'] == 'test_system_1' }
    assert_nil removed_system, "Cache should be invalidated and system should be removed"
  end

  # Test validate_system_position rejects coordinates outside 0-800 canvas
  test "validate_system_position rejects coordinates outside canvas" do
    result = GalaxyService.validate_system_position(-10, 300)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("canvas") || e.include?("0") }

    result = GalaxyService.validate_system_position(850, 300)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("canvas") || e.include?("800") }
  end

  # Test validate_system_position enforces minimum distance from black hole
  test "validate_system_position enforces minimum distance from black hole" do
    # Position too close to black hole at (400, 400)
    result = GalaxyService.validate_system_position(410, 410)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("černé díry") || e.include?("black hole") || e.include?("blízko") }
  end

  # Test validate_system_position detects collisions with existing systems
  test "validate_system_position detects collisions with existing systems" do
    # Position too close to test_system_1 at (300, 300)
    result = GalaxyService.validate_system_position(310, 310)
    assert_not result[:valid]
    assert result[:errors].any? { |e| e.include?("kolize") || e.include?("blízko") || e.include?("collision") }
  end

  # Test validate_system_position accepts valid position
  test "validate_system_position accepts valid position" do
    # Position far from black hole and other systems
    result = GalaxyService.validate_system_position(200, 200)
    assert result[:valid], "Valid position should be accepted: #{result[:errors]}"
    assert_empty result[:errors]
  end

  # Test handles missing or corrupt galaxy_data.json gracefully
  test "handles missing galaxy_data.json gracefully" do
    # Delete the file
    File.delete(@test_galaxy_file)
    Rails.cache.clear

    # Should not crash and should return default structure
    data = GalaxyService.load_galaxy_data
    assert_not_nil data
    assert_not_nil data['black_hole']
    assert_not_nil data['systems']
  end

  test "handles corrupt galaxy_data.json gracefully" do
    # Write invalid JSON
    File.write(@test_galaxy_file, "{ invalid json }")
    Rails.cache.clear

    # Should not crash and should return default structure
    data = GalaxyService.load_galaxy_data
    assert_not_nil data
    assert_not_nil data['black_hole']
    assert_not_nil data['systems']
  end

  # Test add_system updates existing system position
  test "add_system updates existing system position if already present" do
    # Add system at one position
    GalaxyService.add_system('movable_system', 200.0, 200.0)

    # Move it to another position
    result = GalaxyService.add_system('movable_system', 250.0, 250.0)
    assert result

    # Verify position was updated
    data = JSON.parse(File.read(@test_galaxy_file))
    system = data['systems'].find { |s| s['id'] == 'movable_system' }
    assert_equal 250.0, system['x']
    assert_equal 250.0, system['y']

    # Should only have one entry for this system
    matching_systems = data['systems'].select { |s| s['id'] == 'movable_system' }
    assert_equal 1, matching_systems.length
  end

  # Test validate_system_position allows excluding specific system from collision check
  test "validate_system_position with exclude_system_id option" do
    # Position at test_system_1's location should fail normally
    result = GalaxyService.validate_system_position(300, 300)
    assert_not result[:valid]

    # But should succeed when excluding test_system_1
    result = GalaxyService.validate_system_position(300, 300, exclude_system_id: 'test_system_1')
    assert result[:valid], "Should be valid when excluding self: #{result[:errors]}"
  end

  # Test cache version is used in cache keys
  test "uses cache version in cache keys" do
    # Access cache key through the service
    data1 = GalaxyService.load_galaxy_data
    assert_not_nil data1

    # Cache should have the versioned key
    cache_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"
    cached_data = Rails.cache.read(cache_key)
    assert_not_nil cached_data, "Cache should contain versioned key"
  end

  # Test clear caches methods
  test "clear_galaxy_cache clears galaxy data cache" do
    # Load and cache data
    GalaxyService.load_galaxy_data
    cache_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"
    assert_not_nil Rails.cache.read(cache_key)

    # Clear cache
    GalaxyService.clear_galaxy_cache

    # Should be cleared
    assert_nil Rails.cache.read(cache_key)
  end
end
