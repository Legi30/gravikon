require "test_helper"

class DashboardHelperTest < ActionView::TestCase
  # system_intro and the chart data use the shared view helpers (km, system colours)
  include ApplicationHelper

  setup do
    Meeting.delete_all
    System.delete_all
  end

  # === cs_count ===

  test "cs_count picks the Czech plural form" do
    assert_equal "1 planeta", cs_count(1, "planeta", "planety", "planet")
    assert_equal "3 planety", cs_count(3, "planeta", "planety", "planet")
    assert_equal "5 planet", cs_count(5, "planeta", "planety", "planet")
    assert_equal "0 planet", cs_count(0, "planeta", "planety", "planet")
  end

  # === number formatting ===

  test "format_minutes uses one decimal and a decimal comma" do
    assert_equal "56,0", format_minutes(56)
    assert_equal "47,9", format_minutes(47.86)
  end

  test "format_delay_display returns 0 s for nil and zero" do
    assert_equal "0 s", format_delay_display(nil)
    assert_equal "0 s", format_delay_display(0)
  end

  test "format_delay_display formats seconds and minutes with a decimal comma" do
    assert_equal "25,27 s", format_delay_display(25.271)
    assert_equal "2,00 min", format_delay_display(120)
  end

  # === system_intro ===

  test "system_intro names the star, distance, time rate and extremes" do
    profile = {
      system: System.new(name: "Alfa"),
      stars: [ { name: "Steldith", dilation: 0.93 } ],
      distance: 140,
      rate: 0.9333,
      planets: [
        { name: "Plexis", dilation: 0.845, moons: [ { name: "Molan", dilation: 0.932 } ] }
      ]
    }

    intro = system_intro(profile)
    assert_includes intro, "Soustava hvězdy Steldith leží 140 000 km od černé díry"
    assert_includes intro, "uběhne 56,0 min"
    assert_includes intro, "Nejpomaleji plyne čas na tělese Plexis (50,7 min za hodinu)"
    assert_includes intro, "nejrychleji na tělese Molan (55,9 min)"
  end

  test "system_intro names both stars of a binary" do
    profile = {
      system: System.new(name: "Alfa"),
      stars: [ { name: "Steldith", dilation: 1.0 }, { name: "Stavor", dilation: 1.0 } ],
      distance: 140,
      rate: 0.9333,
      planets: []
    }

    assert_includes system_intro(profile), "Dvojhvězda Steldith a Stavor, jejíž hvězdy krouží kolem sebe, leží 140\u00A0000\u00A0km"
  end

  # === system_color (ApplicationHelper) ===

  test "system_color follows system id order and falls back to the neutral colour" do
    first = System.create!(name: "First System", x: 200, y: 200, json_file_path: "data/systems/first_color.json")
    second = System.create!(name: "Second System", x: 600, y: 600, json_file_path: "data/systems/second_color.json")

    assert_equal ApplicationHelper::SYSTEM_COLORS[0], system_color(first.id)
    assert_equal ApplicationHelper::SYSTEM_COLORS[1], system_color(second.id)
    assert_equal ApplicationHelper::SYSTEM_OTHER_COLOR, system_color(nil)
  end

  test "system_tint mixes the system colour toward white" do
    assert_equal "#14a594", System.tint("#14a594", 0)
    assert_equal "#ffffff", System.tint("#14a594", 1)
    assert_equal "#8ad2ca", System.tint("#14a594", 0.5)
  end

  # === system_story ===

  test "system_story is hand-written for the core systems" do
    profile = { system: System.new(name: "Trappist"), planets: [] }
    assert_includes system_story(profile), "Trapisté složili slib mlčení"
  end

  test "system_story picks a stable pooled story for other systems" do
    profile = { system: System.new(name: "Custom Sys"), planets: [ { name: "Plexis" } ] }
    story = system_story(profile)

    assert_equal story, system_story(profile)
    assert_includes story, "Plexis"
  end
end
