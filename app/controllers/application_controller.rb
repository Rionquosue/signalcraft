# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_request_context

  private

  def set_request_context
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
  end
end
