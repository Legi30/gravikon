# frozen_string_literal: true

# Nightly demo reset — wipes everything users created/broke during the day
# and rebuilds a predefined demo galaxy so the app starts each morning fresh
# and prefilled.
#
# Cron example (3:00 every night):
#   0 3 * * * cd /path/to/gravikon && RAILS_ENV=production bin/rails demo:reset >> log/demo_reset.log 2>&1
namespace :demo do
  # Predefined demo galaxy: positions are spread safely (>= 50 units from the
  # black hole at (400,400), >= 40 units apart) and deliberately sit at
  # DIFFERENT distances from the black hole so each system has its own orbit
  # ring (radii ~100 / 160 / 300 / 350: the inner two sit deep in the black
  # hole's well, so its effect dominates). Bodies are generated randomly each
  # reset, so the demo stays varied while the structure is stable. Alfa
  # Centauri is a binary star, like the real one (A + B).
  DEMO_SYSTEMS = [
    { name: "Alfa Centauri", x: 314.0, y: 350.0, planets: 5, moons: 2, binary: true },
    { name: "Kepler-442",    x: 551.0, y: 455.0, planets: 7, moons: 1 },
    { name: "Trappist",      x: 250.0, y: 660.0, planets: 4, moons: 3 },
    { name: "Proxima",       x: 668.0, y: 175.0, planets: 3, moons: 2 }
  ].freeze

  desc "Reset the whole database and generated files to the predefined demo state"
  task reset: :environment do
    puts "[demo:reset] #{Time.current} — wiping current data..."

    # 1. Wipe database records (System callbacks remove data files, SVGs and
    #    galaxy_data entries; meetings go first because of the FK)
    Meeting.delete_all
    System.destroy_all

    # 2. Wipe any orphaned generated files and rebuild an empty galaxy file
    FileUtils.rm_rf(GalaxyService.systems_data_dir)
    FileUtils.rm_rf(GalaxyService.systems_svg_dir)
    FileUtils.rm_f(GalaxyService.galaxy_data_path)
    FileUtils.rm_f(GalaxyService.galaxy_svg_path)
    Rails.cache.clear
    GalaxyService.rebuild_galaxy_data!

    # 3. Create the demo systems (synchronously — cron has no job worker)
    systems = DEMO_SYSTEMS.map do |cfg|
      file_id = SecureRandom.uuid
      system = System.create!(
        name: cfg[:name],
        x: cfg[:x],
        y: cfg[:y],
        json_file_path: "data/systems/#{file_id}.json",
        # Permanent: no editing, regenerating or deleting from the UI
        core: true
      )
      GenerateSystemJob.perform_now(
        system_id: file_id,
        system_name: cfg[:name],
        system_x: cfg[:x],
        system_y: cfg[:y],
        num_planets: cfg[:planets],
        max_moons: cfg[:moons],
        binary: cfg.fetch(:binary, false)
      )
      puts "[demo:reset]   ✓ #{cfg[:name]} (#{cfg[:planets]} planet)"
      system
    end

    # 4. Seed a few meetings so the lists and dashboard aren't empty
    calculator = RelativisticCalculator.new

    create_meeting = lambda do |attrs|
      Meeting.create!(attrs)
    rescue => e
      puts "[demo:reset]   ✗ meeting skipped: #{e.message}"
      nil
    end

    intra_topics = [ "Ranní synchronizace orbit", "Porada o gravitačních vlnách", "Kalibrace časové dilatace" ]
    systems.first(3).each_with_index do |system, i|
      bodies = system.load_system_data&.dig("bodies") || []
      next if bodies.size < 3

      participants = bodies.sample(3)
      start_time = format("%02d:00", 9 + i * 2)
      end_time = format("%02d:30", 10 + i * 2)
      stats = calculator.calculate_meeting_statistics(
        participants.map { |b| { body: b, system_id: system.id } },
        start_time: start_time, end_time: end_time
      )

      create_meeting.call(
        start_time: start_time,
        end_time: end_time,
        topic: intra_topics[i],
        participants: participants.map { |b| b["name"] }.to_json,
        system_id: system.id,
        is_inter_system: false,
        local_avg_duration: stats[:avg_duration],
        avg_delay: stats[:avg_delay]
      )
    end

    # One inter-system meeting between the first two systems
    if systems.size >= 2
      sys1, sys2 = systems.first(2)
      body1 = sys1.load_system_data&.dig("bodies")&.first
      body2 = sys2.load_system_data&.dig("bodies")&.first

      if body1 && body2
        participant_systems = { body1["name"] => sys1.id, body2["name"] => sys2.id }
        stats = calculator.calculate_meeting_statistics(
          [ { body: body1, system_id: sys1.id }, { body: body2, system_id: sys2.id } ],
          start_time: "14:00", end_time: "15:30"
        )

        create_meeting.call(
          start_time: "14:00",
          end_time: "15:30",
          topic: "Mezisystémový summit",
          participants: [ body1["name"], body2["name"] ].to_json,
          participant_systems: participant_systems.to_json,
          is_inter_system: true,
          local_avg_duration: stats[:avg_duration],
          avg_delay: stats[:avg_delay]
        )
      end
    end

    # 5. Render the galaxy map and warm up
    GenerateGalaxyVisualizationJob.perform_now
    Rails.cache.clear

    puts "[demo:reset] Done: #{System.count} systems, #{Meeting.count} meetings."
  end
end
