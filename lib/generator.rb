# frozen_string_literal: true

require 'json'
require 'securerandom'

# === Parametry z příkazové řádky ===
# Přijímá dva argumenty: počet planet a maximální počet měsíců na planetu
# Použití: ruby lib/generator.rb 5 2
if ARGV.length >= 2
  begin
    NUM_PLANETS = Integer(ARGV[0])
    MAX_MOONS_PER_PLANET = Integer(ARGV[1])

    # Validace rozsahů
    unless NUM_PLANETS.between?(1, 10)
      STDERR.puts "Error: NUM_PLANETS must be between 1 and 10, got #{NUM_PLANETS}"
      exit 1
    end

    unless MAX_MOONS_PER_PLANET.between?(0, 5)
      STDERR.puts "Error: MAX_MOONS_PER_PLANET must be between 0 and 5, got #{MAX_MOONS_PER_PLANET}"
      exit 1
    end
  rescue ArgumentError => e
    STDERR.puts "Error: Invalid arguments. Both must be integers. #{e.message}"
    exit 1
  end
else
  # Výchozí hodnoty pokud argumenty nejsou poskytnuty
  NUM_PLANETS = 5
  MAX_MOONS_PER_PLANET = 2
  STDERR.puts "Warning: Using default values (NUM_PLANETS=#{NUM_PLANETS}, MAX_MOONS_PER_PLANET=#{MAX_MOONS_PER_PLANET})"
end

# === Nastavení ===
STAR_POSITION = [400, 400]
GRAVITATIONAL_CONSTANT = 0.0001 #6.67430e-11
C = 10_000_000 #299_792_458.0 # m/s

# === Generátory názvů ===
planet_names = %w[Plaxer Plomur Plaven Plirion Plintar Ploxis Plador Plenor Plurion Plarkon]
moon_names = %w[Morish Morex Molan Morthax Mobin Morlun Mozer Morlux Mochar Morlon]
star_names = %w[Stelaris Starnox Stavor Sturion Steldor Stalius Starnith Storgath]

def random_name(list, used)
  name = list.sample
  while used.include?(name)
    name = list.sample
  end
  used << name
  name
end

# === Výpočty ===
def calculate_mass(radius, density)
  volume = (4.0 / 3.0) * Math::PI * radius**3
  volume * density
end

def gravitational_potential(mass, r)
  return 0 if r == 0
  -GRAVITATIONAL_CONSTANT * mass / r
end

def time_dilation(potential)
  Math.sqrt(1 + 2 * potential / (C**2))
end

# === Generování těles ===
used_names = []
bodies = []

# Hvězda
star_radius = rand(50_000_000..100_000_000) # m
star_density = rand(1000..2000) # kg/m^3
star_mass = calculate_mass(star_radius, star_density)

star = {
  name: random_name(star_names, used_names),
  type: 'star',
  x: STAR_POSITION[0],
  y: STAR_POSITION[1],
  radius: star_radius,
  density: star_density,
  mass: star_mass,
  dilation: time_dilation(0) # referenční čas
}
bodies << star

# Planety a měsíce
NUM_PLANETS.times do |i|
  angle = rand * 2 * Math::PI
  distance = 100 + i * 60 + rand(-20..20)
  planet_x = STAR_POSITION[0] + distance * Math.cos(angle)
  planet_y = STAR_POSITION[1] + distance * Math.sin(angle)

  planet_radius = rand(1_000_000..4_000_000)
  planet_density = rand(3000..6000)
  planet_mass = calculate_mass(planet_radius, planet_density)
  potential = gravitational_potential(planet_mass, planet_radius)

  planet = {
    name: random_name(planet_names, used_names),
    type: 'planet',
    x: planet_x.round(2),
    y: planet_y.round(2),
    radius: planet_radius,
    density: planet_density,
    mass: planet_mass,
    dilation: time_dilation(potential)
  }
  bodies << planet

  # Měsíce (0 až MAX_MOONS_PER_PLANET)
  rand(0..MAX_MOONS_PER_PLANET).times do |j|
    angle = rand * 2 * Math::PI
    moon_distance = 20 + j * 15
    moon_x = planet_x + moon_distance * Math.cos(angle)
    moon_y = planet_y + moon_distance * Math.sin(angle)

    moon_radius = rand(300_000..800_000)
    moon_density = rand(2500..5000)
    moon_mass = calculate_mass(moon_radius, moon_density)
    moon_potential = gravitational_potential(moon_mass, moon_radius)

    moon = {
      name: random_name(moon_names, used_names),
      type: 'moon',
      x: moon_x.round(2),
      y: moon_y.round(2),
      radius: moon_radius,
      density: moon_density,
      mass: moon_mass,
      dilation: time_dilation(moon_potential)
    }
    bodies << moon
  end
end

# === Výstup ===
output = { bodies: bodies }

File.open("data/system_data.json", "w") do |f|
  f.write(JSON.pretty_generate(output))
end

puts "Vesmírný systém úspěšně vygenerován a uložen do system_data.json"

