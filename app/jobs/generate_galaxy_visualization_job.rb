# frozen_string_literal: true

# Background job for regenerating the galaxy visualization
# Creates the galaxy.svg file showing all systems orbiting the central black hole
# Should be called when systems are added, removed, or repositioned
class GenerateGalaxyVisualizationJob < ApplicationJob
  queue_as :default

  # Retry on transient errors
  retry_on StandardError, wait: 5.seconds, attempts: 3 do |job, error|
    Rails.logger.error("GenerateGalaxyVisualizationJob: Retry attempt failed - #{error.class}: #{error.message}")
  end

  # Generate or regenerate the galaxy visualization
  def perform
    job_start_time = Time.current

    Rails.logger.info("=" * 80)
    Rails.logger.info("GenerateGalaxyVisualizationJob: Starting galaxy visualization")
    Rails.logger.info("=" * 80)

    begin
      # 1. Load galaxy data
      load_start = Time.current
      Rails.logger.info("GenerateGalaxyVisualizationJob: Step 1/3 - Loading galaxy data")

      galaxy_data = GalaxyService.load_galaxy_data
      unless galaxy_data
        Rails.logger.error("GenerateGalaxyVisualizationJob: Failed to load galaxy data")
        raise StandardError, "Failed to load galaxy data"
      end

      systems_count = galaxy_data['systems']&.count || 0
      Rails.logger.info("GenerateGalaxyVisualizationJob: Loaded data with #{systems_count} systems")

      load_duration = Time.current - load_start

      # 2. Generate and save galaxy SVG (combined step)
      viz_start = Time.current
      Rails.logger.info("GenerateGalaxyVisualizationJob: Step 2/2 - Generating and saving galaxy SVG")

      output_path = generate_galaxy_svg(galaxy_data)

      viz_duration = Time.current - viz_start
      Rails.logger.info("GenerateGalaxyVisualizationJob: SVG generated and saved to #{output_path} in #{viz_duration.round(2)}s")

      # 4. Clear galaxy cache
      Rails.cache.delete('galaxy_svg')
      Rails.logger.info("GenerateGalaxyVisualizationJob: Cache cleared")

      # Calculate total duration
      total_duration = Time.current - job_start_time

      # Log performance summary
      Rails.logger.info("=" * 80)
      Rails.logger.info("GenerateGalaxyVisualizationJob PERFORMANCE SUMMARY:")
      Rails.logger.info("  Systems count: #{systems_count}")
      Rails.logger.info("  Load time: #{load_duration.round(2)}s")
      Rails.logger.info("  Visualization time: #{viz_duration.round(2)}s")
      Rails.logger.info("  Total time: #{total_duration.round(2)}s")
      Rails.logger.info("  Status: SUCCESS ✓")

      if total_duration > 10
        Rails.logger.warn("  WARNING: Job exceeded 10s target (#{total_duration.round(2)}s)")
      else
        Rails.logger.info("  Performance: Within 10s target ✓")
      end
      Rails.logger.info("=" * 80)

      # Store metrics
      store_performance_metrics(systems_count, {
        load: load_duration,
        visualizer: viz_duration,
        total: total_duration
      })

    rescue => e
      job_duration = Time.current - job_start_time
      Rails.logger.error("=" * 80)
      Rails.logger.error("GenerateGalaxyVisualizationJob: FAILED after #{job_duration.round(2)}s")
      Rails.logger.error("  Error: #{e.class}: #{e.message}")
      Rails.logger.error("  Backtrace: #{e.backtrace.first(10).join("\n  ")}")
      Rails.logger.error("=" * 80)
      raise
    end
  end

  private

  # Generate galaxy SVG using GalaxyVisualizer
  def generate_galaxy_svg(galaxy_data)
    require_relative '../../lib/galaxy_visualizer'

    # GalaxyVisualizer.to_svg loads galaxy_data.json automatically and writes the file
    galaxy_json_path = Rails.root.join('data', 'galaxy_data.json')
    output_path = Rails.root.join('public', 'galaxy.svg')

    visualizer = GalaxyVisualizer.new(galaxy_json_path)
    visualizer.to_svg(output_path)

    Rails.logger.info("GenerateGalaxyVisualizationJob: Galaxy SVG generated successfully")
    # Return the output path for consistency
    output_path.to_s
  rescue => e
    Rails.logger.error("GenerateGalaxyVisualizationJob: Visualization generation failed - #{e.message}")
    raise
  end

  # Store performance metrics
  def store_performance_metrics(systems_count, durations)
    metrics = {
      timestamp: Time.current,
      systems_count: systems_count,
      load_duration: durations[:load].round(3),
      visualizer_duration: durations[:visualizer].round(3),
      total_duration: durations[:total].round(3),
      within_target: durations[:total] <= 10,
      job_type: 'galaxy_visualization'
    }

    history = Rails.cache.fetch('job_performance_history') { [] }
    history << metrics
    history = history.last(20)
    Rails.cache.write('job_performance_history', history)

    Rails.logger.debug("GenerateGalaxyVisualizationJob: Performance metrics stored")
  rescue => e
    Rails.logger.error("GenerateGalaxyVisualizationJob: Failed to store metrics - #{e.message}")
  end
end
