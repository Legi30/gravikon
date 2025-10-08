Rails.application.routes.draw do
  # Systémová kontrola (health check)
  get "up" => "rails/health#show", as: :rails_health_check

  # Meetings (pokud potřebuješ i nadále)
  resources :meetings

  # Gravitační soustava – SVG mapa
  get "/systems", to: "systems#show"
  post "/systems/regenerate", to: "systems#regenerate", as: "regenerate_system"

  # Domovská stránka (přesměrování na soustavu)
  root to: "meetings#index"
end

