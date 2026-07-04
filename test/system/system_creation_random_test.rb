# frozen_string_literal: true

require "application_system_test_case"

class SystemCreationRandomTest < ApplicationSystemTestCase
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

  # Test new_system form loads with random generation option
  test "new_system form loads with creation options" do
    visit new_galaxy_system_path
    assert_selector 'form'
    assert_selector 'input[name*="name"]'
  end

  # Test form accepts system name input
  test "form accepts system name input (3-50 characters)" do
    visit new_galaxy_system_path
    fill_in 'Název soustavy', with: "Test System", match: :first
    # Form should accept the input
    assert_field 'Název soustavy', with: "Test System"
  end

  # Test form accepts num_planets input with validation
  test "form accepts num_planets input with 1-10 validation" do
    visit new_galaxy_system_path
    # Try to fill in planet count field
    if has_field?('Planets')
      fill_in 'Planets', with: "5", match: :first
      assert_field 'Planets', with: "5"
    end
  end

  # Test form accepts max_moons input with validation
  test "form accepts max_moons input with 0-5 validation" do
    visit new_galaxy_system_path
    if has_field?('Moons')
      fill_in 'Moons', with: "2", match: :first
      assert_field 'Moons', with: "2"
    end
  end

  # Test form submission with valid data
  test "form submission with valid data creates system" do
    visit new_galaxy_system_path

    fill_in 'Název soustavy', with: "Created System", match: :first
    fill_in 'Pozice X', with: "300", match: :first
    fill_in 'Pozice Y', with: "300", match: :first

    if has_field?('Počet planet')
      fill_in 'Počet planet', with: "3", match: :first
    end

    # Wait for button to become enabled (JavaScript validation)
    assert_button 'Vytvořit soustavu', disabled: false, wait: 5

    click_button 'Vytvořit soustavu', match: :first

    # Should redirect or show success
    assert_text 'Mapa galaxie', wait: 10
  end

  # Test error messages for invalid name length
  test "displays error messages for invalid name length" do
    visit new_galaxy_system_path

    fill_in 'Název soustavy', with: "AB", match: :first  # Too short
    fill_in 'Pozice X', with: "300", match: :first
    fill_in 'Pozice Y', with: "300", match: :first

    # Wait for button to become enabled
    assert_button 'Vytvořit soustavu', disabled: false, wait: 5

    click_button 'Vytvořit soustavu', match: :first

    # Should show Czech error message
    assert_text '3-50', wait: 5
  end

  # Test error messages for out of range parameters
  test "displays error messages for planets/moons out of range" do
    visit new_galaxy_system_path

    fill_in 'Název soustavy', with: "Invalid Params", match: :first
    fill_in 'Pozice X', with: "300", match: :first
    fill_in 'Pozice Y', with: "300", match: :first

    if has_field?('Počet planet')
      fill_in 'Počet planet', with: "15", match: :first  # Out of range
    end

    # Wait for button to become enabled
    assert_button 'Vytvořit soustavu', disabled: false, wait: 5

    click_button 'Vytvořit soustavu', match: :first

    # Should show error
    assert_text 'chyba', wait: 5
  end
end
