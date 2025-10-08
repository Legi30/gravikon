# frozen_string_literal: true

namespace :assets do
  desc "Minify CSS and JavaScript files for production"
  task minify: :environment do
    require "terser"
    require "csso"

    assets_path = Rails.root.join("app", "assets")
    public_path = Rails.root.join("public", "assets")

    # Create public/assets directory if it doesn't exist
    FileUtils.mkdir_p(public_path)

    puts "=" * 80
    puts "MINIFYING ASSETS FOR PRODUCTION"
    puts "=" * 80

    # Minify JavaScript files
    js_source = assets_path.join("javascripts")
    if Dir.exist?(js_source)
      Dir.glob(js_source.join("**", "*.js")).each do |file|
        next if file.end_with?(".min.js") # Skip already minified files

        original_size = File.size(file)
        content = File.read(file)

        begin
          minified = Terser.new(compress: { passes: 2 }, mangle: true).compile(content)
          relative_path = Pathname.new(file).relative_path_from(js_source)
          output_file = public_path.join("javascripts", relative_path)

          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, minified)

          minified_size = File.size(output_file)
          reduction = ((1 - minified_size.to_f / original_size) * 100).round(1)

          puts "✓ #{relative_path}"
          puts "  #{original_size} bytes → #{minified_size} bytes (#{reduction}% reduction)"
        rescue => e
          puts "✗ Failed to minify #{file}: #{e.message}"
        end
      end
    end

    # Minify CSS files
    css_source = assets_path.join("stylesheets")
    if Dir.exist?(css_source)
      Dir.glob(css_source.join("**", "*.css")).each do |file|
        next if file.end_with?(".min.css") # Skip already minified files

        original_size = File.size(file)
        content = File.read(file)

        begin
          minified = Csso.optimize(content)
          relative_path = Pathname.new(file).relative_path_from(css_source)
          output_file = public_path.join("stylesheets", relative_path)

          FileUtils.mkdir_p(File.dirname(output_file))
          File.write(output_file, minified)

          minified_size = File.size(output_file)
          reduction = ((1 - minified_size.to_f / original_size) * 100).round(1)

          puts "✓ #{relative_path}"
          puts "  #{original_size} bytes → #{minified_size} bytes (#{reduction}% reduction)"
        rescue => e
          puts "✗ Failed to minify #{file}: #{e.message}"
        end
      end
    end

    # Calculate total size
    total_size = 0
    Dir.glob(public_path.join("**", "*.*")).each do |file|
      total_size += File.size(file) if File.file?(file)
    end

    puts "=" * 80
    puts "MINIFICATION COMPLETE"
    puts "Total minified assets size: #{(total_size / 1024.0).round(1)} KB"

    if total_size > 500 * 1024
      puts "⚠️  WARNING: Total size exceeds 500KB target"
    else
      puts "✓ Total size is within 500KB target"
    end
    puts "=" * 80
  end

  desc "Clean minified assets from public/assets"
  task clean_minified: :environment do
    public_path = Rails.root.join("public", "assets")
    if Dir.exist?(public_path)
      FileUtils.rm_rf(public_path)
      puts "✓ Cleaned minified assets from public/assets"
    else
      puts "✓ No minified assets to clean"
    end
  end

  desc "Precompile assets (alias for assets:minify for Propshaft)"
  task precompile: :minify
end
