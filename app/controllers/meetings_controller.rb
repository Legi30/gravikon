# frozen_string_literal: true

class MeetingsController < ApplicationController
  def index
    @meetings = Meeting.includes(:system).all

    # Preload all systems referenced in participant_systems to avoid N+1 queries
    # Extract all unique system IDs from inter-system meetings
    system_ids = @meetings.flat_map do |meeting|
      if meeting.is_inter_system && meeting.participant_systems.present?
        # Parse JSON string to hash
        ps_hash = meeting.participant_systems_hash
        ps_hash.values.compact
      else
        []
      end
    end.uniq

    # Load all referenced systems into a hash for quick lookup in views
    @systems_by_id = System.where(id: system_ids).index_by(&:id)

    # Also load all systems for the filter dropdown
    @systems = System.all

    # Load system data for legacy single-system display (backwards compatibility)
    @system_data = Rails.cache.fetch('system_data') do
      JSON.parse(File.read(Rails.root.join("data/system_data.json")))
    rescue Errno::ENOENT, JSON::ParserError => e
      Rails.logger.error("MeetingsController#index: Failed to load system_data - #{e.message}")
      { "bodies" => [] }  # Return empty structure to prevent crashes
    end
  end

  def new
    @meeting = Meeting.new
    @system_id = params[:system_id]

    if @system_id.present?
      # Load bodies from specific system
      @system = System.find_by(id: @system_id)
      if @system
        @bodies = extract_bodies_from_system(@system_id)
        @meeting.system_id = @system_id
      else
        redirect_to meetings_path, alert: "Systém nebyl nalezen."
        return
      end
    else
      # No system specified - show system selector or use default system
      @systems = System.all
      if @systems.count == 1
        # If only one system exists, use it
        @system = @systems.first
        @bodies = extract_bodies_from_system(@system.id)
        @meeting.system_id = @system.id
      elsif @systems.count > 1
        # Multiple systems - need to select one first
        # Could redirect to a system selector or load from legacy file
        @bodies = extract_bodies_from_system  # Use legacy method
      else
        # No systems exist - fall back to legacy behavior
        @bodies = extract_bodies_from_system
      end
    end
  end

  def new_inter_system
    @meeting = Meeting.new
    @meeting.is_inter_system = true
    @systems = System.all

    if @systems.count < 2
      redirect_to meetings_path, alert: "Pro vytvoření schůzky mezi systémy musí existovat alespoň 2 systémy."
      return
    end

    # Load bodies from all systems, grouped by system
    @systems_with_bodies = extract_bodies_from_multiple_systems(@systems.pluck(:id))
  end

  def create
    @meeting = create_or_update_meeting
    return unless @meeting  # Early return if validation failed and method already redirected

    respond_to do |format|
      format.html { redirect_to meetings_path, notice: "Schůzka naplánována." }
      format.turbo_stream { render turbo_stream: turbo_stream.append("meetings", partial: "meetings/meeting", locals: { meeting: @meeting }) }
    end
  rescue ActiveRecord::RecordInvalid => e
    # Handle validation errors (e.g., participant doesn't exist in specified system)
    Rails.logger.warn("Meeting validation failed: #{e.message}")

    # Determine which form to redirect to based on meeting type
    redirect_path = if params[:participant_systems].present? || (params[:meeting] && params[:meeting][:participant_systems].present?)
                      new_inter_system_meetings_path
                    else
                      new_meeting_path
                    end

    redirect_to redirect_path, alert: "Nelze vytvořit schůzku: #{e.record.errors.full_messages.join(', ')}"
  end

  def edit
    @meeting = Meeting.find(params[:id])

    if @meeting.is_inter_system
      # Inter-system meeting - load all systems with bodies
      @systems = System.all
      @systems_with_bodies = extract_bodies_from_multiple_systems(@systems.pluck(:id))
    elsif @meeting.system_id.present?
      # Single-system meeting with system assigned
      @system = @meeting.system
      @bodies = extract_bodies_from_system(@meeting.system_id)
    else
      # Legacy meeting without system
      @bodies = extract_bodies_from_system
    end
  end

  def update
    @meeting = Meeting.find(params[:id])
    create_or_update_meeting  # vytvoříme nový z dat formuláře
    @meeting.destroy  # smažeme původní záznam
    redirect_to meetings_path, notice: "Schůzka upravena."
  rescue ActiveRecord::RecordInvalid => e
    # Handle validation errors (e.g., participant doesn't exist in specified system)
    Rails.logger.warn("Meeting validation failed on update: #{e.message}")

    # Redirect back to edit form with error
    redirect_to edit_meeting_path(@meeting), alert: "Nelze upravit schůzku: #{e.record.errors.full_messages.join(', ')}"
  end

  def destroy
    @meeting = Meeting.find(params[:id])
    @meeting.destroy

    respond_to do |format|
      format.html { redirect_to meetings_path, notice: "Schůzka smazána." }
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@meeting) }
    end
  end

  private

  # Extract body names from a specific system or legacy file
  # @param system_id [Integer, nil] System ID to load from, or nil for legacy behavior
  # @return [Array<String>] Array of body names
  def extract_bodies_from_system(system_id = nil)
    if system_id.present?
      # Load from specific system's JSON file with caching
      system = System.find_by(id: system_id)
      return [] unless system

      # Use GalaxyService caching for system data
      system_file_id = File.basename(system.json_file_path, '.json')
      system_data = GalaxyService.load_system_data(system_file_id)
      return [] unless system_data

      system_data["bodies"]&.map { |b| b["name"] } || []
    else
      # Legacy behavior - load from data/system_data.json
      system_data = Rails.cache.fetch('system_data') do
        JSON.parse(File.read(Rails.root.join("data/system_data.json")))
      rescue Errno::ENOENT, JSON::ParserError => e
        Rails.logger.error("MeetingsController#extract_bodies_from_system: Failed to load system_data - #{e.message}")
        { "bodies" => [] }
      end
      system_data["bodies"]&.map { |b| b["name"] } || []
    end
  end

  # Extract bodies from multiple systems, grouped by system
  # @param system_ids [Array<Integer>] Array of system IDs
  # @return [Hash] Hash with system_id as key, value is hash with system and bodies array
  def extract_bodies_from_multiple_systems(system_ids)
    result = {}

    system_ids.each do |system_id|
      system = System.find_by(id: system_id)
      next unless system

      # Use GalaxyService caching for system data
      system_file_id = File.basename(system.json_file_path, '.json')
      system_data = GalaxyService.load_system_data(system_file_id)
      next unless system_data

      bodies = system_data["bodies"] || []
      result[system_id] = {
        system: system,
        bodies: bodies
      }
    end

    result
  end

  # Strong parameters - whitelist only permitted attributes
  def meeting_params
    params.require(:meeting).permit(:start_time, :end_time, :topic, :system_id, :is_inter_system)
  rescue ActionController::ParameterMissing
    {}
  end

  # Strong parameters for participants array
  # Security: Use .permit with empty array syntax to allow array of strings
  def participants_params
    if params[:participants].is_a?(Array)
      params.permit(participants: [])[:participants] || []
    elsif params[:meeting] && params[:meeting][:participants].is_a?(Array)
      params.require(:meeting).permit(participants: [])[:participants] || []
    else
      []
    end
  end

  # Strong parameters for participant_systems hash (inter-system meetings)
  # Security: Use .permit to whitelist hash structure
  def participant_systems_params
    if params[:participant_systems].is_a?(Hash)
      # Permit hash with any keys (participant names) but ensure values are simple types
      permitted = params.permit(participant_systems: {})[:participant_systems]
      permitted.is_a?(Hash) ? permitted : nil
    elsif params[:meeting] && params[:meeting][:participant_systems].is_a?(Hash)
      permitted = params.require(:meeting).permit(participant_systems: {})[:participant_systems]
      permitted.is_a?(Hash) ? permitted : nil
    else
      nil
    end
  end

  def create_or_update_meeting
    # Use strong parameters to extract only permitted attributes
    permitted_params = meeting_params
    participants = participants_params
    participant_systems = participant_systems_params

    start_time = permitted_params[:start_time]
    end_time = permitted_params[:end_time]
    topic = permitted_params[:topic] || ""
    system_id = permitted_params[:system_id]
    is_inter_system = permitted_params[:is_inter_system] || false

    # Detect inter-system meeting if participant_systems is provided
    if participant_systems.present? && participant_systems.is_a?(Hash)
      is_inter_system = true
    end

    # Security: Validate participants array
    validation_result = validate_participants_array(participants)
    unless validation_result[:valid]
      redirect_to new_meeting_path, alert: validation_result[:error]
      return
    end

    # Security: Validate participant_systems JSON if present
    if participant_systems.present?
      validation_result = validate_participant_systems_json(participant_systems, participants)
      unless validation_result[:valid]
        redirect_to new_inter_system_meetings_path, alert: validation_result[:error]
        return
      end
    end

    # Validate participants count
    if participants.size < 2
      redirect_to new_meeting_path, alert: "Musíš vybrat alespoň dvě tělesa."
      return
    end

    # Load participant bodies based on meeting type
    if is_inter_system
      # Inter-system meeting: load bodies from multiple systems
      parsed_participants = load_inter_system_participants(participants, participant_systems)
      if parsed_participants.size < 2
        redirect_to new_inter_system_meetings_path, alert: "Nepodařilo se načíst data účastníků."
        return
      end
    else
      # Single-system meeting: load bodies from one system
      if system_id.present?
        system = System.find_by(id: system_id)
        unless system
          redirect_to new_meeting_path, alert: "Systém nebyl nalezen."
          return
        end
        system_data = system.load_system_data
        bodies = system_data ? system_data["bodies"] : []
      else
        # Legacy: load from data/system_data.json
        system_data = Rails.cache.fetch('system_data') do
          JSON.parse(File.read(Rails.root.join("data/system_data.json")))
        rescue Errno::ENOENT, JSON::ParserError => e
          Rails.logger.error("MeetingsController#create_or_update_meeting: Failed to load system_data - #{e.message}")
          { "bodies" => [] }
        end
        bodies = system_data["bodies"]
      end

      parsed_participants = participants.map { |name| find_body(name, bodies) }.compact
      if parsed_participants.size < 2
        redirect_to new_meeting_path, alert: "Musíš vybrat alespoň dvě tělesa."
        return
      end
    end

    # Calculate meeting duration and relativistic effects using RelativisticCalculator
    # This properly accounts for BOTH local stellar gravity AND black hole gravity
    calculator = RelativisticCalculator.new

    # Prepare participants with system information for calculator
    participants_with_systems = if is_inter_system
      # Inter-system meeting: each participant has its own system_id
      parsed_participants.map do |body|
        system_id_for_body = participant_systems[body['name']]
        {
          body: body,
          system_id: system_id_for_body
        }
      end
    else
      # Single-system meeting: all participants share the same system_id
      parsed_participants.map do |body|
        {
          body: body,
          system_id: system_id
        }
      end
    end

    # Use RelativisticCalculator to compute accurate statistics
    # This combines local stellar time dilation with black hole time dilation
    # and calculates signal delays accounting for inter-system distances
    stats = calculator.calculate_meeting_statistics(participants_with_systems)

    avg_duration = stats[:avg_duration]
    avg_delay = stats[:avg_delay]

    # Create meeting with appropriate attributes
    meeting_attrs = {
      start_time: start_time,
      end_time: end_time,
      topic: topic,
      participants: participants.to_json,
      local_avg_duration: avg_duration,
      avg_delay: avg_delay,
      is_inter_system: is_inter_system
    }

    # Add system_id for single-system meetings
    if !is_inter_system && system_id.present?
      meeting_attrs[:system_id] = system_id
    end

    # Add participant_systems for inter-system meetings
    if is_inter_system && participant_systems.present?
      meeting_attrs[:participant_systems] = participant_systems.to_json
    end

    meeting = Meeting.create!(meeting_attrs)

    # Invalidate meeting stats cache for affected system(s)
    if !is_inter_system && system_id.present?
      GalaxyService.invalidate_system_meeting_stats(system_id)
    elsif is_inter_system && participant_systems.present?
      # Invalidate cache for all systems involved in inter-system meeting
      participant_systems.values.uniq.each do |sys_id|
        GalaxyService.invalidate_system_meeting_stats(sys_id)
      end
    end

    meeting
  end

  # Load participants from multiple systems for inter-system meetings
  # @param participants [Array<String>] Array of participant names
  # @param participant_systems [Hash] Mapping of participant names to system IDs
  # @return [Array<Hash>] Array of participant body hashes with their data
  def load_inter_system_participants(participants, participant_systems)
    return [] unless participant_systems.is_a?(Hash)

    parsed_participants = []

    participants.each do |participant_name|
      system_id = participant_systems[participant_name]
      next unless system_id

      system = System.find_by(id: system_id)
      next unless system

      # Use GalaxyService caching for system data
      system_file_id = File.basename(system.json_file_path, '.json')
      system_data = GalaxyService.load_system_data(system_file_id)
      next unless system_data

      body = find_body(participant_name, system_data["bodies"])
      parsed_participants << body if body
    end

    parsed_participants
  end
  

  def find_body(name, bodies)
    bodies.find { |b| b["name"].downcase == name.downcase }
  end

  # Security: Validate participants array structure and size
  # @param participants [Array] Participants array
  # @return [Hash] { valid: Boolean, error: String }
  def validate_participants_array(participants)
    # Check if array
    unless participants.is_a?(Array)
      Rails.logger.warn("Security: Invalid participants - not an array")
      return { valid: false, error: "Neplatná struktura účastníků" }
    end

    # Check size limit (max 50 participants to prevent DOS)
    if participants.size > 50
      Rails.logger.warn("Security: Too many participants: #{participants.size}")
      return { valid: false, error: "Příliš mnoho účastníků (max. 50)" }
    end

    # Check that all participants are strings
    unless participants.all? { |p| p.is_a?(String) }
      Rails.logger.warn("Security: Invalid participant type in array")
      return { valid: false, error: "Neplatná struktura účastníků" }
    end

    # Check JSON size (when serialized)
    json_size = participants.to_json.bytesize
    if json_size > 10_240 # 10KB limit
      Rails.logger.warn("Security: Participants JSON too large: #{json_size} bytes")
      return { valid: false, error: "Data účastníků jsou příliš velká" }
    end

    { valid: true }
  end

  # Security: Validate participant_systems JSON structure and size
  # @param participant_systems [Hash] Participant systems mapping
  # @param participants [Array] Participants array
  # @return [Hash] { valid: Boolean, error: String }
  def validate_participant_systems_json(participant_systems, participants)
    # Check if Hash
    unless participant_systems.is_a?(Hash)
      Rails.logger.warn("Security: Invalid participant_systems - not a hash")
      return { valid: false, error: "participant_systems must be a hash" }
    end

    # Size limit to prevent DOS (max 50 participants)
    if participant_systems.size > 50
      Rails.logger.warn("Security: Too many participant_systems entries: #{participant_systems.size}")
      return { valid: false, error: "Too many participants (max 50)" }
    end

    # Check JSON size (10KB limit to prevent DOS)
    json_size = participant_systems.to_json.bytesize
    if json_size > 10_240
      Rails.logger.warn("Security: participant_systems JSON too large: #{json_size} bytes")
      return { valid: false, error: "Data systémů jsou příliš velká" }
    end

    # Validate structure: keys are strings (names), values are integers (system_ids)
    participant_systems.each do |participant_name, system_id|
      # Key must be string (participant name) with length limit
      unless participant_name.is_a?(String) && participant_name.length <= 100
        Rails.logger.warn("Security: Invalid participant name format: #{participant_name}")
        return { valid: false, error: "Invalid participant name format" }
      end

      # Value must match integer format (system_id)
      unless system_id.to_s.match?(/\A\d+\z/)
        Rails.logger.warn("Security: Invalid system_id for participant #{participant_name}: #{system_id}")
        return { valid: false, error: "Invalid system_id for participant #{participant_name}" }
      end

      # Verify system exists
      id = system_id.to_i
      unless System.exists?(id)
        Rails.logger.warn("Security: Non-existent system_id in participant_systems: #{id}")
        return { valid: false, error: "Systém #{id} neexistuje" }
      end
    end

    # Validate that all participant_systems keys are in participants array
    participant_systems.keys.each do |key|
      unless participants.include?(key)
        Rails.logger.warn("Security: participant_systems key not in participants: #{key}")
        return { valid: false, error: "Nesoulad mezi účastníky a systémy" }
      end
    end

    { valid: true }
  end

  # Note: distance and time_diff helper methods removed
  # All relativistic calculations now handled by RelativisticCalculator service
end

