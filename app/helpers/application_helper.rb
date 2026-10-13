module ApplicationHelper
  # The palette lives on System (the galaxy map needs it outside views)
  SYSTEM_COLORS = System::COLORS
  SYSTEM_OTHER_COLOR = System::OTHER_COLOR

  def system_color(system_id)
    @system_color_map ||= System.color_map
    @system_color_map[system_id] || SYSTEM_OTHER_COLOR
  end

  # Light tint of a system colour for drawing on the dark map
  # (0 = the colour itself, 1 = white)
  def system_tint(system_id, amount = 0.45)
    System.tint(system_color(system_id), amount)
  end

  # Galaxy/system canvas distance → kilometres for display. One canvas unit is
  # PhysicsConstants::UNIT_METERS (1 000 km); visitors read km, not canvas units.
  def format_distance_km(units)
    km = (units.to_f * PhysicsConstants::UNIT_METERS / 1000).round
    "#{number_with_delimiter(km, delimiter: " ")} km"
  end
end
