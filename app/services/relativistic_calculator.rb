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
#   stats = calculator.calculate_meeting_statistics(participants_with_systems)
class RelativisticCalculator
  # Physics constants (matching SystemGenerator for consistency)
  GRAVITATIONAL_CONSTANT = 0.0001 # 6.67430e-11 (scaled for simulation)
  C = 10_000_000 # 299_792_458.0 m/s (speed of light, scaled)

  # Galaxy center coordinates (default black hole position)
  GALAXY_CENTER_X = 400
  GALAXY_CENTER_Y = 400

  # Initialize calculator with optional galaxy data
  # @param galaxy_data [Hash] Optional galaxy configuration (loads from file if not provided)
  def initialize(galaxy_data: nil)
    @galaxy_data = galaxy_data || load_galaxy_data
    @black_hole = @galaxy_data&.dig('black_hole') || default_black_hole
  end

  # Calculate total time dilation for a body in a system
  # Accounts for BOTH local stellar gravity (from body data) and black hole gravity
  #
  # @param body [Hash] Body data with 'dilation' field (local stellar dilation)
  # @param system_id [String, Integer] System ID to locate system in galaxy
  # @return [Float] Combined time dilation factor (0.0-1.0)
  def calculate_time_dilation(body, system_id)
    return 1.0 if body.nil? || system_id.nil?

    # Get local stellar time dilation from body data
    # This already accounts for the body's local gravitational field
    local_dilation = body['dilation'] || body[:dilation] || 1.0

    # Calculate black hole time dilation based on system's position in galaxy
    system = find_system(system_id)
    return local_dilation unless system

    black_hole_dilation = calculate_black_hole_dilation(system.x, system.y)

    # Combine both effects (multiplicative - dual reference frames)
    # Total dilation = local stellar effect × galaxy black hole effect
    combined_dilation = local_dilation * black_hole_dilation

    combined_dilation
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
        body1['x'] || body1[:x] || 0,
        body1['y'] || body1[:y] || 0,
        body2['x'] || body2[:x] || 0,
        body2['y'] || body2[:y] || 0
      )
    end

    # Different systems: transform to galaxy coordinates
    system_1 = find_system(system_id_1)
    system_2 = find_system(system_id_2)

    return 0.0 unless system_1 && system_2

    # Transform local body coordinates to galaxy coordinates
    # galaxy_x = system.x + body.x, galaxy_y = system.y + body.y
    body1_galaxy_x = system_1.x + (body1['x'] || body1[:x] || 0)
    body1_galaxy_y = system_1.y + (body1['y'] || body1[:y] || 0)
    body2_galaxy_x = system_2.x + (body2['x'] || body2[:x] || 0)
    body2_galaxy_y = system_2.y + (body2['y'] || body2[:y] || 0)

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
  # @return [Float] Signal delay time
  def calculate_signal_delay(distance)
    return 0.0 if distance <= 0

    # Signal delay = distance / speed of light
    distance / C.to_f
  rescue => e
    Rails.logger.error("Failed to calculate signal delay: #{e.message}")
    0.0
  end

  # Calculate meeting statistics for participants across multiple systems
  # Returns average duration and average signal delay accounting for all relativistic effects
  #
  # @param participants_with_systems [Array<Hash>] Array of {body: Hash, system_id: String/Integer}
  # @return [Hash] { avg_duration: Float, avg_delay: Float }
  def calculate_meeting_statistics(participants_with_systems)
    return { avg_duration: 0.0, avg_delay: 0.0 } if participants_with_systems.blank?

    local_durations = []
    distances = []

    # Calculate local duration for each participant (accounting for time dilation)
    participants_with_systems.each do |participant|
      body = participant[:body] || participant['body']
      system_id = participant[:system_id] || participant['system_id']

      next if body.nil? || system_id.nil?

      # Calculate total time dilation (local + black hole)
      dilation = calculate_time_dilation(body, system_id)

      # Local duration = universal duration × dilation factor
      # If dilation is 0.99, time passes slower, so local duration is less
      local_durations << dilation
    end

    # Calculate pairwise distances for all participants
    participants_with_systems.combination(2).each do |p1, p2|
      body1 = p1[:body] || p1['body']
      system_id_1 = p1[:system_id] || p1['system_id']
      body2 = p2[:body] || p2['body']
      system_id_2 = p2[:system_id] || p2['system_id']

      next if body1.nil? || system_id_1.nil? || body2.nil? || system_id_2.nil?

      distance = calculate_body_to_body_distance(body1, system_id_1, body2, system_id_2)
      distances << distance
    end

    # Calculate averages
    avg_duration = if local_durations.any?
                     local_durations.sum / local_durations.size.to_f
                   else
                     1.0
                   end

    avg_delay = if distances.any?
                  distances.map { |d| calculate_signal_delay(d) }.sum / distances.size.to_f
                else
                  0.0
                end

    {
      avg_duration: avg_duration.round(6),
      avg_delay: avg_delay.round(6)
    }
  rescue => e
    Rails.logger.error("Failed to calculate meeting statistics: #{e.message}")
    { avg_duration: 1.0, avg_delay: 0.0 }
  end

  private

  # Load galaxy data from file
  # @return [Hash] Galaxy data with black hole configuration
  def load_galaxy_data
    galaxy_file = Rails.root.join('data', 'galaxy_data.json')
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
      'name' => 'Sagittarius Omega',
      'mass' => 8.2e36,
      'x' => GALAXY_CENTER_X,
      'y' => GALAXY_CENTER_Y,
      'type' => 'black_hole'
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

    # Fallback: try to find by name or slug if system_id is a string
    if system_id.is_a?(String)
      System.find_by(name: system_id) || System.find_by(json_file_path: "data/systems/#{system_id}.json")
    else
      nil
    end
  rescue => e
    Rails.logger.error("Failed to find system #{system_id}: #{e.message}")
    nil
  end

  # Calculate time dilation from black hole at given position
  # Uses gravitational time dilation formula: sqrt(1 + 2*Φ/c²)
  #
  # @param system_x [Float] System X coordinate in galaxy
  # @param system_y [Float] System Y coordinate in galaxy
  # @return [Float] Black hole time dilation factor
  def calculate_black_hole_dilation(system_x, system_y)
    return 1.0 unless @black_hole

    bh_x = @black_hole['x'] || GALAXY_CENTER_X
    bh_y = @black_hole['y'] || GALAXY_CENTER_Y
    bh_mass = @black_hole['mass'] || 8.2e36

    # Calculate distance from system to black hole center
    distance = euclidean_distance(system_x, system_y, bh_x, bh_y)

    # Prevent division by zero (system at black hole center)
    return 0.0 if distance < 1

    # Calculate gravitational potential from black hole at this distance
    # Convert distance to meters (assume 1 coordinate unit = 1,000,000 meters)
    distance_meters = distance * 1_000_000

    # Φ = -GM/r
    potential = -GRAVITATIONAL_CONSTANT * bh_mass / distance_meters

    # Time dilation factor: sqrt(1 + 2*Φ/c²)
    dilation = Math.sqrt(1 + 2 * potential / (C**2))

    # Clamp to valid range [0, 1]
    [[dilation, 0.0].max, 1.0].min
  rescue => e
    Rails.logger.error("Failed to calculate black hole dilation: #{e.message}")
    1.0 # Fallback to no dilation
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
