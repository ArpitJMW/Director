require "sidekiq/web"

Rails.application.routes.draw do
  # Liveness probe for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # Sidekiq dashboard. Open in development; lock behind auth before deploying.
  if Rails.env.development?
    mount Sidekiq::Web => "/sidekiq"
  end

  # Register the Devise mapping for :user without generating any default routes;
  # the API-shaped routes are defined under /api/v1/auth below.
  devise_for :users, skip: :all

  namespace :api do
    namespace :v1 do
      # Auth (Devise + JWT). Tokens are returned in the Authorization response header.
      devise_scope :user do
        post   "auth/sign_up",  to: "auth/registrations#create"
        post   "auth/sign_in",  to: "auth/sessions#create"
        delete "auth/sign_out", to: "auth/sessions#destroy"
      end

      # Current authenticated user.
      resource :me, only: [ :show, :update ], controller: :me

      # Readiness probe: verifies DB + Redis connectivity.
      get "health", to: "health#show"

      # Signed file delivery for the disk storage backend.
      get "files", to: "files#show"

      # --- Application resources (spec §29) --------------------------------
      resources :projects, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          get  :preflight,               to: "preflight_reports#show"
          post "preflight/generate",     to: "pipeline#generate_preflight"
          post "preflight/acknowledge",  to: "pipeline#acknowledge_preflight"
          # Pipeline actions.
          post "script/generate",     to: "pipeline#generate_script"
          post "storyboard/generate", to: "pipeline#generate_storyboard"
          post "assets/generate",     to: "pipeline#generate_assets"
          post "voice/generate",      to: "pipeline#generate_voice"
          post :render,               to: "pipeline#render_video"
        end
        resources :scenes, only: [ :index ]
        resources :renders, only: [ :index ], controller: :video_renders
        resources :jobs, only: [ :index ], controller: :generation_jobs
        resources :assets, only: [ :create ]
      end

      resources :scenes, only: [ :show, :update ] do
        member do
          post :regenerate,        to: "pipeline#regenerate_scene"
          post "assets/regenerate", to: "pipeline#regenerate_scene_asset"
        end
      end

      resources :templates, only: [ :index, :show ]
      resources :assets, only: [ :index ]
    end
  end
end
