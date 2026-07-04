# frozen_string_literal: true

namespace :data do
  desc "Migrate existing single-system data to multi-system structure"
  task migrate_to_multi_system: :environment do
    puts "=" * 80
    puts "MIGRATION: Single-System to Multi-System Structure"
    puts "=" * 80
    puts ""

    # Check if migration has already been run
    migration_flag = Rails.root.join('data', '.migration_complete')
    if File.exist?(migration_flag)
      puts "✓ Migration has already been completed."
      puts "  Flag file exists at: #{migration_flag}"
      puts "  Migration was completed at: #{File.mtime(migration_flag)}"
      puts ""
      puts "To re-run migration, first rollback:"
      puts "  rake data:rollback_multi_system"
      puts ""
      puts "Or force re-run (DANGEROUS - may create duplicates):"
      puts "  rm #{migration_flag}"
      puts "  rm -rf data/backup/"
      puts ""
      exit 0
    end

    puts "⚠ IDEMPOTENCY NOTE: This migration can be safely interrupted and re-run."
    puts "  Each step checks for existing data before making changes."
    puts ""

    # Track that migration has started (for partial completion detection)
    progress_file = Rails.root.join('data', '.migration_in_progress')
    if File.exist?(progress_file)
      puts "⚠ DETECTED PREVIOUS INCOMPLETE MIGRATION"
      puts "  Started at: #{File.mtime(progress_file)}"
      puts "  Resuming migration (all steps are idempotent)..."
      puts ""
    else
      File.write(progress_file, "Migration started at #{Time.current}\n")
    end

    puts "Step 1: Pre-flight checks"
    puts "-" * 80

    # Check for legacy system data file
    legacy_system_file = Rails.root.join('data', 'system_data.json')
    unless File.exist?(legacy_system_file)
      puts "⚠ Legacy system file not found: #{legacy_system_file}"
      puts "  This is expected for new installations. Skipping migration."
      File.write(migration_flag, "Migration skipped - no legacy data found\n#{Time.current}")
      exit 0
    end

    puts "✓ Found legacy system file: #{legacy_system_file}"

    # Parse legacy data
    begin
      legacy_data = JSON.parse(File.read(legacy_system_file))
      puts "✓ Legacy system data is valid JSON"
      puts "  Bodies in legacy system: #{legacy_data['bodies']&.count || 0}"
    rescue JSON::ParserError => e
      puts "✗ ERROR: Failed to parse legacy system data: #{e.message}"
      exit 1
    end

    puts ""
    puts "Step 2: Create backup directory"
    puts "-" * 80

    backup_dir = Rails.root.join('data', 'backup')
    FileUtils.mkdir_p(backup_dir)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    puts "✓ Created backup directory: #{backup_dir}"

    # Backup legacy files
    if File.exist?(legacy_system_file)
      backup_file = backup_dir.join("system_data_#{timestamp}.json")
      FileUtils.cp(legacy_system_file, backup_file)
      puts "✓ Backed up: system_data.json → #{backup_file}"
    end

    legacy_svg = Rails.root.join('public', 'system.svg')
    if File.exist?(legacy_svg)
      backup_svg = backup_dir.join("system_#{timestamp}.svg")
      FileUtils.cp(legacy_svg, backup_svg)
      puts "✓ Backed up: system.svg → #{backup_svg}"
    end

    puts ""
    puts "Step 3: Create directory structure"
    puts "-" * 80

    systems_dir = Rails.root.join('data', 'systems')
    FileUtils.mkdir_p(systems_dir)
    puts "✓ Created/verified: #{systems_dir}"

    systems_svg_dir = Rails.root.join('public', 'systems')
    FileUtils.mkdir_p(systems_svg_dir)
    puts "✓ Created/verified: #{systems_svg_dir}"

    puts ""
    puts "Step 4: Generate system ID and create System record"
    puts "-" * 80

    # Use a deterministic ID for the default system
    system_id = 'default_system'
    system_name = 'Default System'

    # Check if system already exists
    existing_system = System.find_by(json_file_path: "data/systems/#{system_id}.json")
    if existing_system
      puts "⚠ System record already exists: #{existing_system.name} (ID: #{existing_system.id})"
      system = existing_system
    else
      # Create System record with default galaxy position
      system = System.new(
        name: system_name,
        x: 400.0,  # Center of galaxy (horizontally)
        y: 250.0,  # Slightly above center
        json_file_path: "data/systems/#{system_id}.json"
      )

      if system.save
        puts "✓ Created System record: #{system.name} (ID: #{system.id})"
        puts "  Position: (#{system.x}, #{system.y})"
        puts "  File path: #{system.json_file_path}"
      else
        puts "✗ ERROR: Failed to create System record:"
        system.errors.full_messages.each do |msg|
          puts "    - #{msg}"
        end
        exit 1
      end
    end

    puts ""
    puts "Step 5: Copy system data to new location"
    puts "-" * 80

    new_system_file = Rails.root.join(system.json_file_path)
    if File.exist?(new_system_file)
      puts "⚠ System data file already exists: #{new_system_file}"
    else
      FileUtils.cp(legacy_system_file, new_system_file)
      puts "✓ Copied: system_data.json → #{new_system_file}"
    end

    puts ""
    puts "Step 6: Update or create galaxy_data.json"
    puts "-" * 80

    galaxy_file = Rails.root.join('data', 'galaxy_data.json')

    if File.exist?(galaxy_file)
      # Galaxy file exists - check if it already has this system
      galaxy_data = JSON.parse(File.read(galaxy_file))
      existing_entry = galaxy_data['systems']&.find { |s| s['id'] == system_id }

      if existing_entry
        puts "⚠ Galaxy already contains this system: #{system_id}"
      else
        # Add system to existing galaxy
        galaxy_data['systems'] ||= []
        galaxy_data['systems'] << {
          'id' => system_id,
          'x' => system.x,
          'y' => system.y
        }
        File.write(galaxy_file, JSON.pretty_generate(galaxy_data))
        puts "✓ Added system to existing galaxy_data.json"
      end
    else
      # Create new galaxy file
      # Sagittarius A* has mass of ~4.1 million solar masses
      black_hole_mass = 8.2e36

      galaxy_data = {
        'black_hole' => {
          'name' => 'Sagittarius Omega',
          'mass' => black_hole_mass,
          'x' => 400,
          'y' => 400,
          'schwarzschild_radius' => 2 * 0.0001 * black_hole_mass / (10_000_000**2),
          'dilation' => 0.0,
          'type' => 'black_hole'
        },
        'systems' => [
          {
            'id' => system_id,
            'x' => system.x,
            'y' => system.y
          }
        ]
      }

      File.write(galaxy_file, JSON.pretty_generate(galaxy_data))
      puts "✓ Created galaxy_data.json with default system"
    end

    puts ""
    puts "Step 7: Migrate existing meetings"
    puts "-" * 80

    meetings_without_system = Meeting.where(system_id: nil)
    count = meetings_without_system.count

    if count.zero?
      puts "✓ No meetings need migration (all have system_id)"
    else
      updated = meetings_without_system.update_all(system_id: system.id)
      puts "✓ Updated #{updated} meeting(s) to use system ID: #{system.id}"
    end

    puts ""
    puts "Step 8: Migrate SVG files"
    puts "-" * 80

    if File.exist?(legacy_svg)
      new_svg_path = Rails.root.join('public', 'systems', "#{system_id}.svg")
      if File.exist?(new_svg_path)
        puts "⚠ System SVG already exists: #{new_svg_path}"
      else
        FileUtils.cp(legacy_svg, new_svg_path)
        puts "✓ Copied: system.svg → #{new_svg_path}"
      end
    else
      puts "⚠ No legacy system.svg found - will be generated on demand"
    end

    puts ""
    puts "Step 9: Generate galaxy SVG"
    puts "-" * 80

    begin
      require_relative '../../lib/galaxy_visualizer'
      GalaxyVisualizer.generate
      puts "✓ Generated galaxy.svg"
    rescue => e
      puts "⚠ Warning: Could not generate galaxy.svg: #{e.message}"
      puts "  This will be generated automatically on first view"
    end

    puts ""
    puts "Step 10: Clear caches"
    puts "-" * 80

    begin
      Rails.cache.clear
      puts "✓ Cleared Rails cache"
    rescue => e
      puts "⚠ Warning: Failed to clear cache: #{e.message}"
    end

    puts ""
    puts "Step 11: Mark migration as complete"
    puts "-" * 80

    migration_log = <<~LOG
      Migration completed successfully at #{Time.current}

      System created:
        - ID: #{system.id}
        - Name: #{system.name}
        - File: #{system.json_file_path}
        - Position: (#{system.x}, #{system.y})

      Meetings migrated: #{count}

      Backups saved to: #{backup_dir}
    LOG

    File.write(migration_flag, migration_log)
    puts "✓ Created migration flag: #{migration_flag}"

    # Clean up progress tracking file
    if File.exist?(progress_file)
      FileUtils.rm(progress_file)
      puts "✓ Removed progress tracking file"
    end

    puts ""
    puts "=" * 80
    puts "MIGRATION COMPLETE"
    puts "=" * 80
    puts ""
    puts "Summary:"
    puts "  • System '#{system.name}' created (ID: #{system.id})"
    puts "  • #{count} meeting(s) migrated"
    puts "  • Legacy files backed up to: #{backup_dir}"
    puts "  • New structure ready at: data/systems/"
    puts ""
    puts "Next steps:"
    puts "  • View galaxy map at /galaxy"
    puts "  • Legacy files (system_data.json, system.svg) can be kept for reference"
    puts "  • Or run: rake data:cleanup_legacy_files"
    puts ""
  end

  desc "Rollback multi-system migration"
  task rollback_multi_system: :environment do
    puts "=" * 80
    puts "ROLLBACK: Multi-System Migration"
    puts "=" * 80
    puts ""

    # Check if migration was completed
    migration_flag = Rails.root.join('data', '.migration_complete')
    unless File.exist?(migration_flag)
      puts "⚠ Migration flag not found - nothing to rollback"
      exit 0
    end

    puts "Migration flag found. Reading migration log..."
    puts ""
    puts File.read(migration_flag)
    puts ""

    print "Are you sure you want to rollback the migration? (yes/no): "
    confirmation = STDIN.gets.chomp.downcase

    unless confirmation == 'yes'
      puts "Rollback cancelled."
      exit 0
    end

    puts ""
    puts "Step 1: Find backup files"
    puts "-" * 80

    backup_dir = Rails.root.join('data', 'backup')
    unless Dir.exist?(backup_dir)
      puts "✗ ERROR: Backup directory not found: #{backup_dir}"
      puts "Cannot rollback without backups."
      exit 1
    end

    # Find most recent backups
    backup_json = Dir.glob(backup_dir.join('system_data_*.json')).max
    backup_svg = Dir.glob(backup_dir.join('system_*.svg')).max

    if backup_json
      puts "✓ Found backup: #{File.basename(backup_json)}"
    else
      puts "✗ No backup JSON found"
      exit 1
    end

    puts ""
    puts "Step 2: Restore legacy files"
    puts "-" * 80

    # Restore system_data.json
    legacy_system_file = Rails.root.join('data', 'system_data.json')
    FileUtils.cp(backup_json, legacy_system_file)
    puts "✓ Restored: #{legacy_system_file}"

    # Restore system.svg if backup exists
    if backup_svg
      legacy_svg = Rails.root.join('public', 'system.svg')
      FileUtils.cp(backup_svg, legacy_svg)
      puts "✓ Restored: #{legacy_svg}"
    end

    puts ""
    puts "Step 3: Remove migrated System record"
    puts "-" * 80

    # Find the default system
    system = System.find_by(json_file_path: 'data/systems/default_system.json')
    if system
      # Reset meetings back to nil
      meeting_count = Meeting.where(system_id: system.id).count
      Meeting.where(system_id: system.id).update_all(system_id: nil)
      puts "✓ Reset #{meeting_count} meeting(s)"

      system_id_value = system.id
      system.destroy
      puts "✓ Removed System record (ID: #{system_id_value})"
    else
      puts "⚠ Default system not found in database"
    end

    puts ""
    puts "Step 4: Clean up migrated files"
    puts "-" * 80

    migrated_json = Rails.root.join('data', 'systems', 'default_system.json')
    if File.exist?(migrated_json)
      FileUtils.rm(migrated_json)
      puts "✓ Removed: #{migrated_json}"
    end

    migrated_svg = Rails.root.join('public', 'systems', 'default_system.svg')
    if File.exist?(migrated_svg)
      FileUtils.rm(migrated_svg)
      puts "✓ Removed: #{migrated_svg}"
    end

    puts ""
    puts "Step 5: Clear caches"
    puts "-" * 80

    begin
      Rails.cache.clear
      puts "✓ Cleared Rails cache"
    rescue => e
      puts "⚠ Warning: Failed to clear cache: #{e.message}"
    end

    puts ""
    puts "Step 6: Remove migration flags"
    puts "-" * 80

    FileUtils.rm(migration_flag)
    puts "✓ Removed migration flag"

    # Also remove progress file if it exists
    progress_file = Rails.root.join('data', '.migration_in_progress')
    if File.exist?(progress_file)
      FileUtils.rm(progress_file)
      puts "✓ Removed progress file"
    end

    puts ""
    puts "=" * 80
    puts "ROLLBACK COMPLETE"
    puts "=" * 80
    puts ""
    puts "The application has been restored to single-system mode."
    puts "Legacy files have been restored from backup."
    puts ""
  end

  desc "Clean up legacy single-system files after successful migration"
  task cleanup_legacy_files: :environment do
    puts "=" * 80
    puts "CLEANUP: Legacy Single-System Files"
    puts "=" * 80
    puts ""

    # Check if migration was completed
    migration_flag = Rails.root.join('data', '.migration_complete')
    unless File.exist?(migration_flag)
      puts "⚠ Migration not completed - cannot cleanup"
      puts "  Run: rake data:migrate_to_multi_system first"
      exit 0
    end

    puts "Warning: This will delete legacy files (backups will remain)"
    print "Continue? (yes/no): "
    confirmation = STDIN.gets.chomp.downcase

    unless confirmation == 'yes'
      puts "Cleanup cancelled."
      exit 0
    end

    puts ""
    puts "Removing legacy files..."
    puts "-" * 80

    legacy_system_file = Rails.root.join('data', 'system_data.json')
    if File.exist?(legacy_system_file)
      FileUtils.rm(legacy_system_file)
      puts "✓ Removed: system_data.json"
    end

    legacy_svg = Rails.root.join('public', 'system.svg')
    if File.exist?(legacy_svg)
      FileUtils.rm(legacy_svg)
      puts "✓ Removed: system.svg"
    end

    puts ""
    puts "Cleanup complete. Backups remain in data/backup/"
    puts ""
  end
end
