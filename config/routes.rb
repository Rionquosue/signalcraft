Rails.application.routes.draw do
  root "dashboard#show"

  resource :session, only: %i[new create destroy]

  # Composer and per-platform editing (design specifications/05).
  resources :posts, only: %i[new create edit update]
  resources :post_targets, only: %i[update] do
    member do
      delete :body, action: :reset_body
      post :publish_now
      post :unschedule
      post :cancel
      post :copy
    end
  end

  # Queue slots, pause/resume and reordering (design specifications/05).
  resources :channel_queues, only: %i[edit update] do
    member do
      post :pause
      get :resume, action: :resume_preview
      post :resume
    end
    resources :moves, only: %i[new create], controller: "queue_moves"
  end

  # Health checks (design specifications/02). /up is Rails' default.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health/live" => "health#live"
  get "health/ready" => "health#ready"
end
