# frozen_string_literal: true

require_relative "../validators/orbit_validator"

class System < ApplicationRecord
  # Callbacks
  before_validation :normalize_name
  before_validation :set_default_json_file_path, on: :create
  before_destroy :cleanup_system_files
  before_destroy :remove_from_galaxy
  after_commit :clear_system_cache

  # Validations
  validates :name, presence: { message: "musí být vyplněn" }
  validates :name, uniqueness: { message: "již existuje, zvolte jiný název" }

  # Security: Name format validation (alphanumeric plus spaces/hyphens, 3-50 characters)
  validates :name, format: {
    with: /\A[a-zA-Z0-9\s\-]{3,50}\z/,
    message: "musí obsahovat pouze alfanumerické znaky, mezery a pomlčky (3-50 znaků)"
  }, if: -> { name.present? }

  # Security: Name length validation
  validates :name, length: {
    minimum: 3,
    maximum: 50,
    message: "musí mít délku 3-50 znaků"
  }, if: -> { name.present? }

  validates :x, presence: { message: "musí být vyplněna" }
  validates :y, presence: { message: "musí být vyplněna" }
  validates :json_file_path, presence: { message: "musí být vyplněna" }

  # Coordinate range validation (0-800 for SVG canvas, recommended 50-750 with margin)
  validates :x, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 800,
    message: "musí být v rozsahu 0-800"
  }, if: -> { x.present? }

  validates :y, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 800,
    message: "musí být v rozsahu 0-800"
  }, if: -> { y.present? }

  # Custom orbit validation using OrbitValidator
  validate :validate_orbit_position

  # Security: File path validation to prevent path traversal
  validate :validate_safe_file_path

  # Security: Validate coordinates are finite numbers (not NaN or Infinity)
  validate :validate_finite_coordinates

  # Instance methods

  # Load system's JSON data from file system
  # Returns hash with system data or nil if file doesn't exist
  def load_system_data
    file_path = data_file_path
    return nil unless file_path && File.exist?(file_path)

    JSON.parse(File.read(file_path))
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse JSON for system #{name}: #{e.message}")
    nil
  rescue => e
    Rails.logger.error("Failed to load system data for #{name}: #{e.message}")
    nil
  end

  # Check if system data file exists
  def data_file_exists?
    file_path = data_file_path
    file_path.present? && File.exist?(file_path)
  end

  # Absolute path to this system's JSON data file (resolved through the
  # configured data root — json_file_path stores only the logical identity)
  def data_file_path
    return nil if system_id.blank?

    GalaxyService.system_data_path(system_id)
  end

  # Get slug-friendly version of name for use in file paths
  def slug
    name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
  end

  # Get safe system_id from json_file_path with validation
  # Security: Defense-in-depth - ensures extracted ID is safe even if validation was bypassed
  # @return [String, nil] Sanitized system_id or nil if invalid
  def system_id
    return nil if json_file_path.blank?

    # Extract filename from path
    filename = File.basename(json_file_path, ".json")

    # Validate format (same as in validate_safe_file_path)
    if filename.match?(/\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/i)
      filename.downcase
    elsif filename.match?(/\A[a-z0-9_]+\z/i)
      filename.downcase
    else
      Rails.logger.error("Security: Invalid system_id format extracted from #{json_file_path}")
      nil
    end
  end

  private

  # Normalize name: strip whitespace and squeeze multiple spaces
  # Security: Prevent issues with leading/trailing spaces and multiple consecutive spaces
  def normalize_name
    return if name.blank?
    self.name = name.strip.squeeze(" ")
  end

  # Set default JSON file path based on system name
  def set_default_json_file_path
    return if json_file_path.present? || name.blank?

    # Default path: data/systems/<slug>.json
    self.json_file_path = "data/systems/#{slug}.json"
  end

  # Validate system orbit position using OrbitValidator
  # Checks canvas bounds, distance from black hole, and collision with other systems
  def validate_orbit_position
    return if x.blank? || y.blank?

    # Load galaxy data for validation
    galaxy_data = load_galaxy_data_for_validation

    # Validate using OrbitValidator — exclude this system's own galaxy entry
    # (galaxy_data keys systems by file id, not database id)
    result = OrbitValidator.validate_system_orbit(
      x, y,
      galaxy_data,
      exclude_system_id: system_id || slug
    )

    # Add errors to model if validation failed
    unless result[:valid]
      result[:errors].each do |error|
        errors.add(:base, error)
      end
    end
  rescue => e
    Rails.logger.error("System validation error: #{e.message}")
    errors.add(:base, "Chyba při validaci pozice systému: #{e.message}")
  end

  # Load galaxy data for validation (with fallback to default)
  def load_galaxy_data_for_validation
    GalaxyService.send(:load_galaxy_data_from_file)
  rescue => e
    Rails.logger.warn("Failed to load galaxy data for validation: #{e.message}")
    # Return default structure on error
    {
      "black_hole" => { "x" => 400, "y" => 400 },
      "systems" => []
    }
  end

  # Validate file path to prevent path traversal attacks
  # Security: Ensure file path is safe and within expected directory
  def validate_safe_file_path
    return if json_file_path.blank?

    # Reject paths containing '..' (path traversal)
    if json_file_path.include?("..")
      errors.add(:json_file_path, "obsahuje nepovolené znaky (..)")
      Rails.logger.warn("Security: Path traversal attempt detected in json_file_path: #{json_file_path}")
      return
    end

    # Reject absolute paths
    if json_file_path.start_with?("/")
      errors.add(:json_file_path, "nesmí být absolutní cesta")
      Rails.logger.warn("Security: Absolute path detected in json_file_path: #{json_file_path}")
      return
    end

    # Ensure path starts with data/systems/
    unless json_file_path.start_with?("data/systems/")
      errors.add(:json_file_path, "musí začínat 'data/systems/'")
      Rails.logger.warn("Security: Invalid path prefix in json_file_path: #{json_file_path}")
      return
    end

    # Ensure path ends with .json
    unless json_file_path.end_with?(".json")
      errors.add(:json_file_path, "musí končit '.json'")
      return
    end

    # Extract filename and validate format (UUID or slug)
    filename = File.basename(json_file_path, ".json")
    # UUID format: 8-4-4-4-12 hex digits
    # Slug format: alphanumeric and underscores only
    unless filename.match?(/\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/i) ||
           filename.match?(/\A[a-z0-9_]+\z/)
      errors.add(:json_file_path, "obsahuje neplatný název souboru")
      Rails.logger.warn("Security: Invalid filename format in json_file_path: #{json_file_path}")
    end
  end

  # Validate coordinates are finite numbers (not NaN or Infinity)
  # Security: Prevent physics calculation errors from special float values
  def validate_finite_coordinates
    if x.present? && !x.finite?
      errors.add(:x, "musí být platné číslo")
      Rails.logger.warn("Security: Non-finite x coordinate detected: #{x}")
    end

    if y.present? && !y.finite?
      errors.add(:y, "musí být platné číslo")
      Rails.logger.warn("Security: Non-finite y coordinate detected: #{y}")
    end
  end

  # Clean up associated files before destroying system record
  # Removes system data JSON file and SVG file
  def cleanup_system_files
    return if system_id.blank?

    # Delete system data JSON file
    data_file = GalaxyService.system_data_path(system_id)
    if data_file && File.exist?(data_file)
      File.delete(data_file)
      Rails.logger.info("Deleted system data file: #{data_file}")
    end

    # Delete system SVG file
    svg_file = GalaxyService.system_svg_path(system_id)
    if svg_file && File.exist?(svg_file)
      File.delete(svg_file)
      Rails.logger.info("Deleted system SVG file: #{svg_file}")
    end
  rescue => e
    Rails.logger.error("Failed to cleanup system files: #{e.message}")
    # Don't fail the destroy if file cleanup fails
    # Files will be orphaned but system record is removed
  end

  # Remove this system's entry from galaxy_data.json so no ghost entry
  # blocks future systems at this position
  def remove_from_galaxy
    return if system_id.blank?

    GalaxyService.remove_system(system_id)
  rescue => e
    Rails.logger.error("Failed to remove system #{system_id} from galaxy data: #{e.message}")
  end

  # Clear cache for this specific system when it changes
  # Uses GalaxyService for targeted cache invalidation
  def clear_system_cache
    return unless json_file_path.present?

    system_id = File.basename(json_file_path, ".json")

    # Clear only this system's cache (not all systems)
    GalaxyService.clear_system_cache(system_id)

    # Clear galaxy cache since system list/metadata may have changed
    GalaxyService.clear_galaxy_cache

    # Clear used names cache since this system's names may have changed
    GalaxyService.invalidate_used_names_cache
  rescue => e
    Rails.logger.error("Failed to clear system cache for #{system_id}: #{e.message}")
    # Don't fail the transaction if cache clearing fails
  end
end
