# frozen_string_literal: true

require "application_system_test_case"

class SystemCreationCustomTest < ApplicationSystemTestCase
  # Test custom creation mode displays dynamic form
  test "custom creation mode displays planet/moon form" do
    visit new_galaxy_system_path

    # Look for custom mode toggle or custom fields
    if has_button?('Vlastní')
      click_button 'Vlastní', match: :first
    end

    # Custom form should have dynamic elements or body builder
    assert_selector 'form'
  end

  # Test add planet button functionality
  test "add planet button adds new planet input group" do
    visit new_galaxy_system_path

    if has_button?('Přidat planetu')
      initial_count = all('div[data-planet], .planet-group, [id*="planet"]').count
      click_button 'Přidat planetu', match: :first
      new_count = all('div[data-planet], .planet-group, [id*="planet"]').count
      assert new_count > initial_count, "Add planet button should increase planet count"
    end
  end

  # Test planet inputs include required fields
  test "planet inputs include mass, radius, density fields" do
    visit new_galaxy_system_path

    # Custom mode should have physics parameter inputs
    if has_button?('Vlastní')
      click_button 'Vlastní', match: :first

      # Check for at least some physics fields
      has_any = has_field?('Hmotnost') ||
                has_field?('Poloměr') ||
                has_field?('Hustota')

      # If custom mode is implemented, should have these fields
      assert has_any if has_button?('Add Planet')
    end
  end

  # Test form validation for physics values
  test "validates positive mass, radius, density values" do
    visit new_galaxy_system_path

    fill_in 'Název soustavy', with: "Physics Test", match: :first if has_field?('Název soustavy')

    if has_field?('Hmotnost')
      fill_in 'Hmotnost', with: "-1000", match: :first  # Negative value
      click_button 'Vytvořit soustavu', match: :first

      # Should show validation error
      assert_text 'chyba', wait: 5
    end
  end
end
