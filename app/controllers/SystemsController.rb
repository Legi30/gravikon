# frozen_string_literal: true

class SystemsController < ApplicationController
  def show
    @svg_url = "/system.svg?ts=#{Time.now.to_i}"
  end

  def regenerate
    Meeting.delete_all

    # Získáme a striktně validujeme parametry
    begin
      # Použití Integer() zajistí, že vstup je skutečně celé číslo
      # Na rozdíl od to_i, které vrací 0 pro neplatné vstupy
      num_planets = Integer(params[:num_planets] || 5)
      max_moons = Integer(params[:max_moons] || 2)
    rescue ArgumentError, TypeError => e
      Rails.logger.error("SystemsController#regenerate: Invalid parameters - #{e.message}")
      redirect_to systems_url, alert: "Neplatné parametry. Použijte celá čísla." and return
    end

    # Sanitace a omezení na platné rozsahy
    num_planets = num_planets.clamp(1, 10)
    max_moons = max_moons.clamp(0, 5)

    # Invalidate cache immediately to prevent serving stale data during regeneration
    # This prevents race condition where users could see old system data after meetings are deleted
    Rails.cache.delete('system_data')
    Rails.logger.info("SystemsController#regenerate: Cache invalidated before regeneration")

    # Logování akce pro audit trail
    Rails.logger.info("SystemsController#regenerate: Starting system generation with num_planets=#{num_planets}, max_moons=#{max_moons}")

    # Spustíme generování na pozadí s parametry
    GenerateSystemJob.perform_later(num_planets, max_moons)

    redirect_to systems_url, notice: "Generování soustavy s #{num_planets} planetami probíhá na pozadí..."
  end
end

#class SystemsController < ApplicationController
#  def show
#    @svg_path_with_timestamp = "/system.svg?ts=#{Time.now.to_i}"
#  end

#  def generate
    # Spusť generátor s nějakými výchozími hodnotami
#    system("ruby lib/generator.rb 5 3")  # třeba 5 planet, max 3 měsíce
#    system("ruby lib/visualizer.rb")

#    redirect_to systems_path  # přesměruj zpět na zobrazení
#  end
#end

