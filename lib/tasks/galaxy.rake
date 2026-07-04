# frozen_string_literal: true

namespace :galaxy do
  desc "Rebuild all generated galaxy files (galaxy_data.json, system JSONs, SVGs) from the database"
  task rebuild: :environment do
    puts "Rebuilding galaxy data from #{System.count} database systems..."

    # 1. Rebuild galaxy_data.json from DB records
    GalaxyService.rebuild_galaxy_data!
    puts "  ✓ galaxy_data.json rebuilt"

    # 2. Regenerate any system whose data file is missing
    System.find_each do |system|
      if system.data_file_exists?
        puts "  ✓ #{system.name}: data file exists"
      else
        puts "  ⟳ #{system.name}: data file missing, regenerating..."
        RegenerateSystemJob.perform_now(system_id: system.id, num_planets: 5, max_moons: 2)
        puts "  ✓ #{system.name}: regenerated"
      end

      # Ensure the SVG exists too
      svg_path = GalaxyService.system_svg_path(system.system_id)
      next if svg_path && File.exist?(svg_path)

      data_path = system.data_file_path
      if data_path && File.exist?(data_path)
        PlanetarySystem.generate(json_path: data_path.to_s, system_id: system.system_id)
        puts "  ✓ #{system.name}: SVG rendered"
      end
    rescue => e
      puts "  ✗ #{system.name}: FAILED - #{e.message}"
    end

    # 3. Regenerate the galaxy map SVG
    GenerateGalaxyVisualizationJob.perform_now
    puts "  ✓ galaxy.svg rendered"

    Rails.cache.clear
    puts "Done. Caches cleared."
  end
end
