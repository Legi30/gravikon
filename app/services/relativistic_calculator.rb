# frozen_string_literal: true

# Service object for computing relativistic effects in multi-system galaxy
# Handles time dilation, distances, and signal delays for inter-system meetings
#
# This service encapsulates complex physics calculations for:
# - Time dilation from local stellar gravity AND galaxy black hole gravity
# - Distances between systems and between bodies across systems
# - Signal delay based on speed of light
# - Meeting statistics accounting for all relativistic effects
#
# Usage:
#   calculator = RelativisticCalculator.new
#   dilation = calculator.calculate_time_dilation(body, system_id)
#   distance = calculator.calculate_inter_system_distance(system_id_1, system_id_2)
#   stats = calculator.calculate_meeting_statistics(participants_with_systems,
#                                                   start_time: "10:00", end_time: "11:30")
class RelativisticCalculator
  # Galaxy center coordinates (default black hole position)
  GALAXY_CENTER_X = PhysicsConstants::GALAXY_CENTER_X
  GALAXY_CENTER_Y = PhysicsConstants::GALAXY_CENTER_Y

  # System-local coordinates are centered on the star at (400, 400)
  SYSTEM_LOCAL_CENTER = PhysicsConstants::SYSTEM_LOCAL_CENTER

  # Initialize calculator with optional galaxy data
  # @param galaxy_data [Hash] Optional galaxy configuration (loads from file if not provided)
  def initialize(galaxy_data: nil)
    @galaxy_data = galaxy_data || load_galaxy_data
    @black_hole = @galaxy_data&.dig("black_hole") || default_black_hole
  end

  # Calculate total time dilation for a body in a system
  # Combines local stellar dilation (stored in body data) with black hole
  # dilation derived from the system's current position in the galaxy.
  #
  # @param body [Hash] Body data with 'dilation' field (local stellar dilation)
  # @param system_id [String, Integer] System ID to locate system in galaxy
  # @return [Float] Combined time dilation factor (0.0-1.0)
  def calculate_time_dilation(body, system_id)
    return 1.0 if body.nil? || system_id.nil?

    # Local stellar time dilation from body data
    local_dilation = body["dilation"] || body[:dilation] || 1.0

    # Black hole time dilation based on system's position in galaxy
    system = find_system(system_id)
    return local_dilation unless system

    black_hole_dilation = calculate_black_hole_dilation(system.x, system.y)

    # Combine both effects (multiplicative - dual reference frames)
    local_dilation * black_hole_dilation
  rescue => e
    Rails.logger.error("Failed to calculate time dilation: #{e.message}")
    1.0 # Fallback to no dilation
  end

  # Calculate distance between two systems in the galaxy
  # Uses Euclidean distance between system positions
  #
  # @param system_id_1 [String, Integer] First system ID
  # @param system_id_2 [String, Integer] Second system ID
  # @return [Float] Distance in galaxy coordinate units
  def calculate_inter_system_distance(system_id_1, system_id_2)
    return 0.0 if system_id_1 == system_id_2

    system_1 = find_system(system_id_1)
    system_2 = find_system(system_id_2)

    return 0.0 unless system_1 && system_2

    # Euclidean distance between system centers
    Math.sqrt((system_1.x - system_2.x)**2 + (system_1.y - system_2.y)**2)
  rescue => e
    Rails.logger.error("Failed to calculate inter-system distance: #{e.message}")
    0.0
  end

  # Calculate total distance between two bodies in potentially different systems
  # Accounts for BOTH inter-system distance AND intra-system positions
  #
  # @param body1 [Hash] First body data with 'x' and 'y' coordinates (local to system)
  # @param system_id_1 [String, Integer] First body's system ID
  # @param body2 [Hash] Second body data with 'x' and 'y' coordinates (local to system)
  # @param system_id_2 [String, Integer] Second body's system ID
  # @return [Float] Total distance in coordinate units
  def calculate_body_to_body_distance(body1, system_id_1, body2, system_id_2)
    return 0.0 if body1.nil? || body2.nil?

    # If same system, use local coordinates directly
    if system_id_1 == system_id_2
      return euclidean_distance(
        body1["x"] || body1[:x] || 0,
        body1["y"] || body1[:y] || 0,
        body2["x"] || body2[:x] || 0,
        body2["y"] || body2[:y] || 0
      )
    end

    # Different systems: transform to galaxy coordinates.
    # Body coordinates are local to their system's canvas, centered on the
    # star at (400, 400), so the offset from the star is (body - 400).
    system_1 = find_system(system_id_1)
    system_2 = find_system(system_id_2)

    return 0.0 unless system_1 && system_2

    body1_galaxy_x = system_1.x + ((body1["x"] || body1[:x] || SYSTEM_LOCAL_CENTER) - SYSTEM_LOCAL_CENTER)
    body1_galaxy_y = system_1.y + ((body1["y"] || body1[:y] || SYSTEM_LOCAL_CENTER) - SYSTEM_LOCAL_CENTER)
    body2_galaxy_x = system_2.x + ((body2["x"] || body2[:x] || SYSTEM_LOCAL_CENTER) - SYSTEM_LOCAL_CENTER)
    body2_galaxy_y = system_2.y + ((body2["y"] || body2[:y] || SYSTEM_LOCAL_CENTER) - SYSTEM_LOCAL_CENTER)

    # Calculate distance in galaxy coordinates
    euclidean_distance(body1_galaxy_x, body1_galaxy_y, body2_galaxy_x, body2_galaxy_y)
  rescue => e
    Rails.logger.error("Failed to calculate body-to-body distance: #{e.message}")
    0.0
  end

  # Calculate signal delay based on distance and speed of light
  # Signal delay = distance / c
  #
  # @param distance [Float] Distance in coordinate units
  # @return [Float] Signal delay time in seconds
  def calculate_signal_delay(distance)
    return 0.0 if distance <= 0

    # Convert coordinate units to meters, then divide by speed of light
    (distance * PhysicsConstants::UNIT_METERS) / PhysicsConstants::C
  rescue => e
    Rails.logger.error("Failed to calculate signal delay: #{e.message}")
    0.0
  end

  # Calculate meeting statistics for participants across multiple systems
  #
  # avg_duration: the scheduled duration (from start/end time) multiplied by
  # the average time-dilation factor of the participants — i.e. how long the
  # meeting lasts on average in the participants' local (proper) time, in minutes.
  # avg_delay: average pairwise signal delay in seconds.
  #
  # @param participants_with_systems [Array<Hash>] Array of {body: Hash, system_id: String/Integer}
  # @param start_time [String] Meeting start in HH:MM
  # @param end_time [String] Meeting end in HH:MM
  # @return [Hash] { avg_duration: Float, avg_delay: Float }
  def calculate_meeting_statistics(participants_with_systems, start_time: nil, end_time: nil)
    return { avg_duration: 0.0, avg_delay: 0.0 } if participants_with_systems.blank?

    base_duration = self.class.duration_minutes(start_time, end_time)

    dilations = []
    distances = []

    participants_with_systems.each do |participant|
      body = participant[:body] || participant["body"]
      system_id = participant[:system_id] || participant["system_id"]

      next if body.nil? || system_id.nil?

      dilations << calculate_time_dilation(body, system_id)
    end

    # Calculate pairwise distances for all participants
    participants_with_systems.combination(2).each do |p1, p2|
      body1 = p1[:body] || p1["body"]
      system_id_1 = p1[:system_id] || p1["system_id"]
      body2 = p2[:body] || p2["body"]
      system_id_2 = p2[:system_id] || p2["system_id"]

      next if body1.nil? || system_id_1.nil? || body2.nil? || system_id_2.nil?

      distances << calculate_body_to_body_distance(body1, system_id_1, body2, system_id_2)
    end

    avg_dilation = dilations.any? ? dilations.sum / dilations.size.to_f : 1.0

    avg_delay = if distances.any?
                  distances.map { |d| calculate_signal_delay(d) }.sum / distances.size.to_f
    else
                  0.0
    end

    {
      avg_duration: (base_duration * avg_dilation).round(2),
      avg_delay: avg_delay.round(2)
    }
  rescue => e
    Rails.logger.error("Failed to calculate meeting statistics: #{e.message}")
    { avg_duration: 0.0, avg_delay: 0.0 }
  end

  # Duration between two HH:MM times in minutes, with midnight wraparound
  # (23:00 -> 01:00 is 120 minutes). Returns 0.0 for missing/invalid input.
  def self.duration_minutes(start_time, end_time)
    return 0.0 if start_time.blank? || end_time.blank?

    start_parts = start_time.split(":")
    end_parts = end_time.split(":")
    return 0.0 unless start_parts.length == 2 && end_parts.length == 2

    start_minutes = start_parts[0].to_i * 60 + start_parts[1].to_i
    end_minutes = end_parts[0].to_i * 60 + end_parts[1].to_i

    minutes = end_minutes - start_minutes
    minutes += 24 * 60 if minutes.negative?
    minutes.to_f
  end

  # Calculate time dilation from black hole at given position
  # Uses gravitational time dilation: sqrt(1 - 2GM/(r*c^2))
  #
  # @param system_x [Float] System X coordinate in galaxy
  # @param system_y [Float] System Y coordinate in galaxy
  # @return [Float] Black hole time dilation factor
  def calculate_black_hole_dilation(system_x, system_y)
    return 1.0 unless @black_hole

    bh_x = @black_hole["x"] || GALAXY_CENTER_X
    bh_y = @black_hole["y"] || GALAXY_CENTER_Y
    bh_mass = @black_hole["mass"] || PhysicsConstants::BLACK_HOLE_MASS

    distance = euclidean_distance(system_x, system_y, bh_x, bh_y)

    PhysicsConstants.gravitational_dilation(bh_mass, distance)
  rescue => e
    Rails.logger.error("Failed to calculate black hole dilation: #{e.message}")
    1.0 # Fallback to no dilation
  end

  private

  # Load galaxy data from file
  # @return [Hash] Galaxy data with black hole configuration
  def load_galaxy_data
    galaxy_file = GalaxyService.galaxy_data_path
    return nil unless File.exist?(galaxy_file)

    JSON.parse(File.read(galaxy_file))
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse galaxy data: #{e.message}")
    nil
  rescue => e
    Rails.logger.error("Failed to load galaxy data: #{e.message}")
    nil
  end

  # Default black hole configuration if galaxy data not available
  # @return [Hash] Default black hole properties
  def default_black_hole
    {
      "name" => "Sagittarius Omega",
      "mass" => PhysicsConstants::BLACK_HOLE_MASS,
      "x" => GALAXY_CENTER_X,
      "y" => GALAXY_CENTER_Y,
      "type" => "black_hole"
    }
  end

  # Find system by ID
  # @param system_id [String, Integer] System ID
  # @return [System, nil] System model instance or nil
  def find_system(system_id)
    return nil if system_id.nil?

    # Try to find by primary key first
    system = System.find_by(id: system_id)
    return system if system

    # Fallback: try to find by name or file id if system_id is a string
    if system_id.is_a?(String)
      System.find_by(name: system_id) || System.find_by(json_file_path: "data/systems/#{system_id}.json")
    else
      nil
    end
  rescue => e
    Rails.logger.error("Failed to find system #{system_id}: #{e.message}")
    nil
  end

  # Calculate Euclidean distance between two points
  # @param x1 [Float] First point X coordinate
  # @param y1 [Float] First point Y coordinate
  # @param x2 [Float] Second point X coordinate
  # @param y2 [Float] Second point Y coordinate
  # @return [Float] Distance
  def euclidean_distance(x1, y1, x2, y2)
    Math.sqrt((x1 - x2)**2 + (y1 - y2)**2)
  end
end
