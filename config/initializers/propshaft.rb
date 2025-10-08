# frozen_string_literal: true

# Propshaft configuration for asset serving
Rails.application.configure do
  # In production, serve minified assets from public/assets
  if Rails.env.production?
    # Add public/assets to asset load paths for minified versions
    config.assets.paths << Rails.root.join("public", "assets")

    # Ensure proper cache headers for assets
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{1.year.to_i}",
      "Expires" => 1.year.from_now.to_formatted_s(:rfc822)
    }
  end
end
