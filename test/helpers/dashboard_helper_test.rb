require "test_helper"

class DashboardHelperTest < ActionView::TestCase
  setup do
    Meeting.delete_all
  end

  # === total_meetings_count ===

  test "total_meetings_count returns 0 when no meetings exist" do
    assert_equal 0, total_meetings_count
  end

  test "total_meetings_count returns correct count with meetings" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    assert_equal 2, total_meetings_count
  end

  # === average_signal_delay ===

  test "average_signal_delay returns 0 when no meetings exist" do
    assert_equal 0, average_signal_delay
  end

  test "average_signal_delay calculates correct average" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    assert_equal 110.0, average_signal_delay # (120 + 100) / 2
  end

  test "average_signal_delay rounds to 2 decimal places" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 101
    )

    assert_equal 100.5, average_signal_delay
  end

  # === average_time_dilation ===

  test "average_time_dilation returns 0 when no meetings exist" do
    assert_equal 0, average_time_dilation
  end

  test "average_time_dilation calculates correct average" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    assert_equal 75.0, average_time_dilation # (60 + 90) / 2
  end

  test "average_time_dilation rounds to 2 decimal places" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 50,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 51,
      avg_delay: 100
    )

    assert_equal 50.5, average_time_dilation
  end

  # === participant_frequency ===

  test "participant_frequency returns empty hash when no meetings exist" do
    assert_equal({}, participant_frequency)
  end

  test "participant_frequency counts participants correctly" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 60,
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "11:00",
      end_time: "12:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 110
    )

    freq = participant_frequency
    assert_equal 3, freq["Earth"]
    assert_equal 2, freq["Mars"]
    assert_equal 1, freq["Sol"]
  end

  test "participant_frequency sorts by frequency descending" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 60,
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "11:00",
      end_time: "12:00",
      participants: '["Mars", "Venus"]',
      local_avg_duration: 60,
      avg_delay: 110
    )

    freq = participant_frequency
    freq_keys = freq.keys
    # Mars should be first (3 occurrences)
    assert_equal "Mars", freq_keys[0]
  end

  test "participant_frequency limits to top 10" do
    # Create meetings with 15 different bodies
    (1..15).each do |i|
      # Create i meetings for each body to ensure different counts
      i.times do
        Meeting.create!(
          start_time: "09:00",
          end_time: "10:00",
          participants: "[\"Body#{i}\", \"Earth\"]",
          local_avg_duration: 60,
          avg_delay: 120
        )
      end
    end

    freq = participant_frequency
    assert_equal 10, freq.size
  end

  test "participant_frequency handles malformed JSON gracefully" do
    # Malformed JSON can't pass validations — simulate a legacy corrupted row
    corrupted = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: "invalid json",
      local_avg_duration: 60,
      avg_delay: 120
    )
    corrupted.save!(validate: false)
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 100
    )

    freq = participant_frequency
    # Should skip malformed JSON and only count valid one
    assert_equal 1, freq["Earth"]
    assert_equal 1, freq["Mars"]
  end

  # === duration_distribution ===

  test "duration_distribution returns all zero counts when no meetings exist" do
    dist = duration_distribution
    assert_equal 0, dist["0-30 min"]
    assert_equal 0, dist["31-60 min"]
    assert_equal 0, dist["61-90 min"]
    assert_equal 0, dist["91-120 min"]
    assert_equal 0, dist["120+ min"]
  end

  test "duration_distribution categorizes meetings correctly" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 20, # 0-30
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 45, # 31-60
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "11:00",
      end_time: "12:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 75, # 61-90
      avg_delay: 110
    )
    Meeting.create!(
      start_time: "13:00",
      end_time: "14:00",
      participants: '["Mars", "Venus"]',
      local_avg_duration: 100, # 91-120
      avg_delay: 115
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Venus"]',
      local_avg_duration: 150, # 120+
      avg_delay: 125
    )

    dist = duration_distribution
    assert_equal 1, dist["0-30 min"]
    assert_equal 1, dist["31-60 min"]
    assert_equal 1, dist["61-90 min"]
    assert_equal 1, dist["91-120 min"]
    assert_equal 1, dist["120+ min"]
  end

  test "duration_distribution handles boundary values correctly" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 30, # Boundary: should be in 0-30
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "10:00",
      end_time: "11:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 31, # Boundary: should be in 31-60
      avg_delay: 100
    )
    Meeting.create!(
      start_time: "11:00",
      end_time: "12:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 120, # Boundary: should be in 91-120
      avg_delay: 110
    )
    Meeting.create!(
      start_time: "12:00",
      end_time: "13:00",
      participants: '["Mars", "Venus"]',
      local_avg_duration: 121, # Boundary: should be in 120+
      avg_delay: 115
    )

    dist = duration_distribution
    assert_equal 1, dist["0-30 min"]
    assert_equal 1, dist["31-60 min"]
    assert_equal 1, dist["91-120 min"]
    assert_equal 1, dist["120+ min"]
  end

  # === total_meeting_time ===

  test "total_meeting_time returns 0 when no meetings exist" do
    assert_equal 0, total_meeting_time
  end

  test "total_meeting_time sums all meeting durations" do
    Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    assert_equal 150.0, total_meeting_time
  end

  # === recent_meetings ===

  test "recent_meetings returns empty array when no meetings exist" do
    assert_equal 0, recent_meetings.count
  end

  test "recent_meetings returns meetings in descending order by created_at" do
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    sleep 0.01
    meeting2 = Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )

    recent = recent_meetings
    assert_equal 2, recent.count
    assert_equal meeting2.id, recent.first.id
    assert_equal meeting1.id, recent.last.id
  end

  test "recent_meetings limits to 10 meetings" do
    15.times do |i|
      Meeting.create!(
        start_time: "09:00",
        end_time: "10:00",
        participants: '["Earth", "Mars"]',
        local_avg_duration: 60,
        avg_delay: 120
      )
    end

    assert_equal 10, recent_meetings.count
  end

  # === longest_meeting ===

  test "longest_meeting returns nil when no meetings exist" do
    assert_nil longest_meeting
  end

  test "longest_meeting returns meeting with highest duration" do
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    meeting2 = Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 120,
      avg_delay: 100
    )
    meeting3 = Meeting.create!(
      start_time: "16:00",
      end_time: "17:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 45,
      avg_delay: 110
    )

    assert_equal meeting2.id, longest_meeting.id
  end

  # === highest_delay_meeting ===

  test "highest_delay_meeting returns nil when no meetings exist" do
    assert_nil highest_delay_meeting
  end

  test "highest_delay_meeting returns meeting with highest delay" do
    meeting1 = Meeting.create!(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    meeting2 = Meeting.create!(
      start_time: "14:00",
      end_time: "15:00",
      participants: '["Earth", "Sol"]',
      local_avg_duration: 90,
      avg_delay: 100
    )
    meeting3 = Meeting.create!(
      start_time: "16:00",
      end_time: "17:00",
      participants: '["Mars", "Sol"]',
      local_avg_duration: 45,
      avg_delay: 200
    )

    assert_equal meeting3.id, highest_delay_meeting.id
  end

  # === format_duration_hours ===

  test "format_duration_hours returns 0 min for nil" do
    assert_equal "0 min", format_duration_hours(nil)
  end

  test "format_duration_hours returns 0 min for zero" do
    assert_equal "0 min", format_duration_hours(0)
  end

  test "format_duration_hours formats minutes only" do
    assert_equal "45 min", format_duration_hours(45)
  end

  test "format_duration_hours formats hours and minutes" do
    assert_equal "1h 30m", format_duration_hours(90)
  end

  test "format_duration_hours formats hours only" do
    assert_equal "2h 0m", format_duration_hours(120)
  end

  test "format_duration_hours rounds minutes" do
    assert_equal "1h 31m", format_duration_hours(90.5)
  end

  # === format_delay_display ===

  test "format_delay_display returns 0 s for nil" do
    assert_equal "0 s", format_delay_display(nil)
  end

  test "format_delay_display returns 0 s for zero" do
    assert_equal "0 s", format_delay_display(0)
  end

  test "format_delay_display formats seconds for values less than 60" do
    assert_equal "45.5 s", format_delay_display(45.5)
  end

  test "format_delay_display formats minutes for values 60 or greater" do
    assert_equal "2.0 min", format_delay_display(120)
  end

  test "format_delay_display rounds minutes to 2 decimal places" do
    assert_equal "1.83 min", format_delay_display(110)
  end
end
