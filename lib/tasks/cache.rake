# frozen_string_literal: true

namespace :cache do
  desc "Clear all system-related caches"
  task clear_systems: :environment do
    puts "Clearing all system-related caches..."

    begin
      # Clear galaxy cache (data, SVG timestamp and legacy key)
      GalaxyService.clear_galaxy_cache
      puts "  ✓ Galaxy cache cleared"

      # Clear per-system caches (data, meeting stats, SVG timestamps)
      # and the used names cache
      GalaxyService.clear_all_system_caches
      puts "  ✓ System data caches cleared"

      # Clear legacy system_data cache
      Rails.cache.delete("system_data")
      puts "  ✓ Legacy system_data cache cleared"

      puts "\n✓ All system-related caches cleared successfully!"
    rescue => e
      puts "\n✗ Error clearing caches: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Clear cache for a specific system"
  task :clear_system, [ :system_id ] => :environment do |_t, args|
    system_id = args[:system_id]

    if system_id.blank?
      puts "Error: Please provide a system_id"
      puts "Usage: rails cache:clear_system[system_id]"
      exit 1
    end

    puts "Clearing cache for system: #{system_id}..."

    begin
      GalaxyService.clear_system_cache(system_id)
      puts "  ✓ System data cache cleared"

      GalaxyService.invalidate_system_meeting_stats(system_id)
      puts "  ✓ Meeting stats cache cleared"

      # Clear SVG timestamp
      Rails.cache.delete("system_#{system_id}_svg_timestamp")
      puts "  ✓ SVG timestamp cleared"

      puts "\n✓ Cache cleared successfully for system: #{system_id}"
    rescue => e
      puts "\n✗ Error clearing system cache: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Clear galaxy cache only"
  task clear_galaxy: :environment do
    puts "Clearing galaxy cache..."

    begin
      GalaxyService.clear_galaxy_cache
      puts "  ✓ Galaxy cache cleared"

      Rails.cache.delete("galaxy_svg_timestamp")
      puts "  ✓ Galaxy SVG timestamp cleared"

      puts "\n✓ Galaxy cache cleared successfully!"
    rescue => e
      puts "\n✗ Error clearing galaxy cache: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Clear all meeting statistics caches"
  task clear_meeting_stats: :environment do
    puts "Clearing all meeting statistics caches..."

    begin
      # Solid Cache doesn't support delete_matched — enumerate exact keys.
      # Meeting stats are cached under both id kinds (DB id and file id).
      System.find_each do |system|
        GalaxyService.invalidate_system_meeting_stats(system.id)
        GalaxyService.invalidate_system_meeting_stats(system.system_id)
      end
      puts "  ✓ Meeting statistics caches cleared"

      puts "\n✓ All meeting statistics caches cleared successfully!"
    rescue => e
      puts "\n✗ Error clearing meeting stats caches: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Show cache statistics for systems"
  task stats_systems: :environment do
    puts "System Cache Statistics"
    puts "=" * 60

    begin
      # Get all systems
      systems = System.all

      puts "\nTotal systems: #{systems.count}"
      puts "\nCache keys:"

      # Check galaxy cache
      galaxy_key = "galaxy_data_#{GalaxyService::CACHE_VERSION}"
      galaxy_cached = Rails.cache.exist?(galaxy_key)
      puts "  Galaxy data (#{galaxy_key}): #{galaxy_cached ? '✓ CACHED' : '✗ NOT CACHED'}"

      # Check each system
      systems.each do |system|
        system_file_id = File.basename(system.json_file_path, ".json")
        system_key = "system_data_#{system_file_id}_#{GalaxyService::CACHE_VERSION}"
        stats_key = "system_#{system_file_id}_meeting_stats_#{GalaxyService::CACHE_VERSION}"
        svg_key = "system_#{system_file_id}_svg_timestamp"

        puts "\n  System: #{system.name} (#{system_file_id})"
        puts "    Data: #{Rails.cache.exist?(system_key) ? '✓ CACHED' : '✗ NOT CACHED'}"
        puts "    Stats: #{Rails.cache.exist?(stats_key) ? '✓ CACHED' : '✗ NOT CACHED'}"
        puts "    SVG timestamp: #{Rails.cache.exist?(svg_key) ? '✓ CACHED' : '✗ NOT CACHED'}"
      end

      # Check other caches
      puts "\nOther caches:"
      puts "  Used celestial names: #{Rails.cache.exist?('used_celestial_names') ? '✓ CACHED' : '✗ NOT CACHED'}"
      puts "  Galaxy SVG timestamp: #{Rails.cache.exist?('galaxy_svg_timestamp') ? '✓ CACHED' : '✗ NOT CACHED'}"

      puts "\n" + "=" * 60
    rescue => e
      puts "\n✗ Error getting cache statistics: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end

  desc "Warm up system caches (preload frequently accessed data)"
  task warm: :environment do
    puts "Warming up system caches..."

    begin
      # Load galaxy data (triggers caching)
      galaxy_data = GalaxyService.load_galaxy_data
      puts "  ✓ Galaxy data loaded (#{galaxy_data['systems']&.count || 0} systems)"

      # Load each system's data
      System.find_each do |system|
        system_file_id = File.basename(system.json_file_path, ".json")
        system_data = GalaxyService.load_system_data(system_file_id)
        if system_data
          body_count = system_data["bodies"]&.count || 0
          puts "  ✓ System '#{system.name}' loaded (#{body_count} bodies)"
        else
          puts "  ✗ System '#{system.name}' - no data file"
        end
      end

      # Load used celestial names
      used_names = GalaxyService.get_used_celestial_names
      puts "  ✓ Used celestial names loaded (#{used_names.count} names)"

      # Load meeting stats for each system
      System.find_each do |system|
        stats = GalaxyService.get_system_meeting_stats(system.id)
        puts "  ✓ Meeting stats for '#{system.name}' loaded (#{stats[:total_meetings]} meetings)"
      end

      puts "\n✓ Cache warming completed successfully!"
    rescue => e
      puts "\n✗ Error warming caches: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end
end
