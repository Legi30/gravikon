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

  # === System Associations (LOG002 tests) ===

  test "associates meeting with a system via system_id" do
    # Create a test system with minimal setup to avoid orbit validation
    system = System.new(
      name: "Test System",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test_system.json"
    )
    # Skip validations that require files/galaxy data
    system.save(validate: false)

    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: system
    )

    assert_equal system, meeting.system
    assert_equal system.id, meeting.system_id

    # Cleanup
    system.destroy
  end

  test "allows optional system association for backwards compatibility" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )

    # Should be valid without system_id (for legacy meetings)
    assert meeting.valid?
    assert_nil meeting.system_id
    assert_nil meeting.system
  end

  test "validates is_inter_system defaults to false" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]'
    )

    # is_inter_system should default to false or nil (which is falsy)
    assert_not meeting.is_inter_system
  end

  test "validates participant_systems JSON structure for inter-system meetings" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: '{"Earth": 1, "Mars": 2}'
    )

    # Should parse participant_systems correctly
    ps_hash = meeting.participant_systems_hash
    assert_equal 1, ps_hash["Earth"]
    assert_equal 2, ps_hash["Mars"]
  end

  test "rejects inter-system meeting without participant_systems" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: nil
    )

    assert_not meeting.valid?
    assert_includes meeting.errors[:participant_systems], "musí být vyplněno pro schůzky mezi systémy"
  end

  test "rejects invalid participant_systems JSON format" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: 'invalid json'
    )

    assert_not meeting.valid?
    assert meeting.errors[:participant_systems].any? { |msg| msg.include?("JSON") }
  end

  test "rejects non-hash participant_systems JSON" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: '["array", "not", "hash"]'
    )

    assert_not meeting.valid?
    assert_includes meeting.errors[:participant_systems], "musí být hash/objekt"
  end

  test "validates participant_systems has mapping for all participants" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars", "Venus"]',
      is_inter_system: true,
      participant_systems: '{"Earth": 1, "Mars": 2}'  # Missing Venus
    )

    assert_not meeting.valid?
    assert meeting.errors[:participant_systems].any? { |msg| msg.include?("Venus") }
  end

  test "validates participant_systems references existing systems" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: '{"Earth": 99999, "Mars": 99998}'  # Non-existent IDs
    )

    assert_not meeting.valid?
    assert meeting.errors[:participant_systems].any? { |msg| msg.include?("neexistující systém") }
  end

  test "accepts valid inter-system meeting with participant_systems mapping" do
    # Create test systems
    system1 = System.new(name: "Alpha", x: 200, y: 200, json_file_path: "data/systems/alpha.json")
    system2 = System.new(name: "Beta", x: 600, y: 600, json_file_path: "data/systems/beta.json")
    system1.save(validate: false)
    system2.save(validate: false)

    # Create system data files with test bodies
    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/alpha.json"), {
      bodies: [{ name: "Earth", type: "planet" }, { name: "Mars", type: "planet" }]
    }.to_json)
    File.write(Rails.root.join("data/systems/beta.json"), {
      bodies: [{ name: "Proxima", type: "star" }, { name: "Kepler", type: "planet" }]
    }.to_json)

    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Kepler"]',
      is_inter_system: true,
      participant_systems: "{\"Earth\": #{system1.id}, \"Kepler\": #{system2.id}}"
    )

    assert meeting.valid?, "Meeting should be valid: #{meeting.errors.full_messages}"

    # Cleanup
    File.delete(Rails.root.join("data/systems/alpha.json")) rescue nil
    File.delete(Rails.root.join("data/systems/beta.json")) rescue nil
    system1.destroy
    system2.destroy
  end

  test "participant_systems_hash returns empty hash for blank participant_systems" do
    meeting = Meeting.new(participant_systems: nil)
    assert_equal({}, meeting.participant_systems_hash)

    meeting.participant_systems = ""
    assert_equal({}, meeting.participant_systems_hash)
  end

  test "participant_systems_hash returns empty hash for invalid JSON" do
    meeting = Meeting.new(participant_systems: "invalid json")
    assert_equal({}, meeting.participant_systems_hash)
  end

  test "participant_systems_hash returns parsed hash for valid JSON" do
    meeting = Meeting.new(participant_systems: '{"Earth": 1, "Mars": 2}')
    ps_hash = meeting.participant_systems_hash
    assert_equal 1, ps_hash["Earth"]
    assert_equal 2, ps_hash["Mars"]
  end

  test "rejects participant_systems with oversized data (DOS prevention)" do
    # Create oversized participant_systems (> 50 entries)
    large_hash = {}
    60.times { |i| large_hash["Body#{i}"] = 1 }

    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Body0", "Body1"]',
      is_inter_system: true,
      participant_systems: large_hash.to_json
    )

    assert_not meeting.valid?
    assert meeting.errors[:participant_systems].any? { |msg| msg.include?("příliš mnoho") }
  end

  test "rejects participant_systems with nested objects (security)" do
    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      is_inter_system: true,
      participant_systems: '{"Earth": {"nested": "object"}, "Mars": 2}'
    )

    # The before_validation callback should reject nested objects
    meeting.valid?
    # participant_systems should be set to nil by the security check
    assert_nil meeting.participant_systems
  end

  test "participant_bodies_with_systems returns array for single-system meeting" do
    system = System.new(name: "Sol", x: 300, y: 300, json_file_path: "data/systems/sol.json")
    system.save(validate: false)

    # Create system data file
    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/sol.json"), {
      bodies: [
        { name: "Earth", type: "planet", mass: 5.97e24 },
        { name: "Mars", type: "planet", mass: 6.39e23 }
      ]
    }.to_json)

    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Mars"]',
      system: system
    )

    bodies = meeting.participant_bodies_with_systems
    assert_equal 2, bodies.length
    assert_equal "Earth", bodies[0][:name]
    assert_equal system.id, bodies[0][:system_id]
    assert_equal "Sol", bodies[0][:system_name]
    assert_equal 5.97e24, bodies[0][:body_data]["mass"]

    # Cleanup
    File.delete(Rails.root.join("data/systems/sol.json")) rescue nil
    system.destroy
  end

  test "participant_bodies_with_systems returns array for inter-system meeting" do
    system1 = System.new(name: "Alpha", x: 200, y: 200, json_file_path: "data/systems/alpha.json")
    system2 = System.new(name: "Beta", x: 600, y: 600, json_file_path: "data/systems/beta.json")
    system1.save(validate: false)
    system2.save(validate: false)

    # Create system data files
    FileUtils.mkdir_p(Rails.root.join("data/systems"))
    File.write(Rails.root.join("data/systems/alpha.json"), {
      bodies: [{ name: "Earth", type: "planet", mass: 5.97e24 }]
    }.to_json)
    File.write(Rails.root.join("data/systems/beta.json"), {
      bodies: [{ name: "Kepler", type: "planet", mass: 3.5e24 }]
    }.to_json)

    meeting = Meeting.new(
      start_time: "09:00",
      end_time: "10:00",
      participants: '["Earth", "Kepler"]',
      is_inter_system: true,
      participant_systems: "{\"Earth\": #{system1.id}, \"Kepler\": #{system2.id}}"
    )

    bodies = meeting.participant_bodies_with_systems
    assert_equal 2, bodies.length

    # Check Earth from Alpha
    earth_body = bodies.find { |b| b[:name] == "Earth" }
    assert_not_nil earth_body
    assert_equal system1.id, earth_body[:system_id]
    assert_equal "Alpha", earth_body[:system_name]

    # Check Kepler from Beta
    kepler_body = bodies.find { |b| b[:name] == "Kepler" }
    assert_not_nil kepler_body
    assert_equal system2.id, kepler_body[:system_id]
    assert_equal "Beta", kepler_body[:system_name]

    # Cleanup
    File.delete(Rails.root.join("data/systems/alpha.json")) rescue nil
    File.delete(Rails.root.join("data/systems/beta.json")) rescue nil
    system1.destroy
    system2.destroy
  end
end
