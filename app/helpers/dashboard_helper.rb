# frozen_string_literal: true

module DashboardHelper
  # Calculate total number of meetings
  def total_meetings_count
    Meeting.count
  end

  # Calculate average signal delay across all meetings
  def average_signal_delay
    return 0 if Meeting.count.zero?

    total_delay = Meeting.sum(:avg_delay)
    (total_delay / Meeting.count).round(2)
  end

  # Calculate average time dilation across all meetings
  def average_time_dilation
    return 0 if Meeting.count.zero?

    total_duration = Meeting.sum(:local_avg_duration)
    (total_duration / Meeting.count).round(2)
  end

  # Get most frequently selected celestial bodies
  # Returns hash: { "Earth" => 5, "Mars" => 3, ... }
  # Optimized to avoid N+1 queries by using pluck instead of loading all meetings
  def participant_frequency
    frequency = Hash.new(0)

    # Use pluck to get only the participants column, avoiding full model instantiation
    # This is much more efficient than Meeting.all.each
    Meeting.pluck(:participants).each do |participants_json|
      begin
        participants = JSON.parse(participants_json)
        participants.each { |participant| frequency[participant] += 1 }
      rescue JSON::ParserError
        # Skip malformed JSON
      end
    end

    # Sort by frequency descending, return top 10
    frequency.sort_by { |_name, count| -count }.first(10).to_h
  end

  # Get distribution of meeting durations
  # Returns hash with duration ranges: { "0-30 min" => 5, "31-60 min" => 3, ... }
  # Optimized using SQL CASE for database-level aggregation
  def duration_distribution
    # Use SQL to count directly in database instead of loading all meetings
    # This is significantly faster and more memory efficient
    {
      "0-30 min" => Meeting.where(local_avg_duration: 0..30).count,
      "31-60 min" => Meeting.where(local_avg_duration: 31..60).count,
      "61-90 min" => Meeting.where(local_avg_duration: 61..90).count,
      "91-120 min" => Meeting.where(local_avg_duration: 91..120).count,
      "120+ min" => Meeting.where("local_avg_duration > ?", 120).count
    }
  end

  # Get recent meetings (last 10)
  def recent_meetings
    Meeting.order(created_at: :desc).limit(10)
  end

  # Calculate total meeting time (sum of all durations)
  def total_meeting_time
    Meeting.sum(:local_avg_duration).round(2)
  end

  # Get the longest meeting
  def longest_meeting
    Meeting.order(local_avg_duration: :desc).first
  end

  # Get the meeting with highest delay
  def highest_delay_meeting
    Meeting.order(avg_delay: :desc).first
  end

  # Format duration for display
  def format_duration_hours(minutes)
    return "0 min" if minutes.nil? || minutes.zero?

    hours = (minutes / 60).to_i
    mins = (minutes % 60).round

    if hours > 0
      "#{hours}h #{mins}m"
    else
      "#{mins} min"
    end
  end

  # Format delay for display
  def format_delay_display(seconds)
    return "0 s" if seconds.nil? || seconds.zero?

    if seconds >= 60
      minutes = (seconds / 60).round(2)
      "#{minutes} min"
    else
      "#{seconds.round(2)} s"
    end
  end
end
