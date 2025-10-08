# frozen_string_literal: true

class Meeting < ApplicationRecord
  # Callbacks
  before_validation :ensure_participants_json
  after_commit :clear_dashboard_cache

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

  # Scopes
  # Note: This is a placeholder for when date support is added
  scope :upcoming, -> { where("created_at > ?", Time.current) }

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

  # Check if meeting has complete data (for displaying legacy records)
  def complete_data?
    start_time.present? &&
      end_time.present? &&
      participants.present? &&
      local_avg_duration.present? &&
      avg_delay.present?
  end

  # Get display-safe participants array (never crashes)
  def safe_participants_display
    arr = participants_array
    return "(neznámí účastníci)" if arr.empty?
    arr.join(", ")
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

  # Clear dashboard statistics cache when meetings change
  def clear_dashboard_cache
    # Clear all dashboard_stats cache keys
    # The cache key includes updated_at timestamp, so it will auto-refresh
    # But we also clear old keys to prevent cache bloat
    Rails.cache.delete_matched("dashboard_stats_v2_*")
  rescue => e
    Rails.logger.error("Failed to clear dashboard cache: #{e.message}")
    # Don't fail the transaction if cache clearing fails
  end
end
