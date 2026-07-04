# frozen_string_literal: true

require_relative "../validators/orbit_validator"
require "erb"

# Galaxy service for managing galaxy-level data and operations
# Handles loading, validation, and manipulation of galaxy data including
# the central black hole and all solar systems
class GalaxyService
  GALAXY_CENTER = [ PhysicsConstants::GALAXY_CENTER_X, PhysicsConstants::GALAXY_CENTER_Y ].freeze
  CANVAS_SIZE = 800

  # Minimum distances for collision detection
  MIN_DISTANCE_FROM_BLACK_HOLE = 50 # Minimum distance from galaxy center
  MIN_DISTANCE_BETWEEN_SYSTEMS = 40 # Minimum distance between system centers

  # Cache versioning for schema changes
  CACHE_VERSION = "v2"

  class << self
    # --- File locations -----------------------------------------------------
    # Single source of truth for where generated galaxy/system data lives.
    # Roots are configurable (config.x.gravikon.*) so tests can point them
    # at tmp/ instead of destroying real data.

    # Root directory for JSON data files
    def data_root
      Pathname.new(Rails.application.config.x.gravikon.data_root || Rails.root.join("data"))
    end

    # Root directory for generated SVG files (public/ in dev & production)
    def svg_root
      Pathname.new(Rails.application.config.x.gravikon.svg_root || Rails.root.join("public"))
    end

    def galaxy_data_path
      data_root.join("galaxy_data.json")
    end

    def systems_data_dir
      data_root.join("systems")
    end

    # @param file_id [String] System file id (UUID or slug, sanitized)
    def system_data_path(file_id)
      sanitized = sanitize_system_id(file_id)
      return nil unless sanitized

      systems_data_dir.join("#{sanitized}.json")
    end

    def galaxy_svg_path
      svg_root.join("galaxy.svg")
    end

    def systems_svg_dir
      svg_root.join("systems")
    end

    # @param file_id [String] System file id (UUID or slug, sanitized)
    def system_svg_path(file_id)
      sanitized = sanitize_system_id(file_id)
      return nil unless sanitized

      systems_svg_dir.join("#{sanitized}.svg")
    end
    # Load galaxy data from file with versioned caching
    # Returns hash with black_hole and systems data
    def load_galaxy_data
      cache_key = "galaxy_data_#{CACHE_VERSION}"

      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        log_cache_miss("galaxy_data")
        load_galaxy_data_from_file
      end.tap do
        log_cache_hit("galaxy_data")
      end
    end

    # Load individual system data with caching
    # @param system_id [String, Integer] System ID
    # @return [Hash, nil] System data or nil if not found
    def load_system_data(system_id)
      cache_key = "system_data_#{system_id}_#{CACHE_VERSION}"

      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        log_cache_miss("system_data_#{system_id}")
        load_system_data_from_file(system_id)
      end.tap do |data|
        log_cache_hit("system_data_#{system_id}") if data
      end
    end

    # Add a system to the galaxy at specified coordinates
    # @param system_id [String, Integer] System ID or database ID
    # @param x [Float] X coordinate in galaxy
    # @param y [Float] Y coordinate in galaxy
    # @return [Boolean] Success status
    def add_system(system_id, x, y)
      # Validate position (excluding this system's own entry when updating)
      validation_result = validate_system_position(x, y, exclude_system_id: system_id)
      unless validation_result[:valid]
        Rails.logger.error("Cannot add system: #{validation_result[:errors].join(', ')}")
        return false
      end

      galaxy_data = load_galaxy_data_from_file

      # Check if system already exists
      existing = galaxy_data["systems"].find { |s| s["id"].to_s == system_id.to_s }
      if existing
        # Update existing system position
        existing["x"] = x.to_f
        existing["y"] = y.to_f
      else
        # Add new system reference
        galaxy_data["systems"] << {
          "id" => system_id.to_s,
          "x" => x.to_f,
          "y" => y.to_f
        }
      end

      save_galaxy_data(galaxy_data)
      clear_galaxy_cache
      true
    rescue => e
      Rails.logger.error("Failed to add system: #{e.message}")
      false
    end

    # Remove a system from the galaxy
    # @param system_id [String, Integer] System ID to remove
    # @return [Boolean] Success status
    def remove_system(system_id)
      galaxy_data = load_galaxy_data_from_file

      # Remove system from array
      galaxy_data["systems"].reject! { |s| s["id"].to_s == system_id.to_s }

      save_galaxy_data(galaxy_data)
      clear_galaxy_cache
      true
    rescue => e
      Rails.logger.error("Failed to remove system: #{e.message}")
      false
    end

    # Validate system position in galaxy using OrbitValidator
    # @param x [Float] X coordinate
    # @param y [Float] Y coordinate
    # @param exclude_system_id [String, Integer, nil] System ID to exclude from collision check (for updates)
    # @return [Hash] { valid: Boolean, errors: Array<String> }
    def validate_system_position(x, y, exclude_system_id: nil)
      # Load galaxy data for validation
      galaxy_data = load_galaxy_data_from_file

      # Use OrbitValidator for consistent validation logic
      OrbitValidator.validate_system_orbit(
        x, y,
        galaxy_data,
        exclude_system_id: exclude_system_id
      )
    rescue => e
      Rails.logger.error("Failed to validate system position: #{e.message}")
      {
        valid: false,
        errors: [ "Chyba při validaci pozice: #{e.message}" ]
      }
    end

    # Calculate Schwarzschild radius for a black hole
    # @param mass [Float] Mass of the black hole
    # @return [Float] Schwarzschild radius
    def calculate_schwarzschild_radius(mass)
      PhysicsConstants.schwarzschild_radius(mass)
    end

    # Calculate time dilation at event horizon
    # @param mass [Float] Mass of the black hole
    # @return [Float] Time dilation factor (0 at event horizon)
    def calculate_event_horizon_dilation(mass)
      # At event horizon, time dilation approaches infinity (factor approaches 0)
      0.0
    end

    # Clear galaxy-related caches
    def clear_galaxy_cache
      Rails.cache.delete("galaxy_data_#{CACHE_VERSION}")
      Rails.cache.delete_matched("galaxy_*")
      # Also clear legacy cache key
      Rails.cache.delete("galaxy_data")
      Rails.logger.info("Galaxy cache cleared")
    rescue => e
      Rails.logger.error("Failed to clear galaxy cache: #{e.message}")
    end

    # Clear cache for specific system
    # @param system_id [String, Integer] System ID
    def clear_system_cache(system_id)
      Rails.cache.delete("system_data_#{system_id}_#{CACHE_VERSION}")
      Rails.cache.delete_matched("system_#{system_id}_*")
      # Also clear legacy cache key
      Rails.cache.delete("system_data_#{system_id}")
      Rails.logger.info("System cache cleared for #{system_id}")
    rescue => e
      Rails.logger.error("Failed to clear system cache: #{e.message}")
    end

    # Clear all system-related caches
    def clear_all_system_caches
      Rails.cache.delete_matched("system_*")
      Rails.cache.delete("used_celestial_names")
      Rails.logger.info("All system caches cleared")
    rescue => e
      Rails.logger.error("Failed to clear all system caches: #{e.message}")
    end

    # Get or cache used celestial names across all systems
    # @return [Array<String>] List of used names
    def get_used_celestial_names
      Rails.cache.fetch("used_celestial_names", expires_in: 30.minutes) do
        log_cache_miss("used_celestial_names")
        load_used_names_from_all_systems
      end.tap do
        log_cache_hit("used_celestial_names")
      end
    end

    # Invalidate used names cache (called when system is created/updated)
    def invalidate_used_names_cache
      Rails.cache.delete("used_celestial_names")
      Rails.logger.debug("Used celestial names cache invalidated")
    end

    # Get SVG timestamp for cache busting
    # @param svg_type [Symbol] :galaxy or :system
    # @param system_id [String, nil] System ID for system SVG
    # @return [Integer] Unix timestamp
    def get_svg_timestamp(svg_type, system_id: nil)
      cache_key = svg_type == :galaxy ? "galaxy_svg_timestamp" : "system_#{system_id}_svg_timestamp"

      cached_time = Rails.cache.read(cache_key)
      return cached_time if cached_time

      # Get from file modification time
      file_path = svg_type == :galaxy ? galaxy_svg_path : system_svg_path(system_id)

      timestamp = file_path && File.exist?(file_path) ? File.mtime(file_path).to_i : Time.current.to_i
      Rails.cache.write(cache_key, timestamp, expires_in: 1.hour)
      timestamp
    end

    # Update SVG timestamp after regeneration
    # @param svg_type [Symbol] :galaxy or :system
    # @param system_id [String, nil] System ID for system SVG
    def update_svg_timestamp(svg_type, system_id: nil)
      cache_key = svg_type == :galaxy ? "galaxy_svg_timestamp" : "system_#{system_id}_svg_timestamp"
      timestamp = Time.current.to_i
      Rails.cache.write(cache_key, timestamp, expires_in: 1.hour)
      Rails.logger.debug("Updated SVG timestamp for #{svg_type}#{system_id ? " (#{system_id})" : ''}")
      timestamp
    end

    # Get meeting statistics for a specific system
    # @param system_id [String, Integer] System ID
    # @return [Hash] Statistics hash
    def get_system_meeting_stats(system_id)
      cache_key = "system_#{system_id}_meeting_stats_#{CACHE_VERSION}"

      Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
        log_cache_miss("system_#{system_id}_meeting_stats")
        calculate_system_meeting_stats(system_id)
      end.tap do
        log_cache_hit("system_#{system_id}_meeting_stats")
      end
    end

    # Invalidate meeting stats cache for a system
    # @param system_id [String, Integer] System ID
    def invalidate_system_meeting_stats(system_id)
      Rails.cache.delete("system_#{system_id}_meeting_stats_#{CACHE_VERSION}")
      Rails.logger.debug("Meeting stats cache invalidated for system #{system_id}")
    end

    # Rebuild galaxy_data.json from the System database records.
    # Self-healing: recreates the file (default black hole + one entry per
    # DB system) when it is missing or out of sync.
    # @return [Hash] The rebuilt galaxy data
    def rebuild_galaxy_data!
      galaxy_data = create_default_galaxy_data

      System.find_each do |system|
        file_id = system.system_id
        next if file_id.blank?

        galaxy_data["systems"] << {
          "id" => file_id,
          "x" => system.x.to_f,
          "y" => system.y.to_f
        }
      end

      save_galaxy_data(galaxy_data)
      clear_galaxy_cache
      Rails.logger.info("Galaxy data rebuilt from database (#{galaxy_data['systems'].size} systems)")
      galaxy_data
    end

    private

    # Load galaxy data from file without caching
    # @return [Hash] Galaxy data
    def load_galaxy_data_from_file
      file_path = galaxy_data_path

      unless File.exist?(file_path)
        Rails.logger.warn("Galaxy data file not found, creating default")
        return create_default_galaxy_data
      end

      JSON.parse(File.read(file_path))
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse galaxy data: #{e.message}")
      create_default_galaxy_data
    rescue => e
      Rails.logger.error("Failed to load galaxy data: #{e.message}")
      create_default_galaxy_data
    end

    # Save galaxy data to file
    # @param galaxy_data [Hash] Galaxy data to save
    def save_galaxy_data(galaxy_data)
      file_path = galaxy_data_path
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, JSON.pretty_generate(galaxy_data))
      Rails.logger.info("Galaxy data saved to #{file_path}")
    end

    # Create default galaxy data structure
    # @return [Hash] Default galaxy data
    def create_default_galaxy_data
      # Sagittarius A* has mass of ~4.1 million solar masses
      # Solar mass = 1.989e30 kg
      # Black hole mass = 4.1e6 * 1.989e30 = 8.15e36 kg
      black_hole_mass = 8.2e36

      {
        "black_hole" => {
          "name" => "Sagittarius Omega",
          "mass" => black_hole_mass,
          "x" => GALAXY_CENTER[0],
          "y" => GALAXY_CENTER[1],
          "schwarzschild_radius" => calculate_schwarzschild_radius(black_hole_mass),
          "dilation" => calculate_event_horizon_dilation(black_hole_mass),
          "type" => "black_hole"
        },
        "systems" => []
      }
    end

    # Load system data from file without caching
    # @param system_id [String, Integer] System ID
    # @return [Hash, nil] System data or nil if not found
    def load_system_data_from_file(system_id)
      # Security: system_data_path sanitizes the id to prevent path traversal
      file_path = system_data_path(system_id)
      unless file_path
        Rails.logger.error("Security: Invalid system_id rejected: #{system_id}")
        return nil
      end

      unless File.exist?(file_path)
        Rails.logger.warn("System data file not found: #{file_path}")
        return nil
      end

      JSON.parse(File.read(file_path))
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse system data for #{system_id}: #{e.message}")
      nil
    rescue => e
      Rails.logger.error("Failed to load system data for #{system_id}: #{e.message}")
      nil
    end

    # Load used names from all systems
    # @return [Array<String>] List of all body names across systems
    def load_used_names_from_all_systems
      used_names = []
      systems_dir = systems_data_dir

      return used_names unless Dir.exist?(systems_dir)

      Dir.glob(File.join(systems_dir, "*.json")).each do |file|
        begin
          data = JSON.parse(File.read(file))
          data["bodies"]&.each do |body|
            used_names << body["name"] if body["name"]
          end
        rescue => e
          Rails.logger.warn("Failed to load names from #{file}: #{e.message}")
        end
      end

      used_names.uniq
    end

    # Calculate meeting statistics for a specific system
    # @param system_id [String, Integer] System ID
    # @return [Hash] Statistics hash
    def calculate_system_meeting_stats(system_id)
      meetings = if defined?(Meeting)
                   Meeting.where(system_id: system_id)
      else
                   []
      end

      {
        total_meetings: meetings.count,
        avg_duration: meetings.any? ? meetings.average(:local_avg_duration).to_f.round(2) : 0,
        avg_delay: meetings.any? ? meetings.average(:avg_delay).to_f.round(2) : 0,
        last_meeting_at: meetings.maximum(:created_at)
      }
    rescue => e
      Rails.logger.error("Failed to calculate meeting stats for system #{system_id}: #{e.message}")
      {
        total_meetings: 0,
        avg_duration: 0,
        avg_delay: 0,
        last_meeting_at: nil
      }
    end

    # Log cache hit (only in development)
    # @param key [String] Cache key
    def log_cache_hit(key)
      return unless Rails.env.development?
      Rails.logger.debug("CACHE HIT: #{key}")
    end

    # Log cache miss (only in development)
    # @param key [String] Cache key
    def log_cache_miss(key)
      return unless Rails.env.development?
      Rails.logger.debug("CACHE MISS: #{key}")
    end

    # Security: Sanitize system_id to prevent path traversal attacks
    # @param system_id [String, Integer] System ID to sanitize
    # @return [String, nil] Sanitized system_id or nil if invalid
    def sanitize_system_id(system_id)
      return nil if system_id.blank?

      id_str = system_id.to_s

      # Reject paths containing '..' (path traversal)
      if id_str.include?("..")
        Rails.logger.warn("Security: Path traversal attempt in system_id: #{id_str}")
        return nil
      end

      # Reject paths containing '/' (directory traversal)
      if id_str.include?("/")
        Rails.logger.warn("Security: Directory traversal attempt in system_id: #{id_str}")
        return nil
      end

      # Reject paths containing '\' (Windows path separator)
      if id_str.include?("\\")
        Rails.logger.warn("Security: Backslash in system_id: #{id_str}")
        return nil
      end

      # Validate format: UUID (8-4-4-4-12) or alphanumeric slug
      # UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      # Slug format: alphanumeric and underscores only
      if id_str.match?(/\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/i)
        id_str.downcase
      elsif id_str.match?(/\A[a-z0-9_]+\z/i)
        id_str.downcase
      else
        Rails.logger.warn("Security: Invalid system_id format: #{id_str}")
        nil
      end
    end
  end
end
