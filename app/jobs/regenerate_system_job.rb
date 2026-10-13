# frozen_string_literal: true

# Background job for regenerating an existing solar system
# Regenerates system data + visualization, refreshes galaxy data and caches.
# All file locations come from GalaxyService and use the system's file id
# (the UUID/slug in json_file_path), never the database id.
class RegenerateSystemJob < ApplicationJob
  queue_as :default

  # Regenerate an existing solar system
  #
  # @param system_id [String, Integer] Database ID of the system to regenerate
  # @param num_planets [Integer] Number of planets (1-10)
  # @param max_moons [Integer] Maximum moons per planet (0-5)
  # @param custom_bodies [Array<Hash>] Optional custom body definitions
  def perform(system_id:, num_planets:, max_moons:, custom_bodies: nil)
    job_start_time = Time.current

    system = System.find(system_id)
    file_id = system.system_id
    raise ArgumentError, "System #{system_id} has no valid file id (json_file_path: #{system.json_file_path})" if file_id.blank?

    Rails.logger.info("RegenerateSystemJob: Regenerating '#{system.name}' (#{file_id}) at (#{system.x}, #{system.y}) with #{num_planets} planets, #{max_moons} max moons")

    validate_parameters!(num_planets, max_moons)

    # 1. Generate new system data
    generator_start = Time.current
    generator = SystemGenerator.new(
      system_id: file_id,
      system_name: system.name,
      system_x: system.x,
      system_y: system.y,
      num_planets: num_planets,
      max_moons_per_planet: max_moons,
      custom_bodies: custom_bodies,
      # A binary stays a binary when its planets are regenerated
      binary: system.binary?
    )

    system_data = generator.generate
    unless system_data
      raise StandardError, "System generation failed: #{generator.errors.join(', ')}"
    end
    generator_duration = Time.current - generator_start

    # 2. Save new system data
    output_path = GalaxyService.system_data_path(file_id)
    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, JSON.pretty_generate(system_data))
    Rails.logger.info("RegenerateSystemJob: Data saved to #{output_path}")

    # 3. Regenerate visualization
    viz_start = Time.current
    generate_system_visualization(file_id)
    viz_duration = Time.current - viz_start

    # 4. Ensure galaxy data has this system's entry (self-heals a missing file)
    GalaxyService.add_system(file_id, system.x, system.y)

    # 5. Touch database record
    system.touch

    # 6. Refresh caches
    GalaxyService.clear_system_cache(file_id)
    GalaxyService.clear_galaxy_cache
    GalaxyService.invalidate_used_names_cache
    GalaxyService.update_svg_timestamp(:system, system_id: file_id)

    total_duration = Time.current - job_start_time
    Rails.logger.info("RegenerateSystemJob: '#{system.name}' regenerated in #{total_duration.round(2)}s (generator #{generator_duration.round(2)}s, visualizer #{viz_duration.round(2)}s)")

    store_performance_metrics(file_id, num_planets, max_moons, {
      generator: generator_duration,
      visualizer: viz_duration,
      total: total_duration
    })
  rescue => e
    Rails.logger.error("RegenerateSystemJob FAILED for system #{system_id}: #{e.class}: #{e.message}")
    raise
  end

  private

  # Validate input parameters
  def validate_parameters!(num_planets, max_moons)
    # Integer() truncates floats, so reject those explicitly
    num_planets_int = Integer(num_planets)
    if num_planets.is_a?(Numeric) && num_planets != num_planets_int
      raise ArgumentError, "num_planets must be an integer, got #{num_planets}"
    end
    unless num_planets_int.between?(1, 10)
      raise ArgumentError, "num_planets must be between 1 and 10, got #{num_planets_int}"
    end

    max_moons_int = Integer(max_moons)
    if max_moons.is_a?(Numeric) && max_moons != max_moons_int
      raise ArgumentError, "max_moons must be an integer, got #{max_moons}"
    end
    unless max_moons_int.between?(0, 5)
      raise ArgumentError, "max_moons must be between 0 and 5, got #{max_moons_int}"
    end
  rescue TypeError => e
    raise ArgumentError, "Invalid parameters: #{e.message}"
  end

  # Generate SVG visualization for the system
  def generate_system_visualization(file_id)
    json_path = GalaxyService.system_data_path(file_id)
    output_path = GalaxyService.system_svg_path(file_id)

    FileUtils.mkdir_p(File.dirname(output_path))

    PlanetarySystem.generate(
      json_path: json_path,
      system_id: file_id,
      output_path: output_path
    )

    Rails.logger.info("RegenerateSystemJob: SVG saved to #{output_path}")
  end

  # Store performance metrics
  def store_performance_metrics(file_id, num_planets, max_moons, durations)
    metrics = {
      timestamp: Time.current,
      system_id: file_id,
      num_planets: num_planets,
      max_moons: max_moons,
      generator_duration: durations[:generator].round(3),
      visualizer_duration: durations[:visualizer].round(3),
      total_duration: durations[:total].round(3),
      within_target: durations[:total] <= 30,
      job_type: "regenerate"
    }

    history = Rails.cache.fetch("job_performance_history") { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write("job_performance_history", history)
  rescue => e
    Rails.logger.error("RegenerateSystemJob: Failed to store metrics - #{e.message}")
  end
end
