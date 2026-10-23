# frozen_string_literal: true

module Publishing
  # Per-invocation context handed to an addon (design specifications/04,
  # Context services). Built fresh for each call; never global.
  class Context
    # Checkpoints for one publish attempt, encrypted at rest.
    class Checkpoints
      def initialize(attempt)
        @attempt = attempt
      end

      def load
        @attempt.plugin_checkpoint&.payload
      end

      def save!(data, schema_version: 1)
        record = @attempt.plugin_checkpoint || @attempt.build_plugin_checkpoint(plugin_id: @attempt.plugin_id)
        record.update!(data: JSON.generate(data), schema_version: schema_version, updated_at: Time.current)
      end
    end

    attr_reader :social_account, :checkpoints, :settings

    def initialize(attempt)
      @social_account = attempt.post_target.social_account
      @checkpoints = Checkpoints.new(attempt)
      @settings = WorkspacePlugin.find_by(workspace_id: @social_account.workspace_id,
                                          plugin_id: @social_account.plugin_id)&.settings || {}
    end

    # Decrypted only here, inside the addon call that needs them.
    def credentials
      JSON.parse(social_account.credentials.to_s)
    rescue JSON::ParserError
      {}
    end

    # The host HTTP client (deadlines, TLS verification, blocked private
    # destinations) is built together with the first addon.
    def http
      raise NotImplementedError, "the host HTTP client is not available yet"
    end
  end
end
