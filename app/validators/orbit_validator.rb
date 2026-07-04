# frozen_string_literal: true

# Orbit validator for ensuring celestial bodies and systems stay within canvas bounds
# Validates positions at two levels:
# 1. Galaxy level: Solar systems orbiting the central black hole
# 2. System level: Planets and moons within a solar system
#
# Returns validation results in format: { valid: Boolean, errors: Array<String> }
module OrbitValidator
  # Configuration constants for canvas and validation rules
  CANVAS_SIZE = 800
  CANVAS_MIN = 0
  CANVAS_MAX = 800

  # Galaxy-level validation constants
  GALAXY_MIN_SAFE = CANVAS_MIN # 0 - Allow full canvas
  GALAXY_MAX_SAFE = CANVAS_MAX # 800 - Allow full canvas
  GALAXY_CENTER_X = 400
  GALAXY_CENTER_Y = 400
  MIN_DISTANCE_FROM_BLACK_HOLE = 50 # Minimum safe distance from black hole center
  MIN_DISTANCE_BETWEEN_SYSTEMS = 40 # Minimum distance between system centers

  # Recommended safe zone (for warnings, not hard limits)
  RECOMMENDED_MIN = 50
  RECOMMENDED_MAX = 750

  # System-level validation constants
  SYSTEM_CENTER_X = 400
  SYSTEM_CENTER_Y = 400
  SYSTEM_MARGIN = 30 # Minimum distance from canvas edge for bodies within system
  SYSTEM_MIN_SAFE = SYSTEM_MARGIN # 30
  SYSTEM_MAX_SAFE = CANVAS_MAX - SYSTEM_MARGIN # 770
  MAX_ORBIT_RADIUS_FROM_STAR = 370 # Maximum distance from star (400 - 30)
  MIN_BODY_DISTANCE = 15 # Minimum distance between celestial bodies

  class << self
    # Validate a system's position in the galaxy
    # Ensures system is within canvas bounds, not too close to black hole, and doesn't collide with other systems
    #
    # @param system_x [Float] X coordinate of system in galaxy
    # @param system_y [Float] Y coordinate of system in galaxy
    # @param galaxy_data [Hash] Galaxy data with black_hole and systems
    # @param exclude_system_id [String, Integer, nil] System ID to exclude from collision check (for updates)
    # @return [Hash] { valid: Boolean, errors: Array<String> }
    def validate_system_orbit(system_x, system_y, galaxy_data, exclude_system_id: nil)
      errors = []

      # Validate coordinates are numeric
      unless system_x.is_a?(Numeric) && system_y.is_a?(Numeric)
        errors << "Souřadnice musí být číselné hodnoty"
        return { valid: false, errors: errors }
      end

      # Check canvas bounds (0-800)
      if system_x < GALAXY_MIN_SAFE || system_x > GALAXY_MAX_SAFE
        errors << "X souřadnice musí být v rozsahu #{GALAXY_MIN_SAFE}-#{GALAXY_MAX_SAFE} (systém by byl mimo plátno)"
      end

      if system_y < GALAXY_MIN_SAFE || system_y > GALAXY_MAX_SAFE
        errors << "Y souřadnice musí být v rozsahu #{GALAXY_MIN_SAFE}-#{GALAXY_MAX_SAFE} (systém by byl mimo plátno)"
      end

      # Get black hole position (default to center if not provided)
      black_hole = galaxy_data["black_hole"] || galaxy_data[:black_hole]
      bh_x = black_hole ? (black_hole["x"] || black_hole[:x] || GALAXY_CENTER_X) : GALAXY_CENTER_X
      bh_y = black_hole ? (black_hole["y"] || black_hole[:y] || GALAXY_CENTER_Y) : GALAXY_CENTER_Y

      # Check distance from black hole (must be outside Schwarzschild radius + safety margin)
      distance_from_black_hole = calculate_distance(system_x, system_y, bh_x, bh_y)
      if distance_from_black_hole < MIN_DISTANCE_FROM_BLACK_HOLE
        errors << "Systém je příliš blízko černé díře (min. vzdálenost: #{MIN_DISTANCE_FROM_BLACK_HOLE})"
      end

      # Check collision with other systems
      systems = galaxy_data["systems"] || galaxy_data[:systems] || []
      systems.each do |system|
        # Skip if this is the system being updated
        system_id_str = (system["id"] || system[:id]).to_s
        next if exclude_system_id && system_id_str == exclude_system_id.to_s

        other_x = system["x"] || system[:x]
        other_y = system["y"] || system[:y]

        next unless other_x && other_y

        distance = calculate_distance(system_x, system_y, other_x, other_y)
        if distance < MIN_DISTANCE_BETWEEN_SYSTEMS
          errors << "Systém je příliš blízko jinému systému (min. vzdálenost: #{MIN_DISTANCE_BETWEEN_SYSTEMS})"
          break # Only report first collision
        end
      end

      {
        valid: errors.empty?,
        errors: errors
      }
    rescue => e
      {
        valid: false,
        errors: [ "Chyba při validaci pozice systému: #{e.message}" ]
      }
    end

    # Validate a celestial body's position within a solar system
    # Ensures body stays within the system's allocated space and doesn't collide with other bodies
    #
    # @param body_x [Float] X coordinate of body
    # @param body_y [Float] Y coordinate of body
    # @param parent_x [Float] X coordinate of parent (star for planets, planet for moons)
    # @param parent_y [Float] Y coordinate of parent
    # @param system_bounds [Hash, nil] Optional custom bounds { min_x, max_x, min_y, max_y }
    # @param existing_bodies [Array<Hash>, nil] Optional array of existing bodies to check collisions
    # @return [Hash] { valid: Boolean, errors: Array<String> }
    def validate_body_orbit(body_x, body_y, parent_x, parent_y, system_bounds: nil, existing_bodies: nil)
      errors = []

      # Validate coordinates are numeric
      unless body_x.is_a?(Numeric) && body_y.is_a?(Numeric)
        errors << "Souřadnice tělesa musí být číselné hodnoty"
        return { valid: false, errors: errors }
      end

      unless parent_x.is_a?(Numeric) && parent_y.is_a?(Numeric)
        errors << "Souřadnice rodiče musí být číselné hodnoty"
        return { valid: false, errors: errors }
      end

      # Use custom bounds if provided, otherwise use default canvas bounds with margin
      min_x = system_bounds ? system_bounds[:min_x] : SYSTEM_MIN_SAFE
      max_x = system_bounds ? system_bounds[:max_x] : SYSTEM_MAX_SAFE
      min_y = system_bounds ? system_bounds[:min_y] : SYSTEM_MIN_SAFE
      max_y = system_bounds ? system_bounds[:max_y] : SYSTEM_MAX_SAFE

      # Check canvas bounds (default 30-770 with margin for bodies)
      if body_x < min_x || body_x > max_x
        errors << "X souřadnice tělesa musí být v rozsahu #{min_x.round}-#{max_x.round} (těleso by bylo mimo plátno)"
      end

      if body_y < min_y || body_y > max_y
        errors << "Y souřadnice tělesa musí být v rozsahu #{min_y.round}-#{max_y.round} (těleso by bylo mimo plátno)"
      end

      # Check maximum orbit radius from parent (star/planet)
      # For star-centered systems, ensure bodies don't go beyond max radius
      if parent_x == SYSTEM_CENTER_X && parent_y == SYSTEM_CENTER_Y
        distance_from_center = calculate_distance(body_x, body_y, parent_x, parent_y)
        if distance_from_center > MAX_ORBIT_RADIUS_FROM_STAR
          errors << "Těleso je příliš daleko od hvězdy (max. vzdálenost: #{MAX_ORBIT_RADIUS_FROM_STAR})"
        end
      end

      # Check collision with existing bodies if provided
      if existing_bodies && existing_bodies.any?
        existing_bodies.each do |other_body|
          other_x = other_body["x"] || other_body[:x]
          other_y = other_body["y"] || other_body[:y]

          next unless other_x && other_y

          distance = calculate_distance(body_x, body_y, other_x, other_y)
          if distance < MIN_BODY_DISTANCE
            other_name = other_body["name"] || other_body[:name] || "jiné těleso"
            errors << "Těleso je příliš blízko k #{other_name} (min. vzdálenost: #{MIN_BODY_DISTANCE})"
            break # Only report first collision
          end
        end
      end

      {
        valid: errors.empty?,
        errors: errors
      }
    rescue => e
      {
        valid: false,
        errors: [ "Chyba při validaci pozice tělesa: #{e.message}" ]
      }
    end

    # Validate all bodies in a system at once
    # Useful for validating an entire generated system
    #
    # @param bodies [Array<Hash>] Array of celestial bodies with x, y coordinates
    # @param system_bounds [Hash, nil] Optional custom bounds
    # @return [Hash] { valid: Boolean, errors: Array<String> }
    def validate_all_bodies(bodies, system_bounds: nil)
      errors = []

      bodies.each_with_index do |body, index|
        body_x = body["x"] || body[:x]
        body_y = body["y"] || body[:y]
        body_name = body["name"] || body[:name] || "Těleso #{index + 1}"
        body_type = body["type"] || body[:type]

        # Skip if coordinates missing
        next unless body_x && body_y

        # Find parent body (star for planets, planet for moons)
        parent = find_parent_body(body, bodies)
        parent_x = parent ? (parent["x"] || parent[:x]) : SYSTEM_CENTER_X
        parent_y = parent ? (parent["y"] || parent[:y]) : SYSTEM_CENTER_Y

        # Get other bodies for collision detection (exclude current body)
        other_bodies = bodies.select.with_index { |_, i| i != index }

        # Validate this body
        result = validate_body_orbit(
          body_x, body_y,
          parent_x, parent_y,
          system_bounds: system_bounds,
          existing_bodies: other_bodies
        )

        unless result[:valid]
          result[:errors].each do |error|
            errors << "#{body_name} (#{body_type}): #{error}"
          end
        end
      end

      {
        valid: errors.empty?,
        errors: errors
      }
    end

    private

    # Calculate Euclidean distance between two points
    # @param x1 [Float] X coordinate of first point
    # @param y1 [Float] Y coordinate of first point
    # @param x2 [Float] X coordinate of second point
    # @param y2 [Float] Y coordinate of second point
    # @return [Float] Distance between points
    def calculate_distance(x1, y1, x2, y2)
      Math.sqrt((x1 - x2)**2 + (y1 - y2)**2)
    end

    # Find parent body for a given body (star for planets, planet for moons)
    # @param body [Hash] Body to find parent for
    # @param bodies [Array<Hash>] All bodies in system
    # @return [Hash, nil] Parent body or nil if none found
    def find_parent_body(body, bodies)
      body_type = body["type"] || body[:type]

      case body_type
      when "planet"
        # Parent is the star
        bodies.find { |b| (b["type"] || b[:type]) == "star" }
      when "moon"
        # Parent is the closest planet
        # This is a simplification - in reality we'd need more metadata
        planets = bodies.select { |b| (b["type"] || b[:type]) == "planet" }
        return nil if planets.empty?

        body_x = body["x"] || body[:x]
        body_y = body["y"] || body[:y]

        planets.min_by do |planet|
          planet_x = planet["x"] || planet[:x]
          planet_y = planet["y"] || planet[:y]
          calculate_distance(body_x, body_y, planet_x, planet_y)
        end
      else
        # Star or unknown type has no parent
        nil
      end
    end
  end
end
