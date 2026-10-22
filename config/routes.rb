Rails.application.routes.draw do
  root "dashboard#show"

  resource :session, only: %i[new create destroy]

  # Health checks (design specifications/02). /up is Rails' default.
  get "up" => "rails/health#show", as: :rails_health_check
  get "health/live" => "health#live"
  get "health/ready" => "health#ready"
end
