#def show
#  system_data_path = Rails.root.join("data", "system_data.json")
#  schedule_path = Rails.root.join("data", "schedule.json")
#  svg_output_path = Rails.root.join("public", "system.svg")#

#   Vygeneruj SVG (spuštěním visualizeru)
#  system("ruby lib/visualizer.rb")

#  @svg_path_with_timestamp = "/system.svg?ts=#{Time.now.to_i}"
#end

class SystemsController < ApplicationController
  def show
    @svg_url = "/system.svg?ts=#{Time.now.to_i}"
  end

  def regenerate
    Meeting.delete_all
    # 1. Spustíme generátor nové soustavy
    system("ruby lib/generator.rb 4 2")

    # 2. Spustíme vizualizér
    system("ruby lib/visualizer.rb")

    # 3. Přesměrujeme zpět na zobrazení mapy (čímž se znovu načte)
    redirect_to systems_path
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

