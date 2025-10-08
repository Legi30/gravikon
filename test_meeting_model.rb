#!/usr/bin/env ruby
# Test script for Meeting model validations and methods

require_relative 'config/environment'

puts "=" * 80
puts "Testing Meeting Model Validations and Methods"
puts "=" * 80
puts

# Test 1: Valid meeting
puts "Test 1: Valid meeting"
puts "-" * 40
m = Meeting.new(
  start_time: '09:30',
  end_time: '10:45',
  participants: '["Earth", "Mars"]',
  local_avg_duration: 75,
  avg_delay: 120
)
puts "Valid: #{m.valid?}"
if m.valid?
  puts "✓ Validation passed"
  puts "  Participants array: #{m.participants_array.inspect}"
  puts "  Formatted duration: #{m.formatted_duration}"
  puts "  Formatted delay: #{m.formatted_delay}"
else
  puts "✗ Validation failed"
  puts "  Errors: #{m.errors.full_messages.join(', ')}"
end
puts

# Test 2: Invalid time format
puts "Test 2: Invalid time format (25:00)"
puts "-" * 40
m2 = Meeting.new(
  start_time: '25:00',
  end_time: '10:00',
  participants: '["Earth", "Mars"]'
)
puts "Valid: #{m2.valid?}"
if m2.valid?
  puts "✗ Should have failed validation"
else
  puts "✓ Validation correctly failed"
  puts "  Errors: #{m2.errors.full_messages.join(', ')}"
end
puts

# Test 3: Only one participant (should fail)
puts "Test 3: Only one participant"
puts "-" * 40
m3 = Meeting.new(
  start_time: '09:00',
  end_time: '10:00',
  participants: '["Earth"]'
)
puts "Valid: #{m3.valid?}"
if m3.valid?
  puts "✗ Should have failed validation"
else
  puts "✓ Validation correctly failed"
  puts "  Errors: #{m3.errors.full_messages.join(', ')}"
end
puts

# Test 4: Same start and end time (should fail)
puts "Test 4: Same start and end time"
puts "-" * 40
m4 = Meeting.new(
  start_time: '09:00',
  end_time: '09:00',
  participants: '["Earth", "Mars"]'
)
puts "Valid: #{m4.valid?}"
if m4.valid?
  puts "✗ Should have failed validation"
else
  puts "✓ Validation correctly failed"
  puts "  Errors: #{m4.errors.full_messages.join(', ')}"
end
puts

# Test 5: Midnight wraparound (should be valid)
puts "Test 5: Midnight wraparound (23:00 to 01:00)"
puts "-" * 40
m5 = Meeting.new(
  start_time: '23:00',
  end_time: '01:00',
  participants: '["Earth", "Mars"]'
)
puts "Valid: #{m5.valid?}"
if m5.valid?
  puts "✓ Validation passed (midnight wraparound allowed)"
else
  puts "✗ Should have passed validation"
  puts "  Errors: #{m5.errors.full_messages.join(', ')}"
end
puts

# Test 6: Duration formatting variations
puts "Test 6: Duration formatting (90 minutes = 1h 30m)"
puts "-" * 40
m6 = Meeting.new(
  start_time: '09:00',
  end_time: '10:00',
  participants: '["Earth", "Mars"]',
  local_avg_duration: 90,
  avg_delay: 45
)
puts "Formatted duration: #{m6.formatted_duration}"
puts "Formatted delay: #{m6.formatted_delay}"
puts

# Test 7: Large delay (should show in minutes)
puts "Test 7: Large delay (180 seconds = 3 minutes)"
puts "-" * 40
m7 = Meeting.new(
  start_time: '09:00',
  end_time: '10:00',
  participants: '["Earth", "Mars"]',
  avg_delay: 180
)
puts "Formatted delay: #{m7.formatted_delay}"
puts

# Test 8: Missing required fields
puts "Test 8: Missing required fields"
puts "-" * 40
m8 = Meeting.new
puts "Valid: #{m8.valid?}"
if m8.valid?
  puts "✗ Should have failed validation"
else
  puts "✓ Validation correctly failed"
  puts "  Errors: #{m8.errors.full_messages.join(', ')}"
end
puts

# Test 9: Malformed JSON participants
puts "Test 9: Malformed JSON participants"
puts "-" * 40
m9 = Meeting.new(
  start_time: '09:00',
  end_time: '10:00',
  participants: 'not valid json'
)
puts "Valid: #{m9.valid?}"
if m9.valid?
  puts "✗ Should have failed validation"
else
  puts "✓ Validation correctly failed"
  puts "  Errors: #{m9.errors.full_messages.join(', ')}"
end
puts

# Test 10: participants_array with invalid JSON
puts "Test 10: participants_array with invalid JSON"
puts "-" * 40
m10 = Meeting.new(participants: 'invalid')
result = m10.participants_array
puts "Result: #{result.inspect}"
if result == []
  puts "✓ Correctly returned empty array for invalid JSON"
else
  puts "✗ Should have returned empty array"
end
puts

# Test 11: Edge case time formats (9:30 vs 09:30)
puts "Test 11: Single digit hour (9:30)"
puts "-" * 40
m11 = Meeting.new(
  start_time: '9:30',
  end_time: '10:00',
  participants: '["Earth", "Mars"]'
)
puts "Valid: #{m11.valid?}"
if m11.valid?
  puts "✓ Validation passed (single digit hour allowed)"
else
  puts "✗ Should have passed validation"
  puts "  Errors: #{m11.errors.full_messages.join(', ')}"
end
puts

# Test 12: Hour-only durations
puts "Test 12: Duration formatting (120 minutes = 2h)"
puts "-" * 40
m12 = Meeting.new(
  start_time: '09:00',
  end_time: '10:00',
  participants: '["Earth", "Mars"]',
  local_avg_duration: 120
)
puts "Formatted duration: #{m12.formatted_duration}"
puts

puts "=" * 80
puts "All tests completed!"
puts "=" * 80
