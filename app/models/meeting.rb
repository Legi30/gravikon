# frozen_string_literal: true

class Meeting < ApplicationRecord
  # Associations
  belongs_to :system, optional: true

  # Callbacks
  before_validation :ensure_participants_json
  before_validation :ensure_participant_systems_json

  # Validations
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :participants, presence: true

  # Format validation for time fields (HH:MM)
  validates :start_time, format: {
    with: /\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/,
    message: "musí být ve formátu HH:MM (např. 09:30 nebo 14:45)"
  }, if: -> { start_time.present? }

  validates :end_time, format: {
    with: /\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/,
    message: "musí být ve formátu HH:MM (např. 09:30 nebo 14:45)"
  }, if: -> { end_time.present? }

  # Validate participants is valid JSON array with at least 2 elements
  validate :validate_participants_json

  # Custom validation that end_time is after start_time
  validate :validate_end_time_after_start_time

  # Validate single-system meetings have all participants from same system
  validate :validate_single_system_participants

  # Validate inter-system meetings have valid participant_systems mapping
  validate :validate_inter_system_participant_systems

  # Instance methods

  # Returns parsed participants JSON as array
  # Returns empty array if parsing fails
  def participants_array
    return [] if participants.blank?

    JSON.parse(participants)
  rescue JSON::ParserError
    []
  end

  # Returns human-readable duration string (e.g., "1h 30m" or "45m")
  def formatted_duration
    return "0m" if local_avg_duration.nil? || local_avg_duration.zero?

    total_minutes = local_avg_duration.round
    hours = total_minutes / 60
    minutes = total_minutes % 60

    if hours.positive? && minutes.positive?
      "#{hours}h #{minutes}m"
    elsif hours.positive?
      "#{hours}h"
    else
      "#{minutes}m"
    end
  end

  # Returns delay with appropriate units
  def formatted_delay
    return "0s" if avg_delay.nil? || avg_delay.zero?

    delay = avg_delay.round(2)

    if delay >= 60
      minutes = (delay / 60).round(2)
      "#{minutes} min"
    else
      "#{delay} s"
    end
  end

  # Returns parsed participant_systems JSON as hash mapping participant
  # names to integer system ids. Returns empty hash if parsing fails.
  def participant_systems_hash
    return {} if participant_systems.blank?

    JSON.parse(participant_systems).transform_values { |v| v.to_i }
  rescue JSON::ParserError
    {}
  end

  # Scheduled duration in minutes (from HH:MM times, with midnight wraparound)
  def duration_minutes
    RelativisticCalculator.duration_minutes(start_time, end_time)
  end

  private

  # Ensure participants is properly JSON encoded before validation
  def ensure_participants_json
    return if participants.blank?

    # If participants is already a valid JSON string, leave it
    begin
      JSON.parse(participants)
    rescue JSON::ParserError
      # If it's not valid JSON, try to convert it to JSON array
      # This handles cases where participants might be passed as an array
      self.participants = participants.to_json if participants.is_a?(Array)
    end
  end

  # Validate participants is a valid JSON array with at least 2 elements
  def validate_participants_json
    return if participants.blank?

    begin
      parsed = JSON.parse(participants)

      unless parsed.is_a?(Array)
        errors.add(:participants, "musí být pole (array)")
        return
      end

      if parsed.length < 2
        errors.add(:participants, "musí obsahovat alespoň 2 účastníky")
      end
    rescue JSON::ParserError
      errors.add(:participants, "není platný JSON formát")
    end
  end

  # Validate that end_time is after start_time (with midnight wraparound)
  def validate_end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    # Parse time strings to compare
    start_parts = start_time.split(":")
    end_parts = end_time.split(":")

    return unless start_parts.length == 2 && end_parts.length == 2

    start_minutes = start_parts[0].to_i * 60 + start_parts[1].to_i
    end_minutes = end_parts[0].to_i * 60 + end_parts[1].to_i

    # If end_time is less than start_time, assume midnight wraparound
    # This is valid (e.g., 23:00 to 01:00)
    # But if they're equal, that's invalid
    if start_minutes == end_minutes
      errors.add(:end_time, "musí být odlišný od času začátku")
    end
  end

  # Ensure participant_systems is properly JSON encoded before validation
  def ensure_participant_systems_json
    return if participant_systems.blank?

    # If participant_systems is already a valid JSON string, validate and leave it
    begin
      parsed = JSON.parse(participant_systems)

      # Security: Ensure it's a simple Hash (not nested structure)
      if parsed.is_a?(Hash)
        # Verify values are simple types (Integer or String), not nested objects/arrays
        parsed.each do |key, value|
          unless value.is_a?(Integer) || value.is_a?(String) || value.is_a?(Numeric)
            Rails.logger.warn("Security: Nested object detected in participant_systems, rejecting")
            self.participant_systems = nil
            return
          end
        end
      end
    rescue JSON::ParserError
      # If it's not valid JSON, try to convert it to JSON
      if participant_systems.is_a?(Hash)
        # Validate Hash values before converting to JSON
        participant_systems.each do |key, value|
          unless value.is_a?(Integer) || value.is_a?(String) || value.is_a?(Numeric)
            Rails.logger.warn("Security: Nested object in participant_systems Hash, rejecting")
            self.participant_systems = nil
            return
          end
        end
        self.participant_systems = participant_systems.to_json
      end
    end
  end

  # Validate that single-system meetings have all participants from the same system
  def validate_single_system_participants
    # Skip if inter-system meeting or no system assigned
    return if is_inter_system || system.blank?

    # Skip if participants not valid yet (other validation will catch it)
    return if participants.blank?

    system_data = system.load_system_data
    unless system_data
      errors.add(:system_id, "nemá platná data soustavy")
      return
    end

    # Get all body names in the system
    system_body_names = system_data["bodies"]&.map { |b| b["name"] } || []

    # Check each participant is in the system
    participants_array.each do |participant|
      unless system_body_names.include?(participant)
        errors.add(:participants, "obsahuje '#{participant}', který není v soustavě #{system.name}")
      end
    end
  end

  # Validate that inter-system meetings have valid participant_systems mapping
  def validate_inter_system_participant_systems
    # Only validate if this is an inter-system meeting
    return unless is_inter_system

    if participant_systems.blank?
      errors.add(:participant_systems, "musí být vyplněno pro schůzky mezi soustavami")
      return
    end

    # Parse participant_systems
    begin
      ps_hash = JSON.parse(participant_systems)

      unless ps_hash.is_a?(Hash)
        errors.add(:participant_systems, "musí být hash/objekt")
        return
      end

      # Security: Validate size limits to prevent DOS
      if ps_hash.size > 50
        errors.add(:participant_systems, "obsahuje příliš mnoho záznamů (max. 50)")
        Rails.logger.warn("Security: participant_systems exceeds size limit: #{ps_hash.size}")
        return
      end

      # Security: Validate JSON bytesize to prevent DOS
      json_bytesize = participant_systems.bytesize
      if json_bytesize > 10_240 # 10KB limit
        errors.add(:participant_systems, "je příliš velký (max. 10KB)")
        Rails.logger.warn("Security: participant_systems JSON too large: #{json_bytesize} bytes")
        return
      end

      # Security: Validate structure - keys must be strings, values must be numeric
      ps_hash.each do |key, value|
        # Validate keys are strings with length limit
        unless key.is_a?(String) && key.length <= 100
          errors.add(:participant_systems, "obsahuje neplatný klíč")
          Rails.logger.warn("Security: Invalid participant_systems key: #{key.class}")
          return
        end

        # Validate values are numeric (prevent nested objects/arrays)
        unless value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
          errors.add(:participant_systems, "obsahuje neplatnou hodnotu pro '#{key}'")
          Rails.logger.warn("Security: Non-numeric value in participant_systems: #{value.class}")
          return
        end
      end

      # Validate each participant has a system mapping
      participants_array.each do |participant|
        unless ps_hash.key?(participant)
          errors.add(:participant_systems, "neobsahuje mapování pro účastníka '#{participant}'")
        end
      end

      # Validate each mapped system exists
      ps_hash.each do |participant, system_id|
        # Convert to integer for lookup
        system_id_int = system_id.is_a?(Integer) ? system_id : system_id.to_i

        participant_system = System.find_by(id: system_id_int)
        unless participant_system
          errors.add(:participant_systems, "odkazuje na neexistující soustavu (ID: #{system_id}) pro účastníka '#{participant}'")
          next
        end

        # Validate participant exists in their assigned system
        system_data = participant_system.load_system_data
        if system_data
          system_body_names = system_data["bodies"]&.map { |b| b["name"] } || []
          unless system_body_names.include?(participant)
            errors.add(:participant_systems, "účastník '#{participant}' není v přiřazené soustavě #{participant_system.name}")
          end
        end
      end
    rescue JSON::ParserError => e
      errors.add(:participant_systems, "není platný JSON formát")
      Rails.logger.warn("Security: JSON parse error in participant_systems: #{e.message}")
    end
  end
end
