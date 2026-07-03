# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'system_generator'

# Legacy command-line interface for system generation
# Maintains backward compatibility with original generator.rb
# For new code, use SystemGenerator class instead
#
# Usage:
#   ruby lib/generator.rb <num_planets> <max_moons>
#   ruby lib/generator.rb <num_planets> <max_moons> <system_id> <output_path>

# === Parse command-line arguments ===
if ARGV.length >= 2
  begin
    num_planets = Integer(ARGV[0])
    max_moons_per_planet = Integer(ARGV[1])
    system_id = ARGV[2] || 'default'
    output_path = ARGV[3] # Optional custom output path

    # Validace rozsahů
    unless num_planets.between?(1, 10)
      STDERR.puts "Error: NUM_PLANETS must be between 1 and 10, got #{num_planets}"
      exit 1
    end

    unless max_moons_per_planet.between?(0, 5)
      STDERR.puts "Error: MAX_MOONS_PER_PLANET must be between 0 and 5, got #{max_moons_per_planet}"
      exit 1
    end
  rescue ArgumentError => e
    STDERR.puts "Error: Invalid arguments. Both must be integers. #{e.message}"
    exit 1
  end
else
  # Výchozí hodnoty pokud argumenty nejsou poskytnuty
  num_planets = 5
  max_moons_per_planet = 2
  system_id = 'default'
  output_path = nil
  STDERR.puts "Warning: Using default values (num_planets=#{num_planets}, max_moons_per_planet=#{max_moons_per_planet})"
end

# === Generate system using SystemGenerator ===
begin
  # Create generator instance
  generator = SystemGenerator.new(
    system_id: system_id,
    system_name: "System #{system_id}",
    num_planets: num_planets,
    max_moons_per_planet: max_moons_per_planet
  )

  # Generate system data
  system_data = generator.generate

  unless system_data
    STDERR.puts "Error: Failed to generate system"
    STDERR.puts "Errors: #{generator.errors.join(', ')}" unless generator.errors.empty?
    exit 1
  end

  # Determine output path
  if output_path
    # Custom output path provided
    final_output_path = output_path
  elsif system_id == 'default'
    # Backward compatibility: write to old location for 'default' system
    final_output_path = 'data/system_data.json'
  else
    # New multi-system path
    final_output_path = "data/systems/#{system_id}.json"
  end

  # Ensure directory exists
  require 'fileutils'
  FileUtils.mkdir_p(File.dirname(final_output_path))

  # Write output file
  File.open(final_output_path, 'w') do |f|
    # For backward compatibility with old format, only write bodies array for 'default'
    if system_id == 'default' && !output_path
      f.write(JSON.pretty_generate({ bodies: system_data[:bodies] }))
    else
      f.write(JSON.pretty_generate(system_data))
    end
  end

  puts "Vesmírný systém úspěšně vygenerován: #{final_output_path}"
  puts "System ID: #{system_id}"
  puts "Počet planet: #{num_planets}"
  puts "Max měsíců na planetu: #{max_moons_per_planet}"
  puts "Celkem těles: #{system_data[:bodies].length}"

rescue => e
  STDERR.puts "Error: Failed to generate system: #{e.message}"
  STDERR.puts e.backtrace.join("\n") if ENV['DEBUG']
  exit 1
end

