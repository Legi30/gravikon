# frozen_string_literal: true

class MeetingsController < ApplicationController
  def index
    @meetings = Meeting.includes(:system).all
    @systems = System.all
    @systems_by_id = @systems.index_by(&:id)
    # Shared calculator instance so the relativistic partials don't reload
    # galaxy data for every meeting row
    @relativistic_calculator = RelativisticCalculator.new
  end

  def new
    @meeting = Meeting.new
    @system_id = params[:system_id]

    if @system_id.present?
      @system = System.find_by(id: @system_id)
      unless @system
        redirect_to meetings_path, alert: "Systém nebyl nalezen."
        return
      end
      @bodies = extract_bodies_from_system(@system.id)
      @meeting.system_id = @system.id
    else
      @systems = System.all
      case @systems.count
      when 0
        redirect_to new_galaxy_system_path, alert: "Nejprve vytvořte planetární soustavu."
      when 1
        @system = @systems.first
        @bodies = extract_bodies_from_system(@system.id)
        @meeting.system_id = @system.id
      end
      # Při 2 a více soustavách šablona zobrazí výběr soustavy
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

    @systems_with_bodies = extract_bodies_from_multiple_systems(@systems.pluck(:id))
  end

  def create
    result = build_meeting_attributes
    if result[:error]
      render_form_again(result[:error])
      return
    end

    @meeting = Meeting.create!(result[:attrs])
    invalidate_meeting_stats(@meeting)
    redirect_to meetings_path, notice: "Schůzka naplánována."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Meeting validation failed: #{e.message}")
    render_form_again("Nelze vytvořit schůzku: #{e.record.errors.full_messages.join(', ')}")
  end

  def edit
    @meeting = Meeting.find(params[:id])

    if @meeting.is_inter_system
      @systems = System.all
      @systems_with_bodies = extract_bodies_from_multiple_systems(@systems.pluck(:id))
    else
      @system = @meeting.system
      unless @system
        redirect_to meetings_path, alert: "Soustava této schůzky již neexistuje, schůzku nelze upravit."
        return
      end
      @bodies = extract_bodies_from_system(@system.id)
    end
  end

  def update
    @meeting = Meeting.find(params[:id])
    result = build_meeting_attributes
    if result[:error]
      redirect_to edit_meeting_path(@meeting), alert: result[:error]
      return
    end

    previous_system_ids = affected_system_ids(@meeting)
    @meeting.update!(result[:attrs])
    (previous_system_ids | affected_system_ids(@meeting)).each do |system_id|
      GalaxyService.invalidate_system_meeting_stats(system_id)
    end
    redirect_to meetings_path, notice: "Schůzka upravena."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Meeting validation failed on update: #{e.message}")
    redirect_to edit_meeting_path(@meeting), alert: "Nelze upravit schůzku: #{e.record.errors.full_messages.join(', ')}"
  end

  def destroy
    @meeting = Meeting.find(params[:id])
    @meeting.destroy
    invalidate_meeting_stats(@meeting)
    redirect_to meetings_path, notice: "Schůzka smazána."
  end

  private

  # Extract body names from a specific system
  # @param system_id [Integer] System ID to load from
  # @return [Array<String>] Array of body names
  def extract_bodies_from_system(system_id)
    system = System.find_by(id: system_id)
    return [] unless system

    # Use GalaxyService caching for system data
    system_file_id = File.basename(system.json_file_path, '.json')
    system_data = GalaxyService.load_system_data(system_file_id)
    return [] unless system_data

    system_data["bodies"]&.map { |b| b["name"] } || []
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
  # Security: Use .permit to whitelist hash structure. Note: permit returns
  # ActionController::Parameters, so convert to a plain Hash explicitly.
  def participant_systems_params
    permitted = if params[:participant_systems].present?
                  params.permit(participant_systems: {})[:participant_systems]
                elsif params.dig(:meeting, :participant_systems).present?
                  params.require(:meeting).permit(participant_systems: {})[:participant_systems]
                end
    return nil unless permitted.respond_to?(:to_h)

    permitted.to_h.presence
  end

  # Was the submitted form the inter-system one?
  def inter_system_request?
    params.dig(:meeting, :is_inter_system).to_s == "true" || participant_systems_params.present?
  end

  # Re-render the form the user submitted, preserving their input (views
  # prefill fields and checkboxes from params).
  def render_form_again(error)
    Rails.logger.warn("Meeting form rejected: #{error}")
    flash.now[:alert] = error

    if inter_system_request?
      @meeting = Meeting.new(is_inter_system: true)
      @systems = System.all
      @systems_with_bodies = extract_bodies_from_multiple_systems(@systems.pluck(:id))
      render :new_inter_system, status: :unprocessable_entity
    else
      @meeting = Meeting.new
      @systems = System.all
      @system = System.find_by(id: params.dig(:meeting, :system_id))
      @bodies = @system ? extract_bodies_from_system(@system.id) : []
      render :new, status: :unprocessable_entity
    end
  end

  # Validates the submitted form and computes relativistic statistics.
  # @return [Hash] { attrs: Hash } on success, { error: String } on failure
  def build_meeting_attributes
    permitted_params = meeting_params
    participants = participants_params
    participant_systems = participant_systems_params
    is_inter_system = permitted_params[:is_inter_system].to_s == "true" || participant_systems.present?

    validation_result = validate_participants_array(participants)
    return { error: validation_result[:error] } unless validation_result[:valid]

    return { error: "Musíš vybrat alespoň dvě tělesa." } if participants.size < 2

    if is_inter_system
      if participant_systems.blank?
        return { error: "Chybí přiřazení účastníků k soustavám. Zkuste výběr zopakovat." }
      end

      validation_result = validate_participant_systems_json(participant_systems, participants)
      return { error: validation_result[:error] } unless validation_result[:valid]

      parsed_participants = load_inter_system_participants(participants, participant_systems)
      if parsed_participants.size < 2
        return { error: "Nepodařilo se načíst data účastníků. Zkontrolujte výběr účastníků." }
      end
    else
      system = System.find_by(id: permitted_params[:system_id])
      return { error: "Systém nebyl nalezen." } unless system

      system_data = system.load_system_data
      bodies = system_data ? system_data["bodies"] : []
      parsed_participants = participants.map { |name| find_body(name, bodies) }.compact
      if parsed_participants.size < 2
        return { error: "Vybraná tělesa se v soustavě #{system.name} nepodařilo najít." }
      end
    end

    # Prepare participants with system information for the calculator
    participants_with_systems = if is_inter_system
      parsed_participants.map do |body|
        { body: body, system_id: participant_systems[body['name']] }
      end
    else
      parsed_participants.map do |body|
        { body: body, system_id: system.id }
      end
    end

    # Combines local stellar time dilation with black hole time dilation
    # and calculates signal delays accounting for inter-system distances
    stats = RelativisticCalculator.new.calculate_meeting_statistics(
      participants_with_systems,
      start_time: permitted_params[:start_time],
      end_time: permitted_params[:end_time]
    )

    attrs = {
      start_time: permitted_params[:start_time],
      end_time: permitted_params[:end_time],
      topic: permitted_params[:topic] || "",
      participants: participants.to_json,
      local_avg_duration: stats[:avg_duration],
      avg_delay: stats[:avg_delay],
      is_inter_system: is_inter_system,
      system_id: is_inter_system ? nil : system.id,
      participant_systems: is_inter_system ? participant_systems.to_json : nil
    }

    { attrs: attrs }
  end

  # Invalidate cached meeting statistics for every system the meeting touches
  def invalidate_meeting_stats(meeting)
    affected_system_ids(meeting).each do |system_id|
      GalaxyService.invalidate_system_meeting_stats(system_id)
    end
  end

  def affected_system_ids(meeting)
    if meeting.is_inter_system
      meeting.participant_systems_hash.values.uniq.compact
    elsif meeting.system_id
      [meeting.system_id]
    else
      []
    end
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
      return { valid: false, error: "Neplatná struktura přiřazení soustav" }
    end

    # Size limit to prevent DOS (max 50 participants)
    if participant_systems.size > 50
      Rails.logger.warn("Security: Too many participant_systems entries: #{participant_systems.size}")
      return { valid: false, error: "Příliš mnoho účastníků (max. 50)" }
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
        return { valid: false, error: "Neplatný formát jména účastníka" }
      end

      # Value must match integer format (system_id)
      unless system_id.to_s.match?(/\A\d+\z/)
        Rails.logger.warn("Security: Invalid system_id for participant #{participant_name}: #{system_id}")
        return { valid: false, error: "Neplatné ID soustavy pro účastníka #{participant_name}" }
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
end
