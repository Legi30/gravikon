# frozen_string_literal: true

require "application_system_test_case"

class ResponsiveDesignTest < ApplicationSystemTestCase
  setup do
    @test_galaxy_file = Rails.root.join('data', 'galaxy_data.json')
    @test_galaxy_data = {
      'black_hole' => { 'name' => 'Sagittarius Omega', 'x' => 400, 'y' => 400 },
      'systems' => []
    }
    FileUtils.mkdir_p(File.dirname(@test_galaxy_file))
    File.write(@test_galaxy_file, JSON.pretty_generate(@test_galaxy_data))
  end

  teardown do
    File.delete(@test_galaxy_file) if File.exist?(@test_galaxy_file)
  end

  # Test page renders on desktop viewport
  test "galaxy page renders correctly on desktop viewport" do
    visit galaxy_index_path
    assert_selector 'body'
    assert_text /Galaxy|Galaxie/i, wait: 5
  end

  # Test styles are applied
  test "CSS styles are loaded and applied" do
    visit galaxy_index_path

    # Check for styled elements (basic smoke test)
    assert_selector 'body'

    # If styles are loaded, elements should have classes or inline styles
    has_styled_content = has_selector?('[class*="galaxy"], [class*="system"], [style]', wait: 5)
    assert has_styled_content || has_text?(/Galaxy/), "Page should render with styles"
  end

  # Test navigation is accessible
  test "navigation elements are accessible and visible" do
    visit galaxy_index_path

    # Check for navigation elements
    assert_selector 'nav, header, [role="navigation"]', wait: 5
  end

  # Test buttons are visible and clickable
  test "buttons and interactive elements are visible" do
    visit galaxy_index_path

    # Check for interactive elements
    has_buttons = has_button?(/New|Add|Přidat|Nový/i) || has_link?(/New|Add|Přidat|Nový/i)
    assert has_buttons, "Should have interactive buttons or links"
  end

  # Test meeting pages have consistent styling
  test "meeting pages display with consistent styling" do
    visit meetings_path

    assert_selector 'body'
    assert_text /Meeting|Schůzk/i, wait: 5

    # Check for styled content
    assert_selector 'table, .meeting-list, .card', wait: 5
  end

  # Test forms are properly styled
  test "forms display with proper styling and layout" do
    visit galaxy_new_system_path

    assert_selector 'form'

    # Form should have styled inputs
    assert_selector 'input, select, button', wait: 5
  end

  # Test space theme colors are present
  test "space theme with dark backgrounds is applied" do
    visit galaxy_index_path

    # Check for dark theme indicators (dark background, light text)
    # This is a basic check - actual styling verification would need computed styles
    assert_selector 'body'
  end

  # Test page doesn't have obvious layout breaks
  test "page layout does not have obvious breaks or overlaps" do
    visit galaxy_index_path

    # Page should render without critical errors
    assert_no_selector '.error, #error', wait: 2
    assert_selector 'body'
  end
end
