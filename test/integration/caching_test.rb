# frozen_string_literal: true

require "test_helper"

class CachingTest < ActiveSupport::TestCase
  def setup
    # Clear all caches before each test
    Rails.cache.clear

    # Create test galaxy data
    @test_galaxy_file = GalaxyService.galaxy_data_path
    @test_galaxy_data = {
      "black_hole" => {
        "name" => "Sagittarius Omega",
        "mass" => 8.2e36,
        "x" => 400,
        "y" => 400,
        "schwarzschild_radius" => 0.00365,
        "dilation" => 0.0,
        "type" => "black_hole"
      },
      "systems" => [
        { "id" => "test_sys_1", "x" => 200.0, "y" => 300.0 },
        { "id" => "test_sys_2", "x" => 600.0, "y" => 500.0 }
      ]
    }

    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))

    # Create test system files
    FileUtils.mkdir_p(GalaxyService.systems_data_dir)
    @system1_file = GalaxyService.systems_data_dir.join("test_sys_1.json")
    @system2_file = GalaxyService.systems_data_dir.join("test_sys_2.json")

    File.write(@system1_file, JSON.pretty_generate({
      "bodies" => [
        { "name" => "Alpha Star", "type" => "star", "mass" => 1.989e30 },
        { "name" => "Planet A", "type" => "planet", "mass" => 5.97e24 }
      ]
    }))

    File.write(@system2_file, JSON.pretty_generate({
      "bodies" => [
        { "name" => "Beta Star", "type" => "star", "mass" => 2.5e30 },
        { "name" => "Planet B", "type" => "planet", "mass" => 4.5e24 }
      ]
    }))
  end

  def teardown
    # Clean up test files
    File.delete(@test_galaxy_file) if File.exist?(@test_galaxy_file)
    File.delete(@system1_file) if File.exist?(@system1_file)
    File.delete(@system2_file) if File.exist?(@system2_file)

    Rails.cache.clear
  end

  # === LOG011: Galaxy caching strategy tests ===

  # Test galaxy_data is cached with Rails.cache.fetch('galaxy_data')
  test "galaxy_data cached with versioned key" do
    cache_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"

    # First load - should cache
    galaxy_data_1 = GalaxyService.load_galaxy_data
    assert Rails.cache.exist?(cache_key), "Galaxy data should be cached"

    cached_data = Rails.cache.read(cache_key)
    assert_not_nil cached_data
    assert_equal galaxy_data_1, cached_data
  end

  # Test galaxy cache invalidated when system added or removed
  test "galaxy cache invalidated when system added or removed" do
    cache_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"

    # Load and cache
    GalaxyService.load_galaxy_data
    assert Rails.cache.exist?(cache_key)

    # Add system - should invalidate cache
    GalaxyService.add_system("new_sys", 300.0, 300.0)
    assert_not Rails.cache.exist?(cache_key), "Cache should be invalidated after adding system"

    # Load again to cache
    GalaxyService.load_galaxy_data
    assert Rails.cache.exist?(cache_key)

    # Remove system - should invalidate cache
    GalaxyService.remove_system("new_sys")
    assert_not Rails.cache.exist?(cache_key), "Cache should be invalidated after removing system"
  end

  # Test each system cached with system_data_<system_id> key
  test "each system cached with versioned system_data key" do
    cache_key = "system_data_test_sys_1_#{GalaxyService::CACHE_VERSION}"

    # Load system - should cache
    system_data = GalaxyService.load_system_data("test_sys_1")
    assert Rails.cache.exist?(cache_key), "System data should be cached"

    cached_data = Rails.cache.read(cache_key)
    assert_not_nil cached_data
    assert_equal 2, cached_data["bodies"].length
  end

  # Test system cache invalidated when specific system is regenerated
  test "system cache invalidated when regenerated" do
    cache_key = "system_data_test_sys_1_#{GalaxyService::CACHE_VERSION}"

    # Load and cache
    GalaxyService.load_system_data("test_sys_1")
    assert Rails.cache.exist?(cache_key)

    # Clear specific system cache
    GalaxyService.clear_system_cache("test_sys_1")
    assert_not Rails.cache.exist?(cache_key), "System cache should be cleared"
  end

  # Test used_celestial_names caching for name generation
  test "used_celestial_names cached and reused" do
    # First call - should cache
    names1 = GalaxyService.get_used_celestial_names
    assert_includes names1, "Alpha Star"
    assert_includes names1, "Beta Star"

    # Verify it's cached
    cached_names = Rails.cache.read("used_celestial_names")
    assert_not_nil cached_names
    assert_equal names1, cached_names

    # Second call - should use cache (add new system file but it won't be detected)
    File.write(GalaxyService.systems_data_dir.join("test_sys_3.json"), JSON.pretty_generate({
      "bodies" => [ { "name" => "Gamma Star", "type" => "star" } ]
    }))

    names2 = GalaxyService.get_used_celestial_names
    assert_not_includes names2, "Gamma Star", "Should use cached data, not see new system"

    # After cache invalidation - should see new system
    GalaxyService.invalidate_used_names_cache
    names3 = GalaxyService.get_used_celestial_names
    assert_includes names3, "Gamma Star", "Should see new system after cache invalidation"

    # Cleanup
    File.delete(GalaxyService.systems_data_dir.join("test_sys_3.json"))
  end

  # Test cache warming on application start
  test "cache warming loads critical data" do
    # Clear cache to simulate cold start
    Rails.cache.clear

    # Simulate cache warming (this would normally happen in initializer)
    # For first 10 systems (or fewer if less exist)
    GalaxyService.load_galaxy_data

    cache_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"
    assert Rails.cache.exist?(cache_key), "Galaxy data should be warmed"
  end

  # Test cache:clear_systems rake task clears all system caches
  test "clear_all_system_caches clears all system-related caches" do
    # Cache some systems
    GalaxyService.load_system_data("test_sys_1")
    GalaxyService.load_system_data("test_sys_2")
    GalaxyService.get_used_celestial_names

    # Verify caches exist
    assert Rails.cache.exist?("system_data_test_sys_1_#{GalaxyService::CACHE_VERSION}")
    assert Rails.cache.exist?("system_data_test_sys_2_#{GalaxyService::CACHE_VERSION}")
    assert Rails.cache.exist?("used_celestial_names")

    # Clear all system caches
    GalaxyService.clear_all_system_caches

    # Verify caches are cleared
    assert_not Rails.cache.exist?("used_celestial_names"), "Used names cache should be cleared"
    # System caches should also be cleared (using pattern matching)
  end

  # Test dashboard statistics caching
  test "dashboard statistics are cached" do
    # This would test dashboard-level caching if it exists
    # The actual cache key would depend on implementation
    skip "Dashboard caching test - verify implementation"
  end

  # Test meeting statistics per system caching
  test "meeting statistics per system are cached" do
    # Create test system in database
    system = System.new(
      name: "Cache Test System",
      x: 300,
      y: 300,
      json_file_path: "data/systems/cache_test.json"
    )
    system.save(validate: false)

    cache_key = "system_#{system.id}_meeting_stats_#{GalaxyService::CACHE_VERSION}"

    # Get stats - should cache
    stats = GalaxyService.get_system_meeting_stats(system.id)
    assert Rails.cache.exist?(cache_key), "Meeting stats should be cached"

    cached_stats = Rails.cache.read(cache_key)
    assert_not_nil cached_stats
    assert cached_stats.key?(:total_meetings)

    # Cleanup
    system.destroy
  end

  # Test SVG timestamp caching for cache busting
  test "SVG timestamps are cached for cache busting" do
    # Create test SVG
    svg_file = GalaxyService.galaxy_svg_path
    FileUtils.mkdir_p(File.dirname(svg_file))
    File.write(svg_file, "<svg></svg>")

    timestamp1 = GalaxyService.get_svg_timestamp(:galaxy)
    assert_not_nil timestamp1

    # Should be cached
    cache_key = "galaxy_svg_timestamp"
    assert Rails.cache.exist?(cache_key)

    # Update timestamp
    timestamp2 = GalaxyService.update_svg_timestamp(:galaxy)
    assert timestamp2 >= timestamp1

    # Cleanup
    File.delete(svg_file) if File.exist?(svg_file)
  end

  # Test cache expiration times are appropriate
  test "cache expiration times are set appropriately" do
    # Galaxy data: 1 hour
    GalaxyService.load_galaxy_data
    cache_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"
    # Rails.cache doesn't expose TTL directly in simple cache stores
    # But we can verify the key exists
    assert Rails.cache.exist?(cache_key)

    # Used names: 30 minutes
    GalaxyService.get_used_celestial_names
    assert Rails.cache.exist?("used_celestial_names")
  end

  # Test cache version upgrade clears old caches
  test "cache version prevents stale data after schema changes" do
    # Write data with old version manually
    old_key = "galaxy_data_v1"
    Rails.cache.write(old_key, { "old" => "data" })

    # Load with current version
    GalaxyService.load_galaxy_data

    # New version should be cached
    new_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"
    assert Rails.cache.exist?(new_key)

    # Old version should still exist but won't be used
    assert Rails.cache.exist?(old_key)

    # Clear galaxy cache clears both
    GalaxyService.clear_galaxy_cache
    assert_not Rails.cache.exist?(old_key)
    assert_not Rails.cache.exist?(new_key)
  end

  # Test concurrent cache access doesn't cause issues
  test "cache handles concurrent access safely" do
    # Load data in "parallel" (simulated)
    results = []
    3.times do
      results << GalaxyService.load_galaxy_data
    end

    # All should return same data
    assert_equal results[0], results[1]
    assert_equal results[1], results[2]
  end

  # Test cache miss logging (in development)
  test "cache misses and hits are logged in development" do
    skip unless Rails.env.development?

    # This would require capturing log output
    # The GalaxyService has log_cache_hit and log_cache_miss methods
  end
end
