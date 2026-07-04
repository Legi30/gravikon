# frozen_string_literal: true

# Cache warming initializer
# Preloads frequently accessed data into cache on application startup
# This improves initial response times for galaxy and system data

Rails.application.config.after_initialize do
  # Only warm cache in production and staging environments
  # Skip in development to avoid slowing down startup
  # Skip in test to avoid interfering with test isolation
  next unless Rails.env.production? || Rails.env.staging?

  # Use a background thread to avoid blocking application startup
  Thread.new do
    begin
      # Wait a bit for the application to fully initialize
      sleep 2

      Rails.logger.info("Cache warming: Starting...")

      # Warm galaxy data cache
      galaxy_data = GalaxyService.load_galaxy_data
      systems_count = galaxy_data['systems']&.count || 0
      Rails.logger.info("Cache warming: Galaxy data loaded (#{systems_count} systems)")

      # Warm individual system caches
      # Only load first 10 systems to avoid excessive startup time
      System.order(:id).limit(10).each do |system|
        system_file_id = File.basename(system.json_file_path, '.json')
        system_data = GalaxyService.load_system_data(system_file_id)

        if system_data
          body_count = system_data['bodies']&.count || 0
          Rails.logger.info("Cache warming: System '#{system.name}' loaded (#{body_count} bodies)")
        else
          Rails.logger.warn("Cache warming: System '#{system.name}' has no data file")
        end
      end

      # Warm used celestial names cache
      used_names = GalaxyService.get_used_celestial_names
      Rails.logger.info("Cache warming: Used celestial names loaded (#{used_names.count} names)")

      # Warm SVG timestamps for quick cache busting
      GalaxyService.get_svg_timestamp(:galaxy)
      Rails.logger.info("Cache warming: Galaxy SVG timestamp loaded")

      # Warm meeting stats for first few systems
      System.order(:id).limit(5).each do |system|
        stats = GalaxyService.get_system_meeting_stats(system.id)
        Rails.logger.info("Cache warming: Meeting stats for '#{system.name}' loaded (#{stats[:total_meetings]} meetings)")
      end

      Rails.logger.info("Cache warming: Completed successfully!")
    rescue => e
      # Log error but don't crash the application
      Rails.logger.error("Cache warming: Failed - #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
    end
  end
end
