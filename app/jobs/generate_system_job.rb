# frozen_string_literal: true

# Background job for generating a new solar system asynchronously
# Handles system data generation, visualization, database record creation,
# and galaxy data updates without blocking the web request.
# All file locations come from GalaxyService; system_id here is the system's
# FILE id (UUID), not the database id.
class GenerateSystemJob < ApplicationJob
  queue_as :default

  # Generate a new solar system with full multi-system support
  #
  # @param system_id [String] Unique file identifier for the system (UUID)
  # @param system_name [String] Display name for the system
  # @param system_x [Float] X position in galaxy (100-700 recommended)
  # @param system_y [Float] Y position in galaxy (100-700 recommended)
  # @param num_planets [Integer] Number of planets (1-10)
  # @param max_moons [Integer] Maximum moons per planet (0-5)
  # @param custom_bodies [Array<Hash>] Optional custom body definitions
  def perform(system_id:, system_name:, system_x:, system_y:, num_planets:, max_moons:, custom_bodies: nil)
    job_start_time = Time.current

    Rails.logger.info("GenerateSystemJob: Generating '#{system_name}' (#{system_id}) at (#{system_x}, #{system_y}) with #{num_planets} planets, #{max_moons} max moons")

    validate_parameters!(num_planets, max_moons, system_x, system_y)

    # 1. Generate system data using SystemGenerator
    generator_start = Time.current
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
      raise StandardError, "System generation failed: #{generator.errors.join(', ')}"
    end
    generator_duration = Time.current - generator_start

    # 2. Save system data to file
    output_path = GalaxyService.system_data_path(system_id)
    raise ArgumentError, "Invalid system_id: #{system_id}" unless output_path

    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, JSON.pretty_generate(system_data))
    Rails.logger.info("GenerateSystemJob: Data saved to #{output_path}")

    # 3. Generate system visualization (SVG)
    viz_start = Time.current
    generate_system_visualization(system_id)
    viz_duration = Time.current - viz_start

    # 4. Update galaxy_data.json
    unless GalaxyService.add_system(system_id, system_x, system_y)
      Rails.logger.warn("GenerateSystemJob: Failed to add system to galaxy data (non-fatal)")
    end

    # 5. Find existing System database record (created by controller)
    system = System.find_by(json_file_path: "data/systems/#{system_id}.json")
    unless system
      Rails.logger.warn("GenerateSystemJob: System record not found, creating new one")
      system = System.create!(
        name: system_name,
        x: system_x,
        y: system_y,
        json_file_path: "data/systems/#{system_id}.json"
      )
    end

    # 6. Refresh caches
    GalaxyService.clear_system_cache(system_id)
    GalaxyService.clear_galaxy_cache
    GalaxyService.invalidate_used_names_cache
    GalaxyService.update_svg_timestamp(:system, system_id: system_id)

    total_duration = Time.current - job_start_time
    Rails.logger.info("GenerateSystemJob: '#{system_name}' generated in #{total_duration.round(2)}s (generator #{generator_duration.round(2)}s, visualizer #{viz_duration.round(2)}s)")

    store_performance_metrics(system_id, num_planets, max_moons, {
      generator: generator_duration,
      visualizer: viz_duration,
      total: total_duration
    })
  rescue => e
    Rails.logger.error("GenerateSystemJob FAILED for #{system_name} (#{system_id}): #{e.class}: #{e.message}")
    raise
  end

  private

  # Validate input parameters
  def validate_parameters!(num_planets, max_moons, system_x, system_y)
    # Validate planet count (Integer() truncates floats, so reject those explicitly)
    num_planets_int = Integer(num_planets)
    if num_planets.is_a?(Numeric) && num_planets != num_planets_int
      raise ArgumentError, "num_planets must be an integer, got #{num_planets}"
    end
    unless num_planets_int.between?(1, 10)
      raise ArgumentError, "num_planets must be between 1 and 10, got #{num_planets_int}"
    end

    # Validate moon count
    max_moons_int = Integer(max_moons)
    if max_moons.is_a?(Numeric) && max_moons != max_moons_int
      raise ArgumentError, "max_moons must be an integer, got #{max_moons}"
    end
    unless max_moons_int.between?(0, 5)
      raise ArgumentError, "max_moons must be between 0 and 5, got #{max_moons_int}"
    end

    # Validate coordinates
    x_float = Float(system_x)
    y_float = Float(system_y)

    unless x_float.between?(0, 800) && y_float.between?(0, 800)
      raise ArgumentError, "Coordinates must be between 0 and 800, got (#{x_float}, #{y_float})"
    end
  rescue TypeError => e
    raise ArgumentError, "Invalid parameters: #{e.message}"
  end

  # Generate SVG visualization for the system
  def generate_system_visualization(system_id)
    json_path = GalaxyService.system_data_path(system_id)
    output_path = GalaxyService.system_svg_path(system_id)

    FileUtils.mkdir_p(File.dirname(output_path))

    PlanetarySystem.generate(
      json_path: json_path,
      system_id: system_id,
      output_path: output_path
    )

    Rails.logger.info("GenerateSystemJob: SVG saved to #{output_path}")
  end

  # Store performance metrics for monitoring
  def store_performance_metrics(system_id, num_planets, max_moons, durations)
    metrics = {
      timestamp: Time.current,
      system_id: system_id,
      num_planets: num_planets,
      max_moons: max_moons,
      generator_duration: durations[:generator].round(3),
      visualizer_duration: durations[:visualizer].round(3),
      total_duration: durations[:total].round(3),
      within_target: durations[:total] <= 30,
      job_type: "generate"
    }

    # Keep last 20 job executions
    history = Rails.cache.fetch("job_performance_history") { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write("job_performance_history", history)
  rescue => e
    Rails.logger.error("GenerateSystemJob: Failed to store metrics - #{e.message}")
    # Don't fail the job if metrics storage fails
  end
end
