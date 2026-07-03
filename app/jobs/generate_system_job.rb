# frozen_string_literal: true

# Background job for generating a new solar system asynchronously
# Handles system data generation, visualization, database record creation,
# and galaxy data updates without blocking the web request
class GenerateSystemJob < ApplicationJob
  queue_as :default

  # Retry on transient errors (file system issues, etc.)
  retry_on StandardError, wait: 5.seconds, attempts: 3 do |job, error|
    Rails.logger.error("GenerateSystemJob: Retry attempt failed - #{error.class}: #{error.message}")
  end

  # Don't retry on validation errors (invalid parameters)
  discard_on ArgumentError do |job, error|
    Rails.logger.error("GenerateSystemJob: Discarded due to invalid parameters - #{error.message}")
  end

  # Generate a new solar system with full multi-system support
  #
  # @param system_id [String] Unique identifier for the system
  # @param system_name [String] Display name for the system
  # @param system_x [Float] X position in galaxy (100-700 recommended)
  # @param system_y [Float] Y position in galaxy (100-700 recommended)
  # @param num_planets [Integer] Number of planets (1-10)
  # @param max_moons [Integer] Maximum moons per planet (0-5)
  # @param custom_bodies [Array<Hash>] Optional custom body definitions
  def perform(system_id:, system_name:, system_x:, system_y:, num_planets:, max_moons:, custom_bodies: nil)
    job_start_time = Time.current

    Rails.logger.info("=" * 80)
    Rails.logger.info("GenerateSystemJob: Starting generation")
    Rails.logger.info("  System ID: #{system_id}")
    Rails.logger.info("  System Name: #{system_name}")
    Rails.logger.info("  Position: (#{system_x}, #{system_y})")
    Rails.logger.info("  Parameters: #{num_planets} planets, #{max_moons} max moons")
    Rails.logger.info("  Custom bodies: #{custom_bodies ? 'Yes' : 'No'}")
    Rails.logger.info("=" * 80)

    # Validate parameters
    validate_parameters!(num_planets, max_moons, system_x, system_y)

    begin
      # 1. Generate system data using SystemGenerator
      generator_start = Time.current
      Rails.logger.info("GenerateSystemJob: Step 1/5 - Generating system data")

      generator = SystemGenerator.new(
        system_id: system_id,
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
        Rails.logger.error("GenerateSystemJob: System generation failed - #{errors}")
        raise StandardError, "System generation failed: #{errors}"
      end

      generator_duration = Time.current - generator_start
      Rails.logger.info("GenerateSystemJob: System data generated in #{generator_duration.round(2)}s")

      # 2. Save system data to file
      save_start = Time.current
      Rails.logger.info("GenerateSystemJob: Step 2/5 - Saving system data to file")

      output_path = Rails.root.join('data', 'systems', "#{system_id}.json")
      FileUtils.mkdir_p(File.dirname(output_path))
      File.write(output_path, JSON.pretty_generate(system_data))

      save_duration = Time.current - save_start
      Rails.logger.info("GenerateSystemJob: Data saved to #{output_path} in #{save_duration.round(2)}s")

      # 3. Generate system visualization (SVG)
      viz_start = Time.current
      Rails.logger.info("GenerateSystemJob: Step 3/5 - Generating system visualization")

      generate_system_visualization(system_id, system_data)

      viz_duration = Time.current - viz_start
      Rails.logger.info("GenerateSystemJob: Visualization generated in #{viz_duration.round(2)}s")

      # 4. Update galaxy_data.json
      galaxy_start = Time.current
      Rails.logger.info("GenerateSystemJob: Step 4/5 - Updating galaxy data")

      success = GalaxyService.add_system(system_id, system_x, system_y)
      unless success
        Rails.logger.warn("GenerateSystemJob: Failed to add system to galaxy data (non-fatal)")
      end

      galaxy_duration = Time.current - galaxy_start
      Rails.logger.info("GenerateSystemJob: Galaxy data updated in #{galaxy_duration.round(2)}s")

      # 5. Find existing System database record (created by controller)
      db_start = Time.current
      Rails.logger.info("GenerateSystemJob: Step 5/5 - Finding database record")

      # Find system by json_file_path since system_id is UUID (not database ID)
      system = System.find_by(json_file_path: "data/systems/#{system_id}.json")

      unless system
        Rails.logger.warn("GenerateSystemJob: System record not found, creating new one")
        system = System.new(
          name: system_name,
          x: system_x,
          y: system_y,
          json_file_path: "data/systems/#{system_id}.json"
        )
        system.save!
      end

      db_duration = Time.current - db_start
      Rails.logger.info("GenerateSystemJob: Database record saved in #{db_duration.round(2)}s")

      # 6. Clear relevant caches
      Rails.logger.info("GenerateSystemJob: Clearing caches")
      clear_caches(system_id)

      # Calculate total job execution time
      total_duration = Time.current - job_start_time

      # Log performance summary
      Rails.logger.info("=" * 80)
      Rails.logger.info("GenerateSystemJob PERFORMANCE SUMMARY:")
      Rails.logger.info("  System: #{system_name} (#{system_id})")
      Rails.logger.info("  Position: (#{system_x}, #{system_y})")
      Rails.logger.info("  Parameters: #{num_planets} planets, #{max_moons} max moons")
      Rails.logger.info("  Generator time: #{generator_duration.round(2)}s")
      Rails.logger.info("  Save time: #{save_duration.round(2)}s")
      Rails.logger.info("  Visualizer time: #{viz_duration.round(2)}s")
      Rails.logger.info("  Galaxy update time: #{galaxy_duration.round(2)}s")
      Rails.logger.info("  Database time: #{db_duration.round(2)}s")
      Rails.logger.info("  Total time: #{total_duration.round(2)}s")
      Rails.logger.info("  Status: SUCCESS ✓")

      if total_duration > 30
        Rails.logger.warn("  WARNING: Job exceeded 30s target (#{total_duration.round(2)}s)")
      else
        Rails.logger.info("  Performance: Within 30s target ✓")
      end
      Rails.logger.info("=" * 80)

      # Store performance metrics
      store_performance_metrics(system_id, num_planets, max_moons, {
        generator: generator_duration,
        save: save_duration,
        visualizer: viz_duration,
        galaxy: galaxy_duration,
        database: db_duration,
        total: total_duration
      })

    rescue => e
      job_duration = Time.current - job_start_time
      Rails.logger.error("=" * 80)
      Rails.logger.error("GenerateSystemJob: FAILED after #{job_duration.round(2)}s")
      Rails.logger.error("  Error: #{e.class}: #{e.message}")
      Rails.logger.error("  Backtrace: #{e.backtrace.first(10).join("\n  ")}")
      Rails.logger.error("=" * 80)
      raise
    end
  end

  private

  # Validate input parameters
  def validate_parameters!(num_planets, max_moons, system_x, system_y)
    # Validate planet count
    num_planets_int = Integer(num_planets)
    unless num_planets_int.between?(1, 10)
      raise ArgumentError, "num_planets must be between 1 and 10, got #{num_planets_int}"
    end

    # Validate moon count
    max_moons_int = Integer(max_moons)
    unless max_moons_int.between?(0, 5)
      raise ArgumentError, "max_moons must be between 0 and 5, got #{max_moons_int}"
    end

    # Validate coordinates
    x_float = Float(system_x)
    y_float = Float(system_y)

    unless x_float.between?(0, 800) && y_float.between?(0, 800)
      raise ArgumentError, "Coordinates must be between 0 and 800, got (#{x_float}, #{y_float})"
    end

    Rails.logger.debug("GenerateSystemJob: Parameters validated successfully")
  rescue ArgumentError, TypeError => e
    raise ArgumentError, "Invalid parameters: #{e.message}"
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

    Rails.logger.info("GenerateSystemJob: SVG saved to #{output_path}")
  rescue => e
    Rails.logger.error("GenerateSystemJob: Visualization failed - #{e.message}")
    # Don't fail the entire job if visualization fails
    Rails.logger.warn("GenerateSystemJob: Continuing despite visualization failure")
  end

  # Clear relevant caches
  def clear_caches(system_id)
    Rails.cache.delete('system_data') # Legacy cache
    Rails.cache.delete('galaxy_data')
    Rails.cache.delete("system_#{system_id}")
    Rails.cache.delete_matched("system_*")

    Rails.logger.info("GenerateSystemJob: Caches cleared")
  rescue => e
    Rails.logger.error("GenerateSystemJob: Cache clearing failed - #{e.message}")
    # Don't fail the job if cache clearing fails
  end

  # Store performance metrics for monitoring
  def store_performance_metrics(system_id, num_planets, max_moons, durations)
    metrics = {
      timestamp: Time.current,
      system_id: system_id,
      num_planets: num_planets,
      max_moons: max_moons,
      generator_duration: durations[:generator].round(3),
      save_duration: durations[:save].round(3),
      visualizer_duration: durations[:visualizer].round(3),
      galaxy_duration: durations[:galaxy].round(3),
      database_duration: durations[:database].round(3),
      total_duration: durations[:total].round(3),
      within_target: durations[:total] <= 30,
      job_type: 'generate'
    }

    # Keep last 20 job executions
    history = Rails.cache.fetch('job_performance_history') { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write('job_performance_history', history)

    Rails.logger.debug("GenerateSystemJob: Performance metrics stored")
  rescue => e
    Rails.logger.error("GenerateSystemJob: Failed to store metrics - #{e.message}")
    # Don't fail the job if metrics storage fails
  end
end
