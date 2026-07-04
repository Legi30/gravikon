# frozen_string_literal: true

# Background job for regenerating an existing solar system
# Handles cleanup of old files, regeneration of system data and visualization
class RegenerateSystemJob < ApplicationJob
  queue_as :default

  # Retry on transient errors
  retry_on StandardError, wait: 5.seconds, attempts: 3 do |job, error|
    Rails.logger.error("RegenerateSystemJob: Retry attempt failed - #{error.class}: #{error.message}")
  end

  # Don't retry on validation errors
  discard_on ArgumentError do |job, error|
    Rails.logger.error("RegenerateSystemJob: Discarded due to invalid parameters - #{error.message}")
  end

  # Regenerate an existing solar system
  #
  # @param system_id [String, Integer] ID of the system to regenerate
  # @param num_planets [Integer] Number of planets (1-10)
  # @param max_moons [Integer] Maximum moons per planet (0-5)
  # @param custom_bodies [Array<Hash>] Optional custom body definitions
  def perform(system_id:, num_planets:, max_moons:, custom_bodies: nil)
    job_start_time = Time.current

    Rails.logger.info("=" * 80)
    Rails.logger.info("RegenerateSystemJob: Starting regeneration")
    Rails.logger.info("  System ID: #{system_id}")
    Rails.logger.info("  Parameters: #{num_planets} planets, #{max_moons} max moons")
    Rails.logger.info("  Custom bodies: #{custom_bodies ? 'Yes' : 'No'}")
    Rails.logger.info("=" * 80)

    # Load existing system to get position and name
    system = System.find(system_id)
    unless system
      raise ArgumentError, "System with ID #{system_id} not found"
    end

    system_name = system.name
    system_x = system.x
    system_y = system.y

    Rails.logger.info("RegenerateSystemJob: Found existing system '#{system_name}' at (#{system_x}, #{system_y})")

    # Validate parameters
    validate_parameters!(num_planets, max_moons)

    begin
      # 1. Backup old files (optional safety measure)
      backup_start = Time.current
      Rails.logger.info("RegenerateSystemJob: Step 1/6 - Backing up old files")

      backup_old_files(system_id)

      backup_duration = Time.current - backup_start
      Rails.logger.info("RegenerateSystemJob: Backup completed in #{backup_duration.round(2)}s")

      # 2. Generate new system data
      generator_start = Time.current
      Rails.logger.info("RegenerateSystemJob: Step 2/6 - Generating new system data")

      generator = SystemGenerator.new(
        system_id: system_id.to_s,
        system_name: system_name,
        system_x: system_x,
        system_y: system_y,
        num_planets: num_planets,
        max_moons_per_planet: max_moons,
        custom_bodies: custom_bodies
      )

      system_data = generator.generate

      unless system_data
        errors = generator.errors.join(', ')
        Rails.logger.error("RegenerateSystemJob: System generation failed - #{errors}")
        raise StandardError, "System generation failed: #{errors}"
      end

      generator_duration = Time.current - generator_start
      Rails.logger.info("RegenerateSystemJob: System data generated in #{generator_duration.round(2)}s")

      # 3. Save new system data
      save_start = Time.current
      Rails.logger.info("RegenerateSystemJob: Step 3/6 - Saving new system data")

      output_path = Rails.root.join('data', 'systems', "#{system_id}.json")
      File.write(output_path, JSON.pretty_generate(system_data))

      save_duration = Time.current - save_start
      Rails.logger.info("RegenerateSystemJob: Data saved in #{save_duration.round(2)}s")

      # 4. Regenerate visualization
      viz_start = Time.current
      Rails.logger.info("RegenerateSystemJob: Step 4/6 - Regenerating visualization")

      generate_system_visualization(system_id, system_data)

      viz_duration = Time.current - viz_start
      Rails.logger.info("RegenerateSystemJob: Visualization regenerated in #{viz_duration.round(2)}s")

      # 5. Update database record (if needed)
      db_start = Time.current
      Rails.logger.info("RegenerateSystemJob: Step 5/6 - Updating database record")

      system.touch # Update updated_at timestamp
      system.save!

      db_duration = Time.current - db_start
      Rails.logger.info("RegenerateSystemJob: Database updated in #{db_duration.round(2)}s")

      # 6. Clear caches
      cache_start = Time.current
      Rails.logger.info("RegenerateSystemJob: Step 6/6 - Clearing caches")

      clear_caches(system_id)

      cache_duration = Time.current - cache_start
      Rails.logger.info("RegenerateSystemJob: Caches cleared in #{cache_duration.round(2)}s")

      # Calculate total duration
      total_duration = Time.current - job_start_time

      # Log performance summary
      Rails.logger.info("=" * 80)
      Rails.logger.info("RegenerateSystemJob PERFORMANCE SUMMARY:")
      Rails.logger.info("  System: #{system_name} (#{system_id})")
      Rails.logger.info("  Parameters: #{num_planets} planets, #{max_moons} max moons")
      Rails.logger.info("  Backup time: #{backup_duration.round(2)}s")
      Rails.logger.info("  Generator time: #{generator_duration.round(2)}s")
      Rails.logger.info("  Save time: #{save_duration.round(2)}s")
      Rails.logger.info("  Visualizer time: #{viz_duration.round(2)}s")
      Rails.logger.info("  Database time: #{db_duration.round(2)}s")
      Rails.logger.info("  Cache time: #{cache_duration.round(2)}s")
      Rails.logger.info("  Total time: #{total_duration.round(2)}s")
      Rails.logger.info("  Status: SUCCESS ✓")

      if total_duration > 30
        Rails.logger.warn("  WARNING: Job exceeded 30s target (#{total_duration.round(2)}s)")
      else
        Rails.logger.info("  Performance: Within 30s target ✓")
      end
      Rails.logger.info("=" * 80)

      # Store metrics
      store_performance_metrics(system_id, num_planets, max_moons, {
        backup: backup_duration,
        generator: generator_duration,
        save: save_duration,
        visualizer: viz_duration,
        database: db_duration,
        cache: cache_duration,
        total: total_duration
      })

    rescue => e
      job_duration = Time.current - job_start_time
      Rails.logger.error("=" * 80)
      Rails.logger.error("RegenerateSystemJob: FAILED after #{job_duration.round(2)}s")
      Rails.logger.error("  Error: #{e.class}: #{e.message}")
      Rails.logger.error("  Backtrace: #{e.backtrace.first(10).join("\n  ")}")
      Rails.logger.error("=" * 80)
      raise
    end
  end

  private

  # Validate input parameters
  def validate_parameters!(num_planets, max_moons)
    num_planets_int = Integer(num_planets)
    unless num_planets_int.between?(1, 10)
      raise ArgumentError, "num_planets must be between 1 and 10, got #{num_planets_int}"
    end

    max_moons_int = Integer(max_moons)
    unless max_moons_int.between?(0, 5)
      raise ArgumentError, "max_moons must be between 0 and 5, got #{max_moons_int}"
    end

    Rails.logger.debug("RegenerateSystemJob: Parameters validated successfully")
  rescue ArgumentError, TypeError => e
    raise ArgumentError, "Invalid parameters: #{e.message}"
  end

  # Backup old system files
  def backup_old_files(system_id)
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

    # Backup JSON data file
    json_path = Rails.root.join('data', 'systems', "#{system_id}.json")
    if File.exist?(json_path)
      backup_json_path = Rails.root.join('data', 'systems', "#{system_id}_backup_#{timestamp}.json")
      FileUtils.cp(json_path, backup_json_path)
      Rails.logger.info("RegenerateSystemJob: Backed up JSON to #{backup_json_path}")
    end

    # Backup SVG file
    svg_path = Rails.root.join('public', 'systems', "#{system_id}.svg")
    if File.exist?(svg_path)
      backup_svg_path = Rails.root.join('public', 'systems', "#{system_id}_backup_#{timestamp}.svg")
      FileUtils.cp(svg_path, backup_svg_path)
      Rails.logger.info("RegenerateSystemJob: Backed up SVG to #{backup_svg_path}")
    end
  rescue => e
    Rails.logger.warn("RegenerateSystemJob: Backup failed (non-fatal) - #{e.message}")
    # Continue even if backup fails
  end

  # Generate SVG visualization for the system
  def generate_system_visualization(system_id, system_data)
    require_relative '../../lib/visualizer'

    # Use PlanetarySystem class method to generate and save SVG
    json_path = Rails.root.join('data', 'systems', "#{system_id}.json")
    output_path = Rails.root.join('public', 'systems', "#{system_id}.svg")

    FileUtils.mkdir_p(File.dirname(output_path))

    PlanetarySystem.generate(
      json_path: json_path,
      system_id: system_id,
      output_path: output_path
    )

    Rails.logger.info("RegenerateSystemJob: SVG saved to #{output_path}")
  rescue => e
    Rails.logger.error("RegenerateSystemJob: Visualization failed - #{e.message}")
    Rails.logger.warn("RegenerateSystemJob: Continuing despite visualization failure")
  end

  # Clear relevant caches
  def clear_caches(system_id)
    Rails.cache.delete('system_data') # Legacy cache
    Rails.cache.delete('galaxy_data')
    Rails.cache.delete("system_#{system_id}")
    Rails.cache.delete_matched("system_*")

    Rails.logger.info("RegenerateSystemJob: Caches cleared")
  rescue => e
    Rails.logger.error("RegenerateSystemJob: Cache clearing failed - #{e.message}")
  end

  # Store performance metrics
  def store_performance_metrics(system_id, num_planets, max_moons, durations)
    metrics = {
      timestamp: Time.current,
      system_id: system_id,
      num_planets: num_planets,
      max_moons: max_moons,
      backup_duration: durations[:backup].round(3),
      generator_duration: durations[:generator].round(3),
      save_duration: durations[:save].round(3),
      visualizer_duration: durations[:visualizer].round(3),
      database_duration: durations[:database].round(3),
      cache_duration: durations[:cache].round(3),
      total_duration: durations[:total].round(3),
      within_target: durations[:total] <= 30,
      job_type: 'regenerate'
    }

    history = Rails.cache.fetch('job_performance_history') { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write('job_performance_history', history)

    Rails.logger.debug("RegenerateSystemJob: Performance metrics stored")
  rescue => e
    Rails.logger.error("RegenerateSystemJob: Failed to store metrics - #{e.message}")
  end
end
