# Data Migration Guide

## Overview

This guide explains how Gravikon handles backward compatibility with legacy meeting data when new validations are added to the Meeting model.

## Meeting Model Validations

### Current Validations (as of latest version)

1. **Presence Validations**:
   - `start_time` - Required (string in HH:MM format)
   - `end_time` - Required (string in HH:MM format)
   - `participants` - Required (JSON array string)

2. **Format Validations**:
   - `start_time` - Must match `/\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/` (allows "9:30" or "09:30")
   - `end_time` - Must match same format

3. **Custom Validations**:
   - `participants` - Must be valid JSON array with ≥ 2 elements
   - `end_time` - Must be different from `start_time` (midnight wraparound allowed)

### Validation Timing

**Important**: Validations only run when:
- Creating new records (`Meeting.create`)
- Updating existing records (`meeting.update`)
- Explicitly calling `meeting.valid?`

**Validations DO NOT run when**:
- Loading records from database (`Meeting.all`, `Meeting.find`)
- Displaying records in views
- Reading attributes

This means **legacy data can always be loaded and displayed**, even if it doesn't meet current validation rules.

## Backward Compatibility Strategy

### 1. Defensive View Code

All views handle missing or nil data gracefully:

**app/views/meetings/_meeting.html.erb**:
```erb
<td><%= "#{meeting.start_time || '?'} - #{meeting.end_time || '?'}" %></td>
<td><%= meeting.participants_array.presence&.join(", ") || "(neznámí účastníci)" %></td>
<td><%= meeting.local_avg_duration ? "#{meeting.local_avg_duration} min" : "?" %></td>
<td><%= meeting.avg_delay ? "#{meeting.avg_delay} s" : "?" %></td>
```

### 2. Safe Helper Methods

The Meeting model provides crash-proof methods:

```ruby
# Returns empty array on JSON parse error
def participants_array
  return [] if participants.blank?
  JSON.parse(participants)
rescue JSON::ParserError
  []
end

# Check if meeting has complete data
def complete_data?
  start_time.present? &&
    end_time.present? &&
    participants.present? &&
    local_avg_duration.present? &&
    avg_delay.present?
end

# Display-safe participants string
def safe_participants_display
  arr = participants_array
  return "(neznámí účastníci)" if arr.empty?
  arr.join(", ")
end
```

### 3. Data Migration Tasks

Three rake tasks help manage legacy data:

#### Check Data Quality

```bash
rails data:meeting_data_quality
```

**Output**:
- Total meetings count
- Valid vs invalid meetings percentage
- Breakdown of specific issues (missing fields, invalid formats, etc.)

#### Validate Existing Data

```bash
rails data:validate_meetings
```

**Output**:
- Lists all invalid meetings with their specific validation errors
- Does not modify data
- Use for auditing before migration

#### Auto-Fix Legacy Data

```bash
rails data:fix_legacy_meetings
```

**Actions**:
- Sets default `start_time` to "09:00" if missing
- Sets default `end_time` to "10:00" if missing
- Reformats invalid time strings (e.g., "9.30" → "9:30")
- Sets default participants `["Unknown-1", "Unknown-2"]` if missing
- Converts non-array participants to arrays
- Adds second participant if only one exists
- Fixes malformed JSON
- Adjusts `end_time` if same as `start_time`

**Important**: This task saves records with `validate: false` to preserve legacy data that may not fully meet current standards.

## Migration Scenarios

### Scenario 1: Upgrading from Pre-Validation Version

**Situation**: Existing meetings created before validations were added.

**Steps**:
1. Deploy new code with validations
2. Legacy meetings remain readable
3. Run quality check:
   ```bash
   rails data:meeting_data_quality
   ```
4. If issues found, run auto-fix:
   ```bash
   rails data:fix_legacy_meetings
   ```
5. Verify results:
   ```bash
   rails data:validate_meetings
   ```

### Scenario 2: Database Import from External Source

**Situation**: Importing meetings from CSV or external database.

**Steps**:
1. Import data with `Meeting.create(validate: false)`
2. Run quality check to identify issues
3. Run auto-fix or manually correct specific records
4. Future edits will require valid data

### Scenario 3: Adding New Required Field

**Situation**: Adding validation for a previously optional field.

**Steps**:
1. **Before adding validation**:
   - Check existing data: `Meeting.where(new_field: nil).count`
   - Create migration to set defaults
   - Run migration: `rails db:migrate`
2. **After adding validation**:
   - New records require the field
   - Old records remain readable
   - Use `complete_data?` method to detect incomplete records

## Testing Validations

### Manual Testing

Run the included test script:

```bash
ruby test_meeting_model.rb
```

**Tests**:
- Valid meeting creation
- Invalid time formats (25:00)
- Single participant (should fail)
- Same start/end time (should fail)
- Midnight wraparound (should pass)
- Duration/delay formatting
- Missing required fields
- Malformed JSON
- Edge cases (single digit hours)

### Validation Check Script

Create test data:

```ruby
# Valid meeting
Meeting.create!(
  start_time: '09:30',
  end_time: '10:45',
  participants: '["Earth", "Mars"]',
  local_avg_duration: 75,
  avg_delay: 120
)

# Invalid meeting (bypassing validation)
Meeting.create(
  start_time: nil,
  end_time: nil,
  participants: '["OnlyOne"]',
  validate: false
)
```

Check validity:

```ruby
Meeting.all.each do |m|
  unless m.valid?
    puts "Meeting ##{m.id} is invalid:"
    puts m.errors.full_messages
  end
end
```

## Best Practices

### When Adding New Validations

1. **Check Existing Data First**:
   ```ruby
   # Count records that would fail new validation
   Meeting.where(field: nil).count
   ```

2. **Create Data Migration**:
   - Add rake task in `lib/tasks/data_migrations.rake`
   - Set reasonable defaults for missing data
   - Document what changes are made

3. **Test in Staging**:
   - Deploy to staging environment first
   - Run validation checks
   - Verify views display legacy data correctly

4. **Gradual Rollout**:
   - Add validation with `if: :new_record?` initially
   - Allows editing existing records without forcing immediate compliance
   - Example:
     ```ruby
     validates :new_field, presence: true, if: :new_record?
     ```

### When Editing Legacy Records

Users editing legacy records will be forced to provide valid data:

```ruby
# This will trigger validation
meeting.update(topic: "New topic")
# If meeting has invalid data, update fails with validation errors
```

**Solution**: Pre-validate before allowing edits:

```ruby
# In controller
def edit
  @meeting = Meeting.find(params[:id])
  unless @meeting.valid?
    flash[:warning] = "This meeting has incomplete data. Please fill all required fields."
    # Pre-populate missing fields with defaults
    @meeting.start_time ||= "09:00"
    @meeting.end_time ||= "10:00"
  end
  @bodies = extract_bodies_from_system
end
```

## Database Schema

```ruby
create_table "meetings", force: :cascade do |t|
  t.string "start_time"        # HH:MM format (nullable for legacy data)
  t.string "end_time"          # HH:MM format (nullable for legacy data)
  t.string "topic"             # Optional
  t.text "participants"       # JSON array string (nullable for legacy)
  t.float "local_avg_duration" # Minutes (nullable)
  t.float "avg_delay"         # Seconds (nullable)
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
end
```

**Note**: Fields are nullable at database level to support legacy data, but model validations enforce presence for new records.

## Rollback Strategy

If data migration causes issues:

### 1. Restore from Backup

```bash
# Restore database backup
cp db/backup/development.sqlite3 db/development.sqlite3
```

### 2. Disable Validations Temporarily

```ruby
# In app/models/meeting.rb
# Comment out validations temporarily
# validates :start_time, presence: true
# validates :end_time, presence: true
# etc.
```

### 3. Revert Auto-Fix

No automatic revert available. Use backup or manually correct records.

## Monitoring

### Production Health Checks

```ruby
# Add to health check endpoint
def meeting_data_health
  total = Meeting.count
  invalid = Meeting.select { |m| !m.valid? }.count

  {
    total_meetings: total,
    invalid_meetings: invalid,
    health_percentage: ((total - invalid).to_f / total * 100).round(2)
  }
end
```

### Logging

```ruby
# Log validation failures
Meeting.find_each do |meeting|
  unless meeting.valid?
    Rails.logger.warn "Invalid meeting detected: ##{meeting.id} - #{meeting.errors.full_messages.join(', ')}"
  end
end
```

## FAQ

### Q: Will existing meetings break after adding validations?

**A**: No. Validations only run on create/update, not on loading data. All existing meetings remain readable.

### Q: What happens when user edits a legacy meeting?

**A**: If the legacy meeting has invalid data, the update will fail with validation errors. User must fix the invalid fields.

### Q: Can I skip validations when importing data?

**A**: Yes, use `Meeting.create(data, validate: false)` or `meeting.save(validate: false)`.

### Q: How do I handle large datasets?

**A**: Use `find_each` for batch processing:
```ruby
Meeting.find_each(batch_size: 100) do |meeting|
  # Process meeting
end
```

### Q: Should I run fix_legacy_meetings in production?

**A**: Test in staging first. The task modifies data and cannot be automatically reverted. Always backup database before running.

## Summary

Gravikon's backward compatibility strategy ensures:

1. ✅ **Legacy data is always readable** - No crashes on invalid data
2. ✅ **Views handle missing data gracefully** - Display "?" or defaults
3. ✅ **Helper methods never throw exceptions** - Safe JSON parsing
4. ✅ **Automated migration tools available** - Rake tasks for data cleanup
5. ✅ **New records enforce quality** - Validations prevent future issues
6. ✅ **Gradual migration path** - Fix data at your own pace

**Golden Rule**: Validations guard the door for new data, but don't lock out existing residents.
