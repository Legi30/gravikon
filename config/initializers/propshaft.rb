# frozen_string_literal: true

# Propshaft configuration for asset serving.
#
# NOTE: public/assets is Propshaft's OUTPUT directory and must never be on the
# asset load path; it used to be added here, which made every
# assets:precompile re-digest the previous build's output
# (galaxy-850f107a-850f107a.js, "Unable to resolve" warnings).
Rails.application.configure do
  if Rails.env.production?
    # Ensure proper cache headers for assets
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{1.year.to_i}",
      "Expires" => 1.year.from_now.to_formatted_s(:rfc822)
    }
  end
end
