# frozen_string_literal: true

class AddSystemToMeetings < ActiveRecord::Migration[8.0]
  def change
    # Add system_id to track which system a meeting belongs to
    # For single-system meetings, this is the system where all participants are
    # For inter-system meetings, this can be the "primary" system or null
    add_column :meetings, :system_id, :integer, null: true

    # Add foreign key constraint (optional: true allows backwards compatibility)
    add_foreign_key :meetings, :systems, on_delete: :nullify

    # Add index for query performance
    add_index :meetings, :system_id

    # Add is_inter_system boolean to flag meetings spanning multiple systems
    add_column :meetings, :is_inter_system, :boolean, default: false, null: false

    # Add participant_systems JSON field to map participants to their system IDs
    # Format: { "participant_name" => system_id, ... }
    # Only used when is_inter_system is true
    add_column :meetings, :participant_systems, :text, null: true
  end
end
