# frozen_string_literal: true

# Controller for galaxy view and system management
# Handles CRUD operations for solar systems and displays galaxy map
class GalaxyController < ApplicationController
  before_action :set_system, only: [ :show_system, :edit_system, :update_system, :destroy_system, :regenerate_system ]
  # The four core systems are permanent: no editing, regenerating or deleting
  before_action :protect_core_system, only: [ :edit_system, :update_system, :destroy_system, :regenerate_system ]

  # GET /galaxy
  # Display galaxy map with all systems
  def index
    @galaxy_data = load_galaxy_data
    @systems = System.order(:id) # same order as the system colours and dashboard pills

    # Black-hole time dilation per system (keyed by FILE id, like the map
    # markers) for the landing-map clocks — computed here so the physics
    # stays in RelativisticCalculator instead of being re-derived in JS
    calculator = RelativisticCalculator.new(galaxy_data: @galaxy_data)
    @system_dilations = (@galaxy_data["systems"] || []).to_h do |system|
      [ system["id"], calculator.calculate_black_hole_dilation(system["x"].to_f, system["y"].to_f).round(6) ]
    end

    # System profiles for the slide-in panel (formerly the Přehled page) and
    # the time chart in the story below the map. Built through `helpers`
    # because the data helpers use view helpers (system colours, km formatting).
    @profiles = helpers.galaxy_system_profiles
    @galaxy_time_chart = helpers.galaxy_time_chart_data
    @meetings_count = Meeting.count
    @black_hole = helpers.black_hole_profile(@galaxy_data, @profiles)

    # Generate galaxy SVG if it doesn't exist or is outdated
    generate_galaxy_svg_if_needed

    # Load galaxy SVG content for embedding in view
    @galaxy_svg = File.read(GalaxyService.galaxy_svg_path) rescue nil

    respond_to do |format|
      format.html
      format.json { render json: { galaxy: @galaxy_data, systems: @systems } }
    end
  end

  # GET /galaxy/systems
  # "Soustavy": every system with its key facts, nearest to the black hole
  # first, plus the way to add another one
  def systems
    @galaxy_data = load_galaxy_data
    @profiles = helpers.galaxy_system_profiles.sort_by { |profile| profile[:distance] }
  end

  # GET /galaxy/systems/:id
  # Display specific system's details and visualization
  def show_system
    unless @system
      redirect_to galaxy_index_path, alert: "Soustava nebyla nalezena."
      return
    end

    @system_data = @system.load_system_data

    unless @system_data
      redirect_to galaxy_index_path, alert: "Data soustavy se nepodařilo načíst."
      return
    end

    # Generate system SVG if needed
    generate_system_svg_if_needed(@system)

    # Load system SVG content for embedding in view (path is sanitized)
    svg_path = GalaxyService.system_svg_path(@system.system_id)
    @system_svg = svg_path && File.exist?(svg_path) ? File.read(svg_path) : nil

    @bodies = @system_data["bodies"] || []
    # Same profile as the landing panel (inhabitants, relations, meetings)
    @profile = helpers.galaxy_system_profiles.find { |profile| profile[:system].id == @system.id }

    respond_to do |format|
      format.html
      format.json { render json: { system: @system, data: @system_data } }
    end
  end

  # GET /galaxy/systems/new
  # Show form for creating a new system
  def new
    @system = System.new
    prepare_new_form
  end

  # POST /galaxy/systems
  # Handle system creation (triggers background job for generation)
  def create
    # Generate unique system ID
    system_id = SecureRandom.uuid

    # Extract and validate parameters
    system_params_hash = system_params
    name = system_params_hash[:name]
    x = system_params_hash[:x].to_f
    y = system_params_hash[:y].to_f
    num_planets = system_params_hash[:num_planets]&.to_i || 5
    max_moons = system_params_hash[:max_moons_per_planet]&.to_i || 2
    custom_bodies = system_params_hash[:custom_bodies]

    # Security: Validate numeric parameters
    validation_errors = validate_numeric_parameters(num_planets, max_moons)
    if validation_errors.any?
      Rails.logger.warn("System creation failed - numeric validation errors: #{validation_errors.join(', ')} | Name: #{name} | Params: #{num_planets} planets, #{max_moons} moons")
      flash.now[:alert] = "Neplatné parametry: #{validation_errors.join(', ')}"
      @system = System.new(name: name, x: x, y: y)
      prepare_new_form
      render :new, status: :unprocessable_entity and return
    end

    # Validate position using GalaxyService
    validation = GalaxyService.validate_system_position(x, y)
    unless validation[:valid]
      Rails.logger.warn("System creation failed - position validation errors: #{validation[:errors].join(', ')} | Name: #{name} | Position: (#{x}, #{y})")
      flash.now[:alert] = "Neplatná pozice: #{validation[:errors].join(', ')}"
      @system = System.new(name: name, x: x, y: y)
      prepare_new_form
      render :new, status: :unprocessable_entity and return
    end

    # Create System database record first (job will populate data)
    @system = System.new(
      name: name,
      x: x,
      y: y,
      json_file_path: "data/systems/#{system_id}.json"
    )

    if @system.save
      begin
        # Trigger background job for system generation (async)
        GenerateSystemJob.perform_later(
          system_id: system_id,
          system_name: name,
          system_x: x,
          system_y: y,
          num_planets: num_planets,
          max_moons: max_moons,
          custom_bodies: custom_bodies
        )

        # Security: Log system creation
        log_security_event("System creation started (async): #{name} (ID: #{system_id}) at (#{x}, #{y})")

        # Redirect immediately with status message
        redirect_to galaxy_index_path, notice: "Soustava #{name} právě vzniká. Za chvíli ji uvidíte na mapě galaxie."
      rescue => e
        @system.destroy
        Rails.logger.error("Failed to enqueue system generation job: #{e.message}\n#{e.backtrace.join("\n")}")
        flash.now[:alert] = "Chyba při spuštění generování systému: #{e.message}"
        prepare_new_form
        render :new, status: :unprocessable_entity
      end
    else
      Rails.logger.error("System creation failed - database save errors: #{@system.errors.full_messages.join(', ')} | Name: #{name} | Position: (#{x}, #{y})")
      flash.now[:alert] = "Nepodařilo se uložit systém: #{@system.errors.full_messages.join(', ')}"
      prepare_new_form
      render :new, status: :unprocessable_entity
    end
  end

  # GET /galaxy/systems/:id/edit
  # Show form for editing an existing system
  def edit_system
    unless @system
      redirect_to galaxy_index_path, alert: "Soustava nebyla nalezena."
      return
    end

    @system_data = @system.load_system_data
    @galaxy_data = load_galaxy_data
  end

  # PATCH/PUT /galaxy/systems/:id
  # Handle system updates
  def update_system
    unless @system
      redirect_to galaxy_index_path, alert: "Soustava nebyla nalezena."
      return
    end

    old_x = @system.x
    old_y = @system.y
    system_params_hash = system_params

    # Validate new position if coordinates changed
    new_x = system_params_hash[:x].to_f
    new_y = system_params_hash[:y].to_f

    if new_x != old_x || new_y != old_y
      system_id = @system.system_id
      validation = GalaxyService.validate_system_position(new_x, new_y, exclude_system_id: system_id)
      unless validation[:valid]
        Rails.logger.warn("System update failed - position validation errors: #{validation[:errors].join(', ')} | System: #{@system.name} (ID: #{system_id}) | New position: (#{new_x}, #{new_y})")
        flash.now[:alert] = "Neplatná pozice: #{validation[:errors].join(', ')}"
        @system_data = @system.load_system_data
        @galaxy_data = load_galaxy_data
        render :edit_system and return
      end
    end

    # Update system record (only real model attributes — num_planets and
    # max_moons_per_planet are generation parameters, not columns)
    if @system.update(system_params_hash.slice(:name, :x, :y))
      # If position changed, update galaxy_data.json
      if new_x != old_x || new_y != old_y
        system_id = @system.system_id
        unless GalaxyService.add_system(system_id, new_x, new_y)
          # Rollback database changes if galaxy_data.json update fails
          Rails.logger.error("System update failed - galaxy_data.json update failed | System: #{@system.name} (ID: #{system_id}) | Position: (#{new_x}, #{new_y}) | Rolled back to: (#{old_x}, #{old_y})")
          @system.update_columns(x: old_x, y: old_y)
          flash.now[:alert] = "Nepodařilo se aktualizovat pozici v galaxii. Změny byly vráceny."
          @system_data = @system.load_system_data
          @galaxy_data = load_galaxy_data
          render :edit_system and return
        end
      end

      # Regenerate SVGs (lightweight, can stay sync)
      system_id = @system.system_id
      generate_system_svg(@system)
      generate_galaxy_svg

      # Invalidate caches
      GalaxyService.clear_system_cache(system_id)
      GalaxyService.invalidate_used_names_cache
      GalaxyService.invalidate_system_meeting_stats(system_id)
      GalaxyService.update_svg_timestamp(:system, system_id: system_id)
      GalaxyService.update_svg_timestamp(:galaxy)

      redirect_to galaxy_system_path(@system), notice: "Soustava #{@system.name} je upravená."
    else
      Rails.logger.error("System update failed - database save errors: #{@system.errors.full_messages.join(', ')} | System: #{@system.name} (ID: #{@system.system_id})")
      @system_data = @system.load_system_data
      @galaxy_data = load_galaxy_data
      flash.now[:alert] = "Nepodařilo se aktualizovat systém: #{@system.errors.full_messages.join(', ')}"
      render :edit_system
    end
  end

  # DELETE /galaxy/systems/:id
  # Delete a system
  def destroy_system
    unless @system
      redirect_to galaxy_index_path, alert: "Soustava nebyla nalezena."
      return
    end

    system_name = @system.name
    system_id = @system.system_id

    begin
      # Delete database record (before_destroy callbacks clean up the data
      # files and the galaxy_data.json entry)
      @system.destroy

      # Regenerate galaxy SVG
      generate_galaxy_svg

      # Invalidate caches
      GalaxyService.clear_system_cache(system_id)
      GalaxyService.invalidate_used_names_cache
      GalaxyService.invalidate_system_meeting_stats(system_id)
      GalaxyService.update_svg_timestamp(:galaxy)

      # Security: Log system deletion
      log_security_event("System deleted: #{system_name} (ID: #{system_id})")

      redirect_to galaxy_index_path, notice: "Soustava #{system_name} byla smazána."
    rescue => e
      Rails.logger.error("Failed to delete system: #{e.message}\n#{e.backtrace.join("\n")}")
      redirect_to galaxy_index_path, alert: "Soustavu se nepodařilo smazat: #{e.message}"
    end
  end

  # POST /galaxy/systems/:id/regenerate
  # Regenerate system with new parameters (triggers background job)
  def regenerate_system
    unless @system
      redirect_to galaxy_index_path, alert: "Soustava nebyla nalezena."
      return
    end

    # Security: Use strong parameters for regeneration params
    regenerate_params_hash = regenerate_params
    num_planets = regenerate_params_hash[:num_planets]&.to_i || 5
    max_moons = regenerate_params_hash[:max_moons_per_planet]&.to_i || 2
    custom_bodies = regenerate_params_hash[:custom_bodies]

    begin
      # Trigger background job for regeneration (async)
      RegenerateSystemJob.perform_later(
        system_id: @system.id,
        num_planets: num_planets,
        max_moons: max_moons,
        custom_bodies: custom_bodies
      )

      Rails.logger.info("System regeneration job enqueued for #{@system.name} (ID: #{@system.system_id})")

      redirect_to galaxy_system_path(@system), notice: "Soustava #{@system.name} se přegenerovává. Za chvíli obnovte stránku."
    rescue => e
      Rails.logger.error("Failed to enqueue regeneration job: #{e.message}\n#{e.backtrace.join("\n")}")
      redirect_to galaxy_system_path(@system), alert: "Přegenerování soustavy se nepodařilo spustit: #{e.message}"
    end
  end

  private

  # Set system from params. Accepts either the database id (numeric, used by
  # links in views) or the system's file id (UUID/slug, used by the SVG map
  # markers whose data comes from galaxy_data.json).
  def set_system
    @system = find_system_record(params[:id])
  end

  def protect_core_system
    return unless @system&.core?

    redirect_to galaxy_system_path(@system), alert: "#{@system.name} patří mezi čtyři stálé soustavy galaxie, ty měnit ani mazat nelze."
  end

  def find_system_record(param)
    return System.find_by(id: param) if param.to_s.match?(/\A\d+\z/)

    file_id = GalaxyService.sanitize_system_id(param)
    file_id ? System.find_by(json_file_path: "data/systems/#{file_id}.json") : nil
  end

  # Strong parameters for system
  def system_params
    permitted = params.require(:system).permit(
      :name, :x, :y, :num_planets, :max_moons_per_planet,
      custom_bodies: [ :type, :name, :x, :y, :radius, :density, :mass ]
    )

    # Security: Validate custom_bodies if present
    if permitted[:custom_bodies].present?
      validation_result = validate_custom_bodies(permitted[:custom_bodies])
      unless validation_result[:valid]
        Rails.logger.warn("Security: Invalid custom_bodies rejected: #{validation_result[:error]}")
        permitted.delete(:custom_bodies)
      end
    end

    permitted
  rescue ActionController::ParameterMissing
    {}
  end

  # Strong parameters for system regeneration
  def regenerate_params
    permitted = params.permit(
      :num_planets,
      :max_moons_per_planet,
      custom_bodies: [ :type, :name, :x, :y, :radius, :density, :mass ]
    )

    # Security: Validate custom_bodies if present
    if permitted[:custom_bodies].present?
      validation_result = validate_custom_bodies(permitted[:custom_bodies])
      unless validation_result[:valid]
        Rails.logger.warn("Security: Invalid custom_bodies rejected in regeneration: #{validation_result[:error]}")
        permitted.delete(:custom_bodies)
      end
    end

    permitted
  end

  # Load galaxy data from file
  def load_galaxy_data
    GalaxyService.load_galaxy_data
  rescue => e
    Rails.logger.error("Failed to load galaxy data: #{e.message}")
    { "black_hole" => {}, "systems" => [] }
  end

  # Set up everything the new-system form needs (also used when re-rendering
  # after validation failures so the position mini-map keeps working)
  def prepare_new_form
    @systems = System.all
    @suggested_position = suggest_system_position

    galaxy_svg_path = GalaxyService.galaxy_svg_path
    @galaxy_svg = File.exist?(galaxy_svg_path) ? File.read(galaxy_svg_path) : nil
  end

  # Suggest a valid system position (simple algorithm)
  def suggest_system_position
    # Start with a random position in safe zone
    attempts = 0
    max_attempts = 50

    loop do
      attempts += 1
      # Generate position in safe zone (150-650)
      x = rand(150..650)
      y = rand(150..650)

      validation = GalaxyService.validate_system_position(x, y)
      return { x: x, y: y } if validation[:valid]

      break if attempts >= max_attempts
    end

    # Fallback if no position found
    { x: 300, y: 300 }
  end

  # Generate galaxy SVG if needed (self-heals a missing galaxy_data.json)
  def generate_galaxy_svg_if_needed
    svg_path = GalaxyService.galaxy_svg_path
    galaxy_data_path = GalaxyService.galaxy_data_path

    GalaxyService.rebuild_galaxy_data! unless File.exist?(galaxy_data_path)

    # Regenerate if SVG doesn't exist or is older than galaxy data
    if !File.exist?(svg_path) || (File.exist?(galaxy_data_path) && File.mtime(svg_path) < File.mtime(galaxy_data_path))
      generate_galaxy_svg
    end
  end

  # Generate galaxy SVG
  def generate_galaxy_svg
    begin
      GalaxyVisualizer.generate
      GalaxyService.update_svg_timestamp(:galaxy)
      Rails.logger.info("Galaxy SVG generated successfully")
    rescue => e
      Rails.logger.error("Failed to generate galaxy SVG: #{e.message}")
    end
  end

  # Generate system SVG if needed
  def generate_system_svg_if_needed(system)
    svg_path = GalaxyService.system_svg_path(system.system_id)
    data_path = system.data_file_path
    return unless svg_path && data_path

    # Regenerate if SVG doesn't exist or is older than data
    if !File.exist?(svg_path) || (File.exist?(data_path) && File.mtime(svg_path) < File.mtime(data_path))
      generate_system_svg(system)
    end
  end

  # Generate system SVG
  def generate_system_svg(system)
    begin
      data_path = system.data_file_path

      if data_path && File.exist?(data_path)
        PlanetarySystem.generate(
          json_path: data_path.to_s,
          system_id: system.system_id
        )
        Rails.logger.info("System SVG generated for #{system.system_id}")
      end
    rescue => e
      Rails.logger.error("Failed to generate system SVG: #{e.message}")
    end
  end


  # Security: Validate numeric parameters for system generation
  # @param num_planets [Integer] Number of planets
  # @param max_moons [Integer] Maximum moons per planet
  # @return [Array<String>] Array of error messages (empty if valid)
  def validate_numeric_parameters(num_planets, max_moons)
    errors = []

    # Validate num_planets (must be integer 1-10)
    unless num_planets.is_a?(Integer) && num_planets.between?(1, 10)
      errors << "Počet planet musí být celé číslo mezi 1 a 10"
      Rails.logger.warn("Security: Invalid num_planets: #{num_planets}")
    end

    # Validate max_moons (must be integer 0-5)
    unless max_moons.is_a?(Integer) && max_moons.between?(0, 5)
      errors << "Maximální počet měsíců musí být celé číslo mezi 0 a 5"
      Rails.logger.warn("Security: Invalid max_moons: #{max_moons}")
    end

    errors
  end

  # Security: Log security-relevant events
  # @param message [String] Event description
  def log_security_event(message)
    Rails.logger.info("SECURITY EVENT: #{message} | IP: #{request.remote_ip} | User-Agent: #{request.user_agent}")
  end

  # Security: Validate custom body parameters
  # @param custom_bodies [Array<Hash>] Array of custom body specifications
  # @return [Hash] { valid: Boolean, error: String }
  def validate_custom_bodies(custom_bodies)
    # Must be an array
    unless custom_bodies.is_a?(Array)
      return { valid: false, error: "Custom bodies must be an array" }
    end

    # Limit number of custom bodies (max 20 to prevent DOS)
    if custom_bodies.size > 20
      Rails.logger.warn("Security: Too many custom bodies: #{custom_bodies.size}")
      return { valid: false, error: "Too many custom bodies (max 20)" }
    end

    # Validate each body
    custom_bodies.each_with_index do |body, index|
      # Must be a hash
      unless body.is_a?(Hash) || body.is_a?(ActionController::Parameters)
        return { valid: false, error: "Custom body #{index + 1} must be a hash" }
      end

      body_hash = body.is_a?(ActionController::Parameters) ? body.to_h : body

      # Validate type
      unless %w[star planet moon].include?(body_hash["type"].to_s)
        Rails.logger.warn("Security: Invalid body type: #{body_hash['type']}")
        return { valid: false, error: "Invalid type for body #{index + 1}" }
      end

      # Validate numeric parameters with realistic ranges
      if body_hash["mass"].present?
        mass = body_hash["mass"].to_f
        # Security: Reject NaN, Infinity, negative, or out-of-range values
        # Mass: 1e20 to 1e40 kg (moon to large star)
        unless mass.finite? && mass.positive? && mass.between?(1e20, 1e40)
          Rails.logger.warn("Security: Invalid mass: #{mass}")
          return { valid: false, error: "Invalid mass for body #{index + 1} (must be 1e20-1e40)" }
        end
      end

      if body_hash["radius"].present?
        radius = body_hash["radius"].to_f
        # Security: Reject NaN, Infinity, negative, or out-of-range values
        # Radius: 100km to 1,000,000km
        unless radius.finite? && radius.positive? && radius.between?(100_000, 1_000_000_000)
          Rails.logger.warn("Security: Invalid radius: #{radius}")
          return { valid: false, error: "Invalid radius for body #{index + 1} (must be 1e5-1e9 m)" }
        end
      end

      if body_hash["density"].present?
        density = body_hash["density"].to_f
        # Security: Reject NaN, Infinity, negative, or out-of-range values
        # Density: 500 to 20,000 kg/m³ (gas to metal)
        unless density.finite? && density.positive? && density.between?(500, 20_000)
          Rails.logger.warn("Security: Invalid density: #{density}")
          return { valid: false, error: "Invalid density for body #{index + 1} (must be 500-20000 kg/m³)" }
        end
      end

      # Validate coordinates (0-800 range)
      if body_hash["x"].present?
        x = body_hash["x"].to_f
        # Security: Reject NaN, Infinity, negative, or out-of-range values
        unless x.finite? && x >= 0 && x.between?(0, 800)
          Rails.logger.warn("Security: Invalid x coordinate: #{x}")
          return { valid: false, error: "Invalid x coordinate for body #{index + 1} (must be 0-800)" }
        end
      end

      if body_hash["y"].present?
        y = body_hash["y"].to_f
        # Security: Reject NaN, Infinity, negative, or out-of-range values
        unless y.finite? && y >= 0 && y.between?(0, 800)
          Rails.logger.warn("Security: Invalid y coordinate: #{y}")
          return { valid: false, error: "Invalid y coordinate for body #{index + 1} (must be 0-800)" }
        end
      end
    end

    { valid: true }
  end
end
