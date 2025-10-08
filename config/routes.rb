# frozen_string_literal: true

Rails.application.routes.draw do
  # Systémová kontrola (health check)
  get "up" => "rails/health#show", as: :rails_health_check

  # Dashboard - analytics and statistics
  get "/dashboard", to: "dashboard#index", as: "dashboard"
  get "/dashboard/cache_stats", to: "dashboard#cache_stats", as: "dashboard_cache_stats"
  get "/dashboard/job_performance", to: "dashboard#job_performance", as: "dashboard_job_performance"

  # Meetings (pokud potřebuješ i nadále)
  resources :meetings

  # Gravitační soustava – SVG mapa
  get "/systems", to: "systems#show", as: "systems"
  post "/systems/regenerate", to: "systems#regenerate", as: "regenerate_system"

  # Domovská stránka (přesměrování na soustavu)
  root to: "meetings#index"
end

