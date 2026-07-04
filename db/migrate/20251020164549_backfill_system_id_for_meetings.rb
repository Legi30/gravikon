# frozen_string_literal: true

# Data migration to backfill system_id for existing meetings
# This migration is part of the multi-system feature rollout
#
# Context:
# - The Meeting model now has a system_id column (added in previous migration)
# - Existing meetings from single-system era have NULL system_id
# - This migration sets system_id to the default/first system for those meetings
#
# Note: This migration is safe to run multiple times (idempotent)
class BackfillSystemIdForMeetings < ActiveRecord::Migration[8.0]
  def up
    # Only proceed if there are meetings without system_id
    meetings_without_system = Meeting.where(system_id: nil).count

    if meetings_without_system.zero?
      puts "  ✓ All meetings already have system_id - skipping backfill"
      return
    end

    puts "  → Found #{meetings_without_system} meeting(s) without system_id"

    # Find the default system (created by migration rake task)
    # The rake task creates a system with json_file_path 'data/systems/default_system.json'
    default_system = System.find_by(json_file_path: 'data/systems/default_system.json')

    # If default system doesn't exist, try to find the first system
    default_system ||= System.order(:created_at).first

    unless default_system
      puts "  ⚠ WARNING: No system found in database"
      puts "     Meetings will remain with NULL system_id"
      puts "     Run 'rake data:migrate_to_multi_system' to create the default system"
      return
    end

    # Backfill system_id for meetings that don't have one
    updated_count = Meeting.where(system_id: nil).update_all(system_id: default_system.id)

    puts "  ✓ Updated #{updated_count} meeting(s) to use system '#{default_system.name}' (ID: #{default_system.id})"
  end

  def down
    # Rollback: Set system_id back to NULL for meetings that reference the default system
    # This is a conservative rollback - we only reset meetings from the default system
    default_system = System.find_by(json_file_path: 'data/systems/default_system.json')

    if default_system
      count = Meeting.where(system_id: default_system.id).count
      if count > 0
        Meeting.where(system_id: default_system.id).update_all(system_id: nil)
        puts "  ✓ Reset #{count} meeting(s) back to NULL system_id"
      else
        puts "  ✓ No meetings to reset"
      end
    else
      puts "  ⚠ Default system not found - nothing to rollback"
    end
  end
end
