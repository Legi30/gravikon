# frozen_string_literal: true

# Single source of truth for the simulation's physics constants and shared
# dilation formulas. The values are pedagogically scaled so relativistic
# effects are visible on an 800x800 canvas — they are NOT real SI constants.
#
# Coordinate convention: 1 canvas unit = 1,000,000 m (UNIT_METERS).
# Light therefore crosses one canvas unit in 0.1 s, giving intra-system
# signal delays of seconds and inter-system delays of minutes.
module PhysicsConstants
  # Meters represented by one canvas coordinate unit
  UNIT_METERS = 1_000_000.0

  # Scaled speed of light in m/s (real: 299_792_458.0)
  C = 10_000_000.0

  # Scaled gravitational constant used for a body's OWN surface dilation
  # (real: 6.67430e-11). Chosen so planets/moons get visible ~0.82-0.99
  # factors, i.e. a body's own gravity matters LESS than the black hole
  # (David's call 2026-10-13: the black hole should dominate).
  GRAVITATIONAL_CONSTANT = 0.00004

  # Separately scaled G for the supermassive black hole: dilation ~0.34 at the
  # 50-unit safety limit, ~0.75 at 100, ~0.93 at 350 (horizon ~44 units, inside
  # the 50-unit limit, so the sqrt never goes negative where systems may sit).
  BLACK_HOLE_GRAVITATIONAL_CONSTANT = 2.7e-16

  # Mass of the central black hole (kg, shared by all generators/services)
  BLACK_HOLE_MASS = 8.2e36

  # Galaxy canvas center = black hole position
  GALAXY_CENTER_X = 400
  GALAXY_CENTER_Y = 400

  # System-local coordinates are centered on the star at (400, 400)
  SYSTEM_LOCAL_CENTER = 400

  # Gravitational time dilation caused by the black hole at a distance given
  # in canvas units: sqrt(1 - 2GM/(r*c^2)), clamped to [0, 1].
  #
  # @param mass [Float] Black hole mass in kg
  # @param distance_units [Float] Distance in canvas coordinate units
  # @return [Float] Dilation factor (0.0 at/inside the horizon, 1.0 = no effect)
  def self.gravitational_dilation(mass, distance_units)
    return 0.0 if distance_units < 1

    r_meters = distance_units * UNIT_METERS
    radicand = 1.0 - (2 * BLACK_HOLE_GRAVITATIONAL_CONSTANT * mass) / (r_meters * C**2)
    return 0.0 if radicand <= 0

    Math.sqrt(radicand)
  end

  # Time dilation at the surface of a body caused by its own mass:
  # sqrt(1 - 2GM/(R*c^2)), clamped to [0, 1].
  #
  # @param mass [Float] Body mass in kg
  # @param radius_meters [Float] Body radius in meters
  # @return [Float] Dilation factor
  def self.surface_dilation(mass, radius_meters)
    return 1.0 if radius_meters.to_f <= 0

    radicand = 1.0 - (2 * GRAVITATIONAL_CONSTANT * mass) / (radius_meters * C**2)
    return 0.0 if radicand <= 0

    Math.sqrt(radicand)
  end

  # Schwarzschild radius for the given mass using the black-hole-scaled G.
  # @param mass [Float] Mass in kg
  # @return [Float] Schwarzschild radius in meters
  def self.schwarzschild_radius(mass)
    2 * BLACK_HOLE_GRAVITATIONAL_CONSTANT * mass / C**2
  end
end
