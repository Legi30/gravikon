require "test_helper"

class MeetingTest < ActiveSupport::TestCase
  # === Presence Validations ===

  test "should be valid with all required fields" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      local_avg_duration: 60,
      avg_delay: 120
    )
    assert meeting.valid?, "Meeting should be valid with all required fields"
  end

  test "should not save meeting without start_time" do
    meeting = Meeting.new(
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Saved meeting without start_time"
    assert meeting.errors[:start_time].any?, "Expected error on start_time"
  end

  test "should not save meeting without end_time" do
    meeting = Meeting.new(
      start_time: "09:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Saved meeting without end_time"
    assert meeting.errors[:end_time].any?, "Expected error on end_time"
  end

  test "should not save meeting without participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00"
    )
    assert_not meeting.valid?, "Saved meeting without participants"
    assert meeting.errors[:participants].any?, "Expected error on participants"
  end

  # === Time Format Validations ===

  test "should reject invalid time format with invalid hours" do
    meeting = Meeting.new(
      start_time: "25:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Accepted time with invalid hours (25)"
    assert meeting.errors[:start_time].any?
  end

  test "should reject invalid time format with invalid minutes" do
    meeting = Meeting.new(
      start_time: "09:99",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Accepted time with invalid minutes (99)"
    assert meeting.errors[:start_time].any?
  end

  test "should reject time without colon separator" do
    meeting = Meeting.new(
      start_time: "0900",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Accepted time without colon separator"
    assert meeting.errors[:start_time].any?
  end

  test "should reject time with invalid format" do
    meeting = Meeting.new(
      start_time: "9am",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Accepted non-numeric time format"
    assert meeting.errors[:start_time].any?
  end

  test "should accept valid time with single digit hour" do
    meeting = Meeting.new(
      start_time: "9:30",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected valid time with single digit hour (9:30)"
  end

  test "should accept valid time with double digit hour" do
    meeting = Meeting.new(
      start_time: "09:30",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected valid time with double digit hour (09:30)"
  end

  test "should accept boundary time 00:00" do
    meeting = Meeting.new(
      start_time: "00:00",
      end_time: "01:00",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected valid boundary time 00:00"
  end

  test "should accept boundary time 23:59" do
    meeting = Meeting.new(
      start_time: "22:00",
      end_time: "23:59",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected valid boundary time 23:59"
  end

  # === Participants Validation ===

  test "should reject meeting with only one participant" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth"]'
    )
    assert_not meeting.valid?, "Accepted meeting with only one participant"
    assert meeting.errors[:participants].any?
  end

  test "should accept meeting with two participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected meeting with two participants"
  end

  test "should accept meeting with three or more participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars", "Venus"]'
    )
    assert meeting.valid?, "Rejected meeting with three participants"
  end

  test "should reject malformed JSON in participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: 'not valid json'
    )
    assert_not meeting.valid?, "Accepted malformed JSON in participants"
    assert meeting.errors[:participants].any?
  end

  test "should reject non-array JSON in participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '{"key": "value"}'
    )
    assert_not meeting.valid?, "Accepted non-array JSON in participants"
    assert meeting.errors[:participants].any?
  end

  test "should reject empty array in participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '[]'
    )
    assert_not meeting.valid?, "Accepted empty array in participants"
    assert meeting.errors[:participants].any?
  end

  # === Time Sequence Validation ===

  test "should reject meeting where start_time equals end_time" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "09:00",
      participants: '["Earth", "Mars"]'
    )
    assert_not meeting.valid?, "Accepted meeting with same start and end time"
    assert meeting.errors[:end_time].any?
  end

  test "should accept meeting with midnight wraparound" do
    meeting = Meeting.new(
      start_time: "23:00",
      end_time: "01:00",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected valid midnight wraparound meeting"
  end

  test "should accept meeting where end_time is after start_time same day" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "17:00",
      participants: '["Earth", "Mars"]'
    )
    assert meeting.valid?, "Rejected valid meeting with end after start"
  end

  # === Helper Methods - participants_array ===

  test "participants_array returns parsed JSON as array" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars", "Venus"]'
    )
    assert_equal ["Earth", "Mars", "Venus"], meeting.participants_array
  end

  test "participants_array returns empty array for invalid JSON" do
    meeting = Meeting.new(participants: 'invalid json')
    assert_equal [], meeting.participants_array
  end

  test "participants_array returns empty array for nil participants" do
    meeting = Meeting.new(participants: nil)
    assert_equal [], meeting.participants_array
  end

  # === Helper Methods - formatted_duration ===

  test "formatted_duration returns hours and minutes for 90 minutes" do
    meeting = Meeting.new(local_avg_duration: 90)
    assert_equal "1h 30m", meeting.formatted_duration
  end

  test "formatted_duration returns only hours for 120 minutes" do
    meeting = Meeting.new(local_avg_duration: 120)
    assert_equal "2h", meeting.formatted_duration
  end

  test "formatted_duration returns only minutes for 45 minutes" do
    meeting = Meeting.new(local_avg_duration: 45)
    assert_equal "45m", meeting.formatted_duration
  end

  test "formatted_duration returns 0m for nil duration" do
    meeting = Meeting.new(local_avg_duration: nil)
    assert_equal "0m", meeting.formatted_duration
  end

  test "formatted_duration returns 0m for zero duration" do
    meeting = Meeting.new(local_avg_duration: 0)
    assert_equal "0m", meeting.formatted_duration
  end

  # === Helper Methods - formatted_delay ===

  test "formatted_delay returns seconds for values less than 60" do
    meeting = Meeting.new(avg_delay: 45.5)
    assert_equal "45.5 s", meeting.formatted_delay
  end

  test "formatted_delay returns minutes for values 60 or greater" do
    meeting = Meeting.new(avg_delay: 180)
    assert_equal "3.0 min", meeting.formatted_delay
  end

  test "formatted_delay returns 0s for nil delay" do
    meeting = Meeting.new(avg_delay: nil)
    assert_equal "0s", meeting.formatted_delay
  end

  test "formatted_delay returns 0s for zero delay" do
    meeting = Meeting.new(avg_delay: 0)
    assert_equal "0s", meeting.formatted_delay
  end

  # === Callbacks - before_validation ===

  test "before_validation converts array to JSON" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: ["Earth", "Mars"]
    )
    meeting.valid? # Trigger validation and callbacks
    assert_kind_of String, meeting.participants
    assert_equal ["Earth", "Mars"], JSON.parse(meeting.participants)
  end
end
