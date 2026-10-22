# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again in a few minutes." }

  FAILED = "That e-mail address and password don't match an account."

  def new
  end

  def create
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s

    if LoginThrottle.locked?(email: email, ip_address: request.remote_ip)
      redirect_to new_session_path, alert: "Too many attempts. Try again in a few minutes."
      return
    end

    user = User.active.authenticate_by(email: email, password: password)
    if user
      LoginThrottle.reset!(email: email)
      user.rehash_password_if_needed!(password)
      start_new_session_for(user)
      AuditEvent.record!(action: "session.signed_in", actor: user)
      redirect_to after_authentication_url
    else
      LoginThrottle.record_failure!(email: email, ip_address: request.remote_ip)
      redirect_to new_session_path, alert: FAILED
    end
  end

  def destroy
    AuditEvent.record!(action: "session.signed_out", actor: current_user) if current_user
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
