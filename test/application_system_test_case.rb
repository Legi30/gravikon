# frozen_string_literal: true

require "test_helper"
require "capybara/rails"
require "capybara/minitest"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]

  # Include Capybara DSL
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  # Teardown to ensure Capybara cleans up after each test
  teardown do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end
