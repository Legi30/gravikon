# frozen_string_literal: true

require "json"
require "securerandom"
require "fileutils"

# Load OrbitValidator if running from Rails context
if defined?(Rails)
  require_relative "../app/validators/orbit_validator"
end

# Object-oriented system generator for creating solar systems
# Can be used from Rails controllers, jobs, and command line
class SystemGenerator
  STAR_POSITION = [ PhysicsConstants::SYSTEM_LOCAL_CENTER, PhysicsConstants::SYSTEM_LOCAL_CENTER ].freeze

  # Name lists (expanded in T001)
  PLANET_NAMES = %w[
    Plaxer Plomur Plaven Plirion Plintar Ploxis Plador Plenor Plurion Plarkon
    Plexor Plidon Pluvox Plareth Plynor Plixar Plomera Plathon Pluven Plirax
    Pledor Plyntar Plomix Plavion Plexis Plorax Plunex Plarion Plexith Plomoth
    Plavex Pliroth Plynex Plodar Plexara Plivor Plometh Plavor Plixon Plorath
    Plexur Plivon Plynara Plyxis Plethon Plarox Pluvith Plirdon Plexion Plomara
    Plivex Plynoth Plirex Plathor Pluvora Plixeth Plomath Plyreth Plexon Plydon
  ].freeze

  MOON_NAMES = %w[
    Morish Morex Molan Morthax Mobin Morlun Mozer Morlux Mochar Morlon
    Moreth Movix Molix Morthon Mobex Morlith Mozara Morvin Mochex Morion
    Movex Molith Morthex Mobor Morlax Mozeth Morlix Mochor Morleth Morvan
    Movith Molax Morthix Mobeth Morlyx Mozor Morvex Mochon Moryx Movon
    Moleth Morthox Mobix Mozix Morvon Mychor Morax Movax Molox Morthyx
    Mobath Morlion Morvix Mochyx Morlan Morven Movyx Morthan Mobyon Morlox
  ].freeze

  STAR_NAMES = %w[
    Stelaris Starnox Stavor Sturion Steldor Stalius Starnith Storgath Stelvor
    Starnex Stavion Sturox Steldex Stalion Starneth Storgix Stelion Starnath
    Stavex Sturith Steldox Stalux Styrox Storgeth Stelox Starlix Stavon Sturix
    Steldion Staleth Storgon Steleth Starnyx Stavox Stureth Steldith Stalor
    Styrneth Storgex Stelux Starlux Stavith Styldax Stylar Starnax Stelith
    Styrnex Stavyon Styrion Steldyx Stalyx Storgion Stelax Starlon Stavyx
    Sturyth Staldor Stalyth Styrgath Stelvon Starnix Stylor Sturgix Stelmax
  ].freeze

  # Binary systems: the two stars circle their common centre (the system's
  # local origin) at this distance each, so the pair spans 72 000 km and the
  # first circumbinary planet orbit (>= 90 units) stays clear of both.
  BINARY_STAR_OFFSET = 36

  attr_reader :system_id, :system_name, :system_x, :system_y, :num_planets, :max_moons_per_planet
  attr_reader :custom_bodies, :binary, :errors

  # Initialize generator with parameters
  # @param system_id [String] Unique identifier for the system (UUID or slug)
  # @param system_name [String] Display name for the system
  # @param system_x [Float] X position in galaxy (optional, for validation)
  # @param system_y [Float] Y position in galaxy (optional, for validation)
  # @param num_planets [Integer] Number of planets (1-10)
  # @param max_moons_per_planet [Integer] Maximum moons per planet (0-5)
  # @param custom_bodies [Array<Hash>] Optional custom body definitions
  # @param binary [Boolean] Two stars orbiting the system centre instead of one
  def initialize(system_id:, system_name: nil, system_x: nil, system_y: nil,
                 num_planets: 5, max_moons_per_planet: 2, custom_bodies: nil, binary: false)
    @system_id = system_id
    @system_name = system_name || "System #{system_id}"
    @system_x = system_x
    @system_y = system_y
    @num_planets = num_planets.to_i
    @max_moons_per_planet = max_moons_per_planet.to_i
    @custom_bodies = custom_bodies
    @binary = binary
    @errors = []
    @used_names = []
  end

  # Generate the solar system
  # Bodies store only their LOCAL surface dilation — the black hole's
  # contribution is applied at calculation time by RelativisticCalculator,
  # so moving a system never stales its data.
  # @return [Hash, nil] Generated system data or nil on error
  def generate
    # Validate parameters
    return nil unless validate_parameters

    # Check for name collisions across existing systems
    load_used_names_from_existing_systems

    bodies = if @custom_bodies
               generate_custom_system
    else
               generate_random_system
    end

    return nil if bodies.nil?

    {
      system_id: @system_id,
      system_name: @system_name,
      bodies: bodies
    }
  rescue => e
    @errors << "Chyba při generování systému: #{e.message}"
    log_error("SystemGenerator error: #{e.message}\n#{e.backtrace.join("\n")}")
    nil
  end

  # Generate and save the system to file
  # @return [Boolean] Success status
  def generate_and_save
    data = generate
    return false unless data

    output_path = GalaxyService.system_data_path(@system_id)

    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(output_path))

    # Save to file
    File.write(output_path, JSON.pretty_generate(data))
    log_info("System #{@system_id} saved to #{output_path}")

    true
  rescue => e
    @errors << "Chyba při ukládání systému: #{e.message}"
    log_error("Failed to save system: #{e.message}")
    false
  end

  # Class method to generate a random system (for convenience)
  # @param system_id [String] System ID
  # @param options [Hash] Generation options
  # @return [Hash, nil] Generated system data
  def self.generate_random(system_id, **options)
    generator = new(system_id: system_id, **options)
    generator.generate
  end

  # Class method to generate and save a random system
  # @param system_id [String] System ID
  # @param options [Hash] Generation options
  # @return [Boolean] Success status
  def self.generate_and_save(system_id, **options)
    generator = new(system_id: system_id, **options)
    generator.generate_and_save
  end

  private

  # Validate generation parameters
  # @return [Boolean] Validation success
  def validate_parameters
    valid = true

    unless @num_planets.between?(1, 10)
      @errors << "Počet planet musí být mezi 1 a 10 (zadáno: #{@num_planets})"
      valid = false
    end

    unless @max_moons_per_planet.between?(0, 5)
      @errors << "Maximální počet měsíců musí být mezi 0 a 5 (zadáno: #{@max_moons_per_planet})"
      valid = false
    end

    # Validate system position if provided (using GalaxyService)
    if @system_x && @system_y
      if defined?(GalaxyService)
        validation = GalaxyService.validate_system_position(@system_x, @system_y, exclude_system_id: @system_id)
        unless validation[:valid]
          @errors.concat(validation[:errors])
          valid = false
        end
      end
    end

    valid
  end

  # Load names already used in existing systems
  def load_used_names_from_existing_systems
    systems_dir = GalaxyService.systems_data_dir
    return unless Dir.exist?(systems_dir)

    Dir.glob(File.join(systems_dir, "*.json")).each do |file|
      # Skip the current system being regenerated
      next if file.include?("#{@system_id}.json")

      begin
        data = JSON.parse(File.read(file))
        data["bodies"]&.each do |body|
          @used_names << body["name"] if body["name"]
        end
      rescue => e
        log_warn("Failed to load names from #{file}: #{e.message}")
      end
    end
  end

  # Generate random solar system
  # @return [Array<Hash>] Array of celestial bodies
  def generate_random_system
    bodies = []

    # Generate the star (or the binary pair). Planets orbit the system
    # centre, which is the star itself or the binary's common centre.
    stars = @binary ? generate_binary_stars : [ generate_star ]
    bodies.concat(stars)
    star = { x: STAR_POSITION[0], y: STAR_POSITION[1] }

    # Generate planets and their moons
    @num_planets.times do |i|
      # Pass existing bodies for collision detection
      planet = generate_planet(i, star, bodies)
      bodies << planet

      # Generate moons for this planet
      rand(0..@max_moons_per_planet).times do |j|
        # Pass existing bodies for collision detection
        moon = generate_moon(j, planet, bodies)
        bodies << moon
      end
    end

    bodies
  end

  # Generate custom solar system from provided specifications
  # @return [Array<Hash>] Array of celestial bodies
  def generate_custom_system
    bodies = []

    @custom_bodies.each do |body_spec|
      body = generate_custom_body(body_spec)
      bodies << body if body
    end

    bodies
  end

  # Generate a star
  # @return [Hash] Star data
  def generate_star
    star_radius = rand(50_000_000..100_000_000)
    star_density = rand(1000..2000)
    star_mass = calculate_mass(star_radius, star_density)

    {
      name: random_name(STAR_NAMES),
      type: "star",
      x: STAR_POSITION[0],
      y: STAR_POSITION[1],
      radius: star_radius,
      density: star_density,
      mass: star_mass,
      # The star is the system's local reference frame
      dilation: 1.0
    }
  end

  # Generate two stars facing each other across the system centre
  # @return [Array<Hash>] Star data, primary first
  def generate_binary_stars
    angle = rand * 2 * Math::PI

    [ 0, Math::PI ].map do |phase|
      star = generate_star
      star.merge(
        x: (STAR_POSITION[0] + BINARY_STAR_OFFSET * Math.cos(angle + phase)).round(2),
        y: (STAR_POSITION[1] + BINARY_STAR_OFFSET * Math.sin(angle + phase)).round(2)
      )
    end
  end

  # Generate a planet
  # @param index [Integer] Planet index
  # @param star [Hash] Parent star data
  # @param existing_bodies [Array<Hash>] Already generated bodies for collision checking
  # @return [Hash] Planet data
  def generate_planet(index, star, existing_bodies = [])
    max_attempts = 50 # Maximum attempts to find valid position
    attempt = 0

    loop do
      attempt += 1

      angle = rand * 2 * Math::PI
      # Spacing shrinks with planet count so the outermost orbit always fits
      # within OrbitValidator::MAX_ORBIT_RADIUS_FROM_STAR (370 units)
      spacing = [ (240.0 / [ @num_planets - 1, 1 ].max).floor, 60 ].min
      distance = 100 + index * spacing + rand(-10..10)
      planet_x = star[:x] + distance * Math.cos(angle)
      planet_y = star[:y] + distance * Math.sin(angle)

      # Validate position if OrbitValidator is available
      if defined?(OrbitValidator)
        validation = OrbitValidator.validate_body_orbit(
          planet_x, planet_y,
          star[:x], star[:y],
          existing_bodies: existing_bodies
        )

        # If position is invalid and we haven't exceeded max attempts, try again
        if !validation[:valid] && attempt < max_attempts
          log_debug("Planet position invalid (attempt #{attempt}): #{validation[:errors].join(', ')}")
          next
        elsif !validation[:valid]
          # Max attempts exceeded - cannot place planet safely
          raise "Could not find valid planet position after #{max_attempts} attempts. Errors: #{validation[:errors].join(', ')}"
        end
      end

      # Position is valid (or validation unavailable)
      planet_radius = rand(1_000_000..4_000_000)
      planet_density = rand(3000..6000)
      planet_mass = calculate_mass(planet_radius, planet_density)

      return {
        name: random_name(PLANET_NAMES),
        type: "planet",
        x: planet_x.round(2),
        y: planet_y.round(2),
        radius: planet_radius,
        density: planet_density,
        mass: planet_mass,
        dilation: PhysicsConstants.surface_dilation(planet_mass, planet_radius)
      }
    end
  end

  # Generate a moon
  # @param index [Integer] Moon index
  # @param planet [Hash] Parent planet data
  # @param existing_bodies [Array<Hash>] Already generated bodies for collision checking
  # @return [Hash] Moon data
  def generate_moon(index, planet, existing_bodies = [])
    max_attempts = 50 # Maximum attempts to find valid position
    attempt = 0

    loop do
      attempt += 1

      angle = rand * 2 * Math::PI
      moon_distance = 20 + index * 15
      moon_x = planet[:x] + moon_distance * Math.cos(angle)
      moon_y = planet[:y] + moon_distance * Math.sin(angle)

      # Validate position if OrbitValidator is available
      if defined?(OrbitValidator)
        validation = OrbitValidator.validate_body_orbit(
          moon_x, moon_y,
          planet[:x], planet[:y],
          existing_bodies: existing_bodies
        )

        # If position is invalid and we haven't exceeded max attempts, try again
        if !validation[:valid] && attempt < max_attempts
          log_debug("Moon position invalid (attempt #{attempt}): #{validation[:errors].join(', ')}")
          next
        elsif !validation[:valid]
          # Max attempts exceeded - cannot place moon safely
          raise "Could not find valid moon position after #{max_attempts} attempts. Errors: #{validation[:errors].join(', ')}"
        end
      end

      # Position is valid (or validation unavailable)
      moon_radius = rand(300_000..800_000)
      moon_density = rand(2500..5000)
      moon_mass = calculate_mass(moon_radius, moon_density)

      return {
        name: random_name(MOON_NAMES),
        type: "moon",
        x: moon_x.round(2),
        y: moon_y.round(2),
        radius: moon_radius,
        density: moon_density,
        mass: moon_mass,
        dilation: PhysicsConstants.surface_dilation(moon_mass, moon_radius)
      }
    end
  end

  # Generate a custom celestial body from specification
  # @param spec [Hash] Body specification
  # @return [Hash] Body data
  def generate_custom_body(spec)
    body_type = spec[:type] || spec["type"]
    name = spec[:name] || spec["name"]

    # Use provided name or generate random one
    name = case body_type
    when "star" then name || random_name(STAR_NAMES)
    when "planet" then name || random_name(PLANET_NAMES)
    when "moon" then name || random_name(MOON_NAMES)
    else name || "Body-#{SecureRandom.hex(4)}"
    end

    radius = (spec[:radius] || spec["radius"] || default_radius_for_type(body_type)).to_f
    density = (spec[:density] || spec["density"] || default_density_for_type(body_type)).to_f
    x = (spec[:x] || spec["x"] || STAR_POSITION[0]).to_f
    y = (spec[:y] || spec["y"] || STAR_POSITION[1]).to_f

    mass = calculate_mass(radius, density)

    {
      name: name,
      type: body_type,
      x: x.round(2),
      y: y.round(2),
      radius: radius,
      density: density,
      mass: mass,
      dilation: body_type == "star" ? 1.0 : PhysicsConstants.surface_dilation(mass, radius)
    }
  end

  # Get random unique name from list
  # @param list [Array<String>] Name list
  # @return [String] Unique name
  def random_name(list)
    available_names = list - @used_names

    if available_names.empty?
      # Fallback: generate unique name with number suffix
      base_name = list.sample
      counter = 1
      name = "#{base_name}-#{counter}"
      while @used_names.include?(name)
        counter += 1
        name = "#{base_name}-#{counter}"
      end
      @used_names << name
      return name
    end

    name = available_names.sample
    @used_names << name
    name
  end

  # Calculate mass from radius and density
  # @param radius [Float] Radius in meters
  # @param density [Float] Density in kg/m³
  # @return [Float] Mass in kg
  def calculate_mass(radius, density)
    volume = (4.0 / 3.0) * Math::PI * radius**3
    volume * density
  end

  # Get default radius for body type
  # @param type [String] Body type
  # @return [Integer] Default radius
  def default_radius_for_type(type)
    case type
    when "star" then 75_000_000
    when "planet" then 2_500_000
    when "moon" then 500_000
    else 1_000_000
    end
  end

  # Get default density for body type
  # @param type [String] Body type
  # @return [Integer] Default density
  def default_density_for_type(type)
    case type
    when "star" then 1500
    when "planet" then 4500
    when "moon" then 3500
    else 3000
    end
  end

  # Log error message (Rails.logger or STDERR)
  # @param message [String] Error message
  def log_error(message)
    if defined?(Rails)
      Rails.logger.error(message)
    else
      STDERR.puts("ERROR: #{message}")
    end
  end

  # Log info message (Rails.logger or STDOUT)
  # @param message [String] Info message
  def log_info(message)
    if defined?(Rails)
      Rails.logger.info(message)
    else
      puts("INFO: #{message}")
    end
  end

  # Log warning message (Rails.logger or STDERR)
  # @param message [String] Warning message
  def log_warn(message)
    if defined?(Rails)
      Rails.logger.warn(message)
    else
      STDERR.puts("WARNING: #{message}")
    end
  end

  # Log debug message (Rails.logger or STDOUT in verbose mode)
  # @param message [String] Debug message
  def log_debug(message)
    if defined?(Rails)
      Rails.logger.debug(message)
    elsif ENV["DEBUG"]
      puts("DEBUG: #{message}")
    end
  end
end
