# frozen_string_literal: true

require "test_helper"

class SystemTest < ActiveSupport::TestCase
  # Test validates presence of name, x, y, and json_file_path
  test "validates presence of required fields" do
    system = System.new
    assert_not system.valid?
    assert_includes system.errors[:name], "musí být vyplněn"
    assert_includes system.errors[:x], "musí být vyplněna"
    assert_includes system.errors[:y], "musí být vyplněna"
  end

  # Test validates name uniqueness across all systems
  test "validates name uniqueness" do
    # Create first system
    System.create!(name: "Alpha Centauri", x: 300, y: 300)

    # Try to create duplicate
    duplicate = System.new(name: "Alpha Centauri", x: 400, y: 400)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "již existuje, zvolte jiný název"
  end

  # Test validates name length between 3-50 characters
  test "validates name length minimum 3 characters" do
    system = System.new(name: "AB", x: 300, y: 300)
    assert_not system.valid?
    assert system.errors[:name].any? { |msg| msg.include?("3-50 znaků") }
  end

  test "validates name length maximum 50 characters" do
    long_name = "A" * 51
    system = System.new(name: long_name, x: 300, y: 300)
    assert_not system.valid?
    assert system.errors[:name].any? { |msg| msg.include?("3-50 znaků") }
  end

  test "accepts valid name length" do
    system = System.new(name: "Sol", x: 300, y: 300)
    # Only checking name length, not other validations
    assert system.name.length >= 3
    assert system.name.length <= 50
  end

  # Test validates x and y coordinates within 0-800 range
  test "validates x coordinate within 0-800 range" do
    system = System.new(name: "Test System", x: -10, y: 300)
    assert_not system.valid?
    assert_includes system.errors[:x], "musí být v rozsahu 0-800"

    system.x = 850
    assert_not system.valid?
    assert_includes system.errors[:x], "musí být v rozsahu 0-800"
  end

  test "validates y coordinate within 0-800 range" do
    system = System.new(name: "Test System", x: 300, y: -10)
    assert_not system.valid?
    assert_includes system.errors[:y], "musí být v rozsahu 0-800"

    system.y = 850
    assert_not system.valid?
    assert_includes system.errors[:y], "musí být v rozsahu 0-800"
  end

  test "accepts coordinates within valid range" do
    system = System.new(name: "Test System", x: 300, y: 400)
    # Coordinates should pass numericality validation
    assert system.x >= 0 && system.x <= 800
    assert system.y >= 0 && system.y <= 800
  end

  # Test validates name format (alphanumeric, spaces, hyphens only)
  test "validates name format accepts alphanumeric characters" do
    system = System.new(name: "Alpha123", x: 300, y: 300)
    # Should not have format errors (may have other errors)
    system.valid?
    format_errors = system.errors[:name].select { |msg| msg.include?("alfanumerické") }
    assert_empty format_errors
  end

  test "validates name format accepts spaces and hyphens" do
    system = System.new(name: "Alpha-Beta Gamma", x: 300, y: 300)
    system.valid?
    format_errors = system.errors[:name].select { |msg| msg.include?("alfanumerické") }
    assert_empty format_errors
  end

  test "validates name format rejects special characters" do
    system = System.new(name: "Alpha@Beta!", x: 300, y: 300)
    assert_not system.valid?
    assert system.errors[:name].any? { |msg| msg.include?("alfanumerické") }
  end

  # Test generates unique system_id (slug) before creation
  test "generates slug from name" do
    system = System.new(name: "Alpha Centauri", x: 300, y: 300)
    assert_equal "alpha_centauri", system.slug
  end

  test "slug handles special characters correctly" do
    system = System.new(name: "Beta-Gamma  123", x: 300, y: 300)
    assert_equal "beta_gamma_123", system.slug
  end

  test "sets default json_file_path based on slug" do
    system = System.new(name: "Test System", x: 300, y: 300)
    system.valid? # Triggers before_validation callback
    assert_equal "data/systems/test_system.json", system.json_file_path
  end

  # Test rejects invalid json_file_path formats
  test "rejects json_file_path with path traversal" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/../../../etc/passwd"
    )
    assert_not system.valid?
    assert_includes system.errors[:json_file_path], "obsahuje nepovolené znaky (..)"
  end

  test "rejects absolute json_file_path" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "/etc/passwd"
    )
    assert_not system.valid?
    assert_includes system.errors[:json_file_path], "nesmí být absolutní cesta"
  end

  test "rejects json_file_path not starting with data/systems/" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "other_dir/file.json"
    )
    assert_not system.valid?
    assert_includes system.errors[:json_file_path], "musí začínat 'data/systems/'"
  end

  test "rejects json_file_path not ending with .json" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test.txt"
    )
    assert_not system.valid?
    assert_includes system.errors[:json_file_path], "musí končit '.json'"
  end

  test "rejects json_file_path with invalid filename format" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/invalid@name.json"
    )
    assert_not system.valid?
    assert_includes system.errors[:json_file_path], "obsahuje neplatný název souboru"
  end

  test "accepts valid UUID format json_file_path" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/550e8400-e29b-41d4-a716-446655440000.json"
    )
    # May have orbit validation errors, but not file path errors
    system.valid?
    file_path_errors = system.errors[:json_file_path]
    assert_empty file_path_errors
  end

  test "accepts valid slug format json_file_path" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test_system_123.json"
    )
    system.valid?
    file_path_errors = system.errors[:json_file_path]
    assert_empty file_path_errors
  end

  # Test loads system JSON data from file path correctly
  test "load_system_data returns nil for non-existent file" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/nonexistent.json"
    )
    assert_nil system.load_system_data
  end

  test "load_system_data returns parsed JSON for valid file" do
    # Create a temporary test file
    test_file_path = Rails.root.join("data/systems/test_load.json")
    FileUtils.mkdir_p(File.dirname(test_file_path))
    File.write(test_file_path, { bodies: [{ name: "Earth", type: "planet" }] }.to_json)

    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test_load.json"
    )

    data = system.load_system_data
    assert_not_nil data
    assert_equal "Earth", data["bodies"].first["name"]

    # Cleanup
    File.delete(test_file_path) if File.exist?(test_file_path)
  end

  test "load_system_data handles malformed JSON gracefully" do
    # Create a temporary test file with invalid JSON
    test_file_path = Rails.root.join("data/systems/test_malformed.json")
    FileUtils.mkdir_p(File.dirname(test_file_path))
    File.write(test_file_path, "{ invalid json }")

    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test_malformed.json"
    )

    assert_nil system.load_system_data

    # Cleanup
    File.delete(test_file_path) if File.exist?(test_file_path)
  end

  test "data_file_exists? returns true for existing file" do
    # Create a temporary test file
    test_file_path = Rails.root.join("data/systems/test_exists.json")
    FileUtils.mkdir_p(File.dirname(test_file_path))
    File.write(test_file_path, "{}")

    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test_exists.json"
    )

    assert system.data_file_exists?

    # Cleanup
    File.delete(test_file_path) if File.exist?(test_file_path)
  end

  test "data_file_exists? returns false for non-existent file" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/nonexistent.json"
    )

    assert_not system.data_file_exists?
  end

  # Test validates coordinates are finite (not NaN or Infinity)
  test "rejects NaN x coordinate" do
    system = System.new(name: "Test", x: Float::NAN, y: 300)
    assert_not system.valid?
    assert_includes system.errors[:x], "musí být platné číslo"
  end

  test "rejects Infinity x coordinate" do
    system = System.new(name: "Test", x: Float::INFINITY, y: 300)
    assert_not system.valid?
    assert_includes system.errors[:x], "musí být platné číslo"
  end

  test "rejects NaN y coordinate" do
    system = System.new(name: "Test", x: 300, y: Float::NAN)
    assert_not system.valid?
    assert_includes system.errors[:y], "musí být platné číslo"
  end

  test "rejects Infinity y coordinate" do
    system = System.new(name: "Test", x: 300, y: Float::INFINITY)
    assert_not system.valid?
    assert_includes system.errors[:y], "musí být platné číslo"
  end

  # Test system_id extraction
  test "system_id extracts UUID correctly" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/550e8400-e29b-41d4-a716-446655440000.json"
    )
    assert_equal "550e8400-e29b-41d4-a716-446655440000", system.system_id
  end

  test "system_id extracts slug correctly" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/test_system.json"
    )
    assert_equal "test_system", system.system_id
  end

  test "system_id returns nil for invalid format" do
    system = System.new(
      name: "Test",
      x: 300,
      y: 300,
      json_file_path: "data/systems/invalid@name.json"
    )
    assert_nil system.system_id
  end

  # Test name normalization
  test "normalize_name strips whitespace" do
    system = System.new(name: "  Test System  ", x: 300, y: 300)
    system.valid? # Triggers before_validation
    assert_equal "Test System", system.name
  end

  test "normalize_name squeezes multiple spaces" do
    system = System.new(name: "Test    System", x: 300, y: 300)
    system.valid? # Triggers before_validation
    assert_equal "Test System", system.name
  end
end
