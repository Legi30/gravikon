# frozen_string_literal: true

# Background job for regenerating the galaxy visualization
# Creates the galaxy.svg file showing all systems orbiting the central black hole
# Should be called when systems are added, removed, or repositioned
class GenerateGalaxyVisualizationJob < ApplicationJob
  queue_as :default

  # Generate or regenerate the galaxy visualization
  def perform
    job_start_time = Time.current

    # Self-heal: if galaxy_data.json is missing, rebuild it from the database
    # before the visualizer needs it.
    unless File.exist?(GalaxyService.galaxy_data_path)
      Rails.logger.warn("GenerateGalaxyVisualizationJob: galaxy_data.json missing, rebuilding from database")
      GalaxyService.rebuild_galaxy_data!
    end

    galaxy_data = GalaxyService.load_galaxy_data
    systems_count = galaxy_data['systems']&.count || 0

    output_path = GalaxyService.galaxy_svg_path
    FileUtils.mkdir_p(File.dirname(output_path))

    visualizer = GalaxyVisualizer.new(GalaxyService.galaxy_data_path)
    visualizer.to_svg(output_path)

    GalaxyService.update_svg_timestamp(:galaxy)

    total_duration = Time.current - job_start_time
    Rails.logger.info("GenerateGalaxyVisualizationJob: galaxy.svg with #{systems_count} systems saved to #{output_path} in #{total_duration.round(2)}s")

    store_performance_metrics(systems_count, total_duration)
  rescue => e
    Rails.logger.error("GenerateGalaxyVisualizationJob FAILED: #{e.class}: #{e.message}")
    raise
  end

  private

  # Store performance metrics
  def store_performance_metrics(systems_count, total_duration)
    metrics = {
      timestamp: Time.current,
      systems_count: systems_count,
      total_duration: total_duration.round(3),
      within_target: total_duration <= 10,
      job_type: 'galaxy_visualization'
    }

    history = Rails.cache.fetch('job_performance_history') { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write('job_performance_history', history)
  rescue => e
    Rails.logger.error("GenerateGalaxyVisualizationJob: Failed to store metrics - #{e.message}")
  end
end
