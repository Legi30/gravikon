# frozen_string_literal: true

Rails.application.routes.draw do
  # Systémová kontrola (health check)
  get "up" => "rails/health#show", as: :rails_health_check

  # Dashboard - analytics and statistics
  get "/dashboard", to: "dashboard#index", as: "dashboard"
  get "/dashboard/cache_stats", to: "dashboard#cache_stats", as: "dashboard_cache_stats"
  get "/dashboard/job_performance", to: "dashboard#job_performance", as: "dashboard_job_performance"

  # Meetings - global and inter-system
  resources :meetings, except: [ :show ] do
    collection do
      get "new_inter_system"
    end
  end

  # Galaxy - main navigation hub for multi-system universe
  get "/galaxy", to: "galaxy#index", as: "galaxy_index"

  # Galaxy systems - Custom routes under /galaxy namespace
  # Explicit routes mapped to controller actions with _system suffix
  # Route names match existing view expectations (e.g., new_galaxy_system_path)
  scope "/galaxy" do
    get "/systems/new", to: "galaxy#new", as: :new_galaxy_system
    post "/systems", to: "galaxy#create", as: :galaxy_systems
    get "/systems/:id", to: "galaxy#show_system", as: :galaxy_system
    get "/systems/:id/edit", to: "galaxy#edit_system", as: :edit_galaxy_system
    patch "/systems/:id", to: "galaxy#update_system"
    put "/systems/:id", to: "galaxy#update_system"
    delete "/systems/:id", to: "galaxy#destroy_system"
    post "/systems/:id/regenerate", to: "galaxy#regenerate_system", as: :regenerate_galaxy_system
  end

  # O aplikaci - příběh, fyzikální model a účel Gravikonu
  get "/o-aplikaci", to: "pages#about", as: "about"

  # Domovská stránka - Galaxy as the main landing page
  root to: "galaxy#index"
end
