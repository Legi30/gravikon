# frozen_string_literal: true

namespace :data do
  desc "Validate existing meetings against current model validations"
  task validate_meetings: :environment do
    puts "=" * 80
    puts "VALIDATING EXISTING MEETINGS"
    puts "=" * 80
    puts

    total = Meeting.count
    puts "Total meetings: #{total}"

    if total.zero?
      puts "✓ No meetings to validate"
      next
    end

    invalid_count = 0
    errors_by_type = Hash.new(0)

    Meeting.find_each.with_index do |meeting, index|
      unless meeting.valid?
        invalid_count += 1
        puts "\n⚠️  Meeting ##{meeting.id} (#{index + 1}/#{total})"
        puts "  Start: #{meeting.start_time.inspect}"
        puts "  End: #{meeting.end_time.inspect}"
        puts "  Participants: #{meeting.participants.inspect}"
        puts "  Errors:"
        meeting.errors.full_messages.each do |error|
          puts "    - #{error}"
          errors_by_type[error] += 1
        end
      end
    end

    puts "\n" + "=" * 80
    if invalid_count.zero?
      puts "✓ All #{total} meetings are valid"
    else
      puts "⚠️  Found #{invalid_count} invalid meetings out of #{total}"
      puts "\nError summary:"
      errors_by_type.each do |error, count|
        puts "  • #{error}: #{count} occurrences"
      end
    end
    puts "=" * 80
  end

  desc "Fix legacy meeting data to comply with current validations"
  task fix_legacy_meetings: :environment do
    puts "=" * 80
    puts "FIXING LEGACY MEETING DATA"
    puts "=" * 80
    puts

    total = Meeting.count
    puts "Total meetings: #{total}"

    if total.zero?
      puts "✓ No meetings to fix"
      next
    end

    fixed_count = 0
    deleted_count = 0
    skip_count = 0

    # Disable validations temporarily to load legacy data
    Meeting.skip_callback(:validation, :before, :ensure_participants_json)
    Meeting.skip_callback(:validate, :after, :validate_participants_json)
    Meeting.skip_callback(:validate, :after, :validate_end_time_after_start_time)

    Meeting.find_each.with_index do |meeting, index|
      begin
        # Skip validation to check raw data
        next if meeting.valid?

        puts "\nProcessing meeting ##{meeting.id} (#{index + 1}/#{total})"
        fixed = false

        # Fix 1: NULL or blank start_time
        if meeting.start_time.blank?
          meeting.start_time = "09:00"
          puts "  ✓ Set default start_time: 09:00"
          fixed = true
        end

        # Fix 2: NULL or blank end_time
        if meeting.end_time.blank?
          meeting.end_time = "10:00"
          puts "  ✓ Set default end_time: 10:00"
          fixed = true
        end

        # Fix 3: Invalid time format - try to parse and reformat
        if meeting.start_time.present? && meeting.start_time !~ /\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/
          # Try to extract numbers
          if meeting.start_time =~ /(\d+)[:.](\d+)/
            hour = $1.to_i
            minute = $2.to_i
            if hour <= 23 && minute <= 59
              meeting.start_time = format("%d:%02d", hour, minute)
              puts "  ✓ Reformatted start_time to HH:MM format"
              fixed = true
            end
          end
        end

        if meeting.end_time.present? && meeting.end_time !~ /\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/
          if meeting.end_time =~ /(\d+)[:.](\d+)/
            hour = $1.to_i
            minute = $2.to_i
            if hour <= 23 && minute <= 59
              meeting.end_time = format("%d:%02d", hour, minute)
              puts "  ✓ Reformatted end_time to HH:MM format"
              fixed = true
            end
          end
        end

        # Fix 4: NULL or empty participants
        if meeting.participants.blank?
          meeting.participants = '["Unknown-1", "Unknown-2"]'
          puts "  ✓ Set default participants"
          fixed = true
        end

        # Fix 5: Invalid JSON participants
        begin
          parsed = JSON.parse(meeting.participants)

          # Fix 5a: Not an array
          unless parsed.is_a?(Array)
            meeting.participants = [parsed.to_s, "Unknown"].to_json
            puts "  ✓ Converted participants to array"
            fixed = true
            parsed = JSON.parse(meeting.participants)
          end

          # Fix 5b: Less than 2 participants
          if parsed.length < 2
            parsed << "Unknown-Participant"
            meeting.participants = parsed.to_json
            puts "  ✓ Added participant to meet minimum requirement (2)"
            fixed = true
          end
        rescue JSON::ParserError
          meeting.participants = '["Unknown-1", "Unknown-2"]'
          puts "  ✓ Replaced invalid JSON with default participants"
          fixed = true
        end

        # Fix 6: Same start and end time
        if meeting.start_time == meeting.end_time
          # Add 1 hour to end time
          parts = meeting.end_time.split(":")
          hour = (parts[0].to_i + 1) % 24
          meeting.end_time = format("%d:%02d", hour, parts[1].to_i)
          puts "  ✓ Adjusted end_time to differ from start_time"
          fixed = true
        end

        if fixed
          # Save without validation to preserve legacy data
          if meeting.save(validate: false)
            fixed_count += 1
            puts "  ✓ Fixed and saved meeting ##{meeting.id}"
          else
            puts "  ✗ Failed to save meeting ##{meeting.id}"
            skip_count += 1
          end
        else
          skip_count += 1
        end

      rescue => e
        puts "  ✗ Error processing meeting ##{meeting.id}: #{e.message}"
        skip_count += 1
      end
    end

    # Re-enable validations
    Meeting.set_callback(:validation, :before, :ensure_participants_json)
    Meeting.set_callback(:validate, :after, :validate_participants_json)
    Meeting.set_callback(:validate, :after, :validate_end_time_after_start_time)

    puts "\n" + "=" * 80
    puts "SUMMARY:"
    puts "  Fixed: #{fixed_count}"
    puts "  Skipped: #{skip_count}"
    puts "  Deleted: #{deleted_count}"
    puts "  Total processed: #{total}"
    puts "=" * 80
  end

  desc "Report on meeting data quality"
  task meeting_data_quality: :environment do
    puts "=" * 80
    puts "MEETING DATA QUALITY REPORT"
    puts "=" * 80
    puts

    total = Meeting.count
    puts "Total meetings: #{total}"

    if total.zero?
      puts "No meetings in database"
      next
    end

    # Statistics
    stats = {
      valid: 0,
      invalid: 0,
      missing_start: 0,
      missing_end: 0,
      invalid_time_format: 0,
      missing_participants: 0,
      invalid_json: 0,
      single_participant: 0,
      same_times: 0
    }

    Meeting.find_each do |meeting|
      if meeting.valid?
        stats[:valid] += 1
      else
        stats[:invalid] += 1

        stats[:missing_start] += 1 if meeting.start_time.blank?
        stats[:missing_end] += 1 if meeting.end_time.blank?

        if meeting.start_time.present? && meeting.start_time !~ /\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/
          stats[:invalid_time_format] += 1
        end

        if meeting.end_time.present? && meeting.end_time !~ /\A([0-1]?[0-9]|2[0-3]):[0-5][0-9]\z/
          stats[:invalid_time_format] += 1
        end

        stats[:missing_participants] += 1 if meeting.participants.blank?

        if meeting.participants.present?
          begin
            parsed = JSON.parse(meeting.participants)
            stats[:single_participant] += 1 if parsed.is_a?(Array) && parsed.length < 2
          rescue JSON::ParserError
            stats[:invalid_json] += 1
          end
        end

        stats[:same_times] += 1 if meeting.start_time == meeting.end_time
      end
    end

    puts "\nData Quality Metrics:"
    puts "  ✓ Valid meetings: #{stats[:valid]} (#{(stats[:valid].to_f / total * 100).round(1)}%)"
    puts "  ⚠️  Invalid meetings: #{stats[:invalid]} (#{(stats[:invalid].to_f / total * 100).round(1)}%)"

    if stats[:invalid] > 0
      puts "\nIssue Breakdown:"
      puts "  • Missing start_time: #{stats[:missing_start]}" if stats[:missing_start] > 0
      puts "  • Missing end_time: #{stats[:missing_end]}" if stats[:missing_end] > 0
      puts "  • Invalid time format: #{stats[:invalid_time_format]}" if stats[:invalid_time_format] > 0
      puts "  • Missing participants: #{stats[:missing_participants]}" if stats[:missing_participants] > 0
      puts "  • Invalid JSON: #{stats[:invalid_json]}" if stats[:invalid_json] > 0
      puts "  • Single participant: #{stats[:single_participant]}" if stats[:single_participant] > 0
      puts "  • Same start/end time: #{stats[:same_times]}" if stats[:same_times] > 0
    end

    puts "\n" + "=" * 80
    puts "Use 'rails data:fix_legacy_meetings' to auto-fix issues"
    puts "=" * 80
  end

  desc "Verify consistency between galaxy_data.json and System database"
  task verify_galaxy_consistency: :environment do
    puts "=" * 80
    puts "GALAXY DATA CONSISTENCY CHECK"
    puts "=" * 80
    puts

    galaxy_file = Rails.root.join('data', 'galaxy_data.json')

    unless File.exist?(galaxy_file)
      puts "⚠️  galaxy_data.json not found at #{galaxy_file}"
      puts "Run 'rails runner \"GalaxyVisualizer.generate\"' to create it"
      next
    end

    galaxy_data = JSON.parse(File.read(galaxy_file))
    json_systems = galaxy_data['systems'] || []
    db_systems = System.all.to_a

    puts "Systems in galaxy_data.json: #{json_systems.count}"
    puts "Systems in database: #{db_systems.count}"
    puts

    issues = []

    # Check 1: Systems in JSON but not in database
    json_systems.each do |json_system|
      system_id = json_system['id']
      db_system = db_systems.find do |s|
        File.basename(s.json_file_path, '.json') == system_id.to_s
      end

      unless db_system
        issues << "System '#{system_id}' exists in galaxy_data.json but not in database"
      end
    end

    # Check 2: Systems in database but not in JSON
    db_systems.each do |db_system|
      system_id = File.basename(db_system.json_file_path, '.json')
      json_system = json_systems.find { |s| s['id'].to_s == system_id.to_s }

      unless json_system
        issues << "System '#{db_system.name}' (ID: #{system_id}) exists in database but not in galaxy_data.json"
      end
    end

    # Check 3: Coordinate mismatches
    db_systems.each do |db_system|
      system_id = File.basename(db_system.json_file_path, '.json')
      json_system = json_systems.find { |s| s['id'].to_s == system_id.to_s }

      if json_system
        json_x = json_system['x'].to_f
        json_y = json_system['y'].to_f
        db_x = db_system.x.to_f
        db_y = db_system.y.to_f

        if (json_x - db_x).abs > 0.01 || (json_y - db_y).abs > 0.01
          issues << "System '#{db_system.name}' (ID: #{system_id}) coordinate mismatch: DB=(#{db_x}, #{db_y}), JSON=(#{json_x}, #{json_y})"
        end
      end
    end

    if issues.empty?
      puts "✓ No consistency issues found"
      puts "  All systems are synchronized between galaxy_data.json and database"
    else
      puts "⚠️  Found #{issues.count} consistency issues:"
      puts
      issues.each_with_index do |issue, index|
        puts "  #{index + 1}. #{issue}"
      end
      puts
      puts "Run 'rails data:sync_galaxy_data' to fix these issues"
    end

    puts "=" * 80
  end

  desc "Synchronize galaxy_data.json with System database (DB is source of truth)"
  task sync_galaxy_data: :environment do
    puts "=" * 80
    puts "SYNCHRONIZING GALAXY DATA"
    puts "=" * 80
    puts
    puts "Using database as source of truth..."
    puts

    galaxy_file = Rails.root.join('data', 'galaxy_data.json')

    # Load or create galaxy data
    if File.exist?(galaxy_file)
      galaxy_data = JSON.parse(File.read(galaxy_file))
    else
      puts "Creating new galaxy_data.json..."
      galaxy_data = GalaxyService.send(:create_default_galaxy_data)
    end

    # Rebuild systems array from database
    db_systems = System.all.to_a
    new_systems = []

    db_systems.each do |db_system|
      system_id = File.basename(db_system.json_file_path, '.json')
      new_systems << {
        'id' => system_id,
        'x' => db_system.x.to_f,
        'y' => db_system.y.to_f
      }
      puts "  ✓ Added system '#{db_system.name}' (ID: #{system_id}) at (#{db_system.x}, #{db_system.y})"
    end

    galaxy_data['systems'] = new_systems

    # Save updated galaxy data
    File.write(galaxy_file, JSON.pretty_generate(galaxy_data))
    puts
    puts "✓ Saved #{new_systems.count} systems to galaxy_data.json"

    # Clear caches
    GalaxyService.clear_galaxy_cache
    GalaxyService.clear_all_system_caches
    puts "✓ Cleared galaxy caches"

    # Regenerate galaxy SVG
    begin
      GalaxyVisualizer.generate
      puts "✓ Regenerated galaxy.svg"
    rescue => e
      puts "⚠️  Failed to regenerate galaxy.svg: #{e.message}"
    end

    puts "=" * 80
    puts "Synchronization complete!"
    puts "=" * 80
  end

  desc "Clean up orphaned system files (data and SVG files without database records)"
  task cleanup_orphaned_system_files: :environment do
    puts "=" * 80
    puts "CLEANING UP ORPHANED SYSTEM FILES"
    puts "=" * 80
    puts

    # Get all system IDs from database
    db_system_ids = System.all.map do |system|
      File.basename(system.json_file_path, '.json')
    end

    puts "Systems in database: #{db_system_ids.count}"
    puts

    orphaned_data_files = []
    orphaned_svg_files = []

    # Check data/systems directory
    systems_data_dir = Rails.root.join('data', 'systems')
    if Dir.exist?(systems_data_dir)
      Dir.glob(File.join(systems_data_dir, '*.json')).each do |file|
        system_id = File.basename(file, '.json')
        unless db_system_ids.include?(system_id)
          orphaned_data_files << file
        end
      end
    end

    # Check public/systems directory
    systems_svg_dir = Rails.root.join('public', 'systems')
    if Dir.exist?(systems_svg_dir)
      Dir.glob(File.join(systems_svg_dir, '*.svg')).each do |file|
        system_id = File.basename(file, '.svg')
        unless db_system_ids.include?(system_id)
          orphaned_svg_files << file
        end
      end
    end

    total_orphaned = orphaned_data_files.count + orphaned_svg_files.count

    if total_orphaned == 0
      puts "✓ No orphaned files found"
    else
      puts "⚠️  Found #{total_orphaned} orphaned files:"
      puts

      if orphaned_data_files.any?
        puts "Orphaned data files (#{orphaned_data_files.count}):"
        orphaned_data_files.each do |file|
          puts "  • #{file}"
        end
        puts
      end

      if orphaned_svg_files.any?
        puts "Orphaned SVG files (#{orphaned_svg_files.count}):"
        orphaned_svg_files.each do |file|
          puts "  • #{file}"
        end
        puts
      end

      print "Delete these files? (y/N): "
      response = STDIN.gets.chomp.downcase

      if response == 'y'
        deleted_count = 0

        orphaned_data_files.each do |file|
          File.delete(file)
          puts "  ✓ Deleted: #{file}"
          deleted_count += 1
        end

        orphaned_svg_files.each do |file|
          File.delete(file)
          puts "  ✓ Deleted: #{file}"
          deleted_count += 1
        end

        puts
        puts "✓ Deleted #{deleted_count} orphaned files"
      else
        puts "Cleanup cancelled"
      end
    end

    puts "=" * 80
  end
end
