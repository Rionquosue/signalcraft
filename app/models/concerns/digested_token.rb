# frozen_string_literal: true

# Random lookup tokens of which only the SHA-256 digest is stored
# (design specifications/02, Lookup tokens).
module DigestedToken
  extend ActiveSupport::Concern

  class_methods do
    def generate_token
      SecureRandom.urlsafe_base64(32)
    end

    def digest(token)
      Digest::SHA256.digest(token)
    end
  end
end
