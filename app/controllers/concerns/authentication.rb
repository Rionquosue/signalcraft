# frozen_string_literal: true

# Cookie-based sign-in. The cookie carries a random token; the database keeps
# only its SHA-256 digest (Session.find_by_token). Based on the Rails 8.1
# authentication generator, adapted to design specifications/02 and 08.
module Authentication
  extend ActiveSupport::Concern

  COOKIE = :signalcraft_session

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def authenticated?
    resume_session.present?
  end

  def current_user
    Current.user
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= Session.find_by_token(cookies.signed[COOKIE])
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url if request.get?
    redirect_to new_session_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for(user)
    reset_session # new Rails session id after sign-in (session fixation)
    record, token = Session.start!(user: user, ip_address: request.remote_ip, user_agent: request.user_agent)
    Current.session = record
    cookies.signed[COOKIE] = { value: token, httponly: true, same_site: :lax, secure: Rails.env.production?,
                               expires: Session::ABSOLUTE_LIFETIME.from_now }
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(COOKIE)
    reset_session
  end
end
