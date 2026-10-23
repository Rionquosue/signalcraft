# frozen_string_literal: true

module Publishing
  # The immutable TargetSnapshot recorded on each publish attempt before any
  # network activity (design specifications/04, Social addon DTO definitions).
  # The content hash covers exactly what the provider will receive.
  module Snapshot
    module_function

    # Returns [snapshot (JSON-compatible Hash), content_hash (32 raw bytes)].
    def build(target)
      content = {
        "text" => target.effective_body,
        "media" => target.effective_media.map do |item|
          { "position" => item.position, "media_asset_id" => item.media_asset_id,
            "sha256" => item.media_asset.sha256&.unpack1("H*"), "alt_text" => item.alt_text }
        end,
        "provider_options" => target.provider_options || {}
      }
      content_hash = Digest::SHA256.digest(canonical_json(content))
      snapshot = {
        "target_id" => target.id, "revision" => target.revision, "workspace_id" => target.workspace_id,
        "social_account_id" => target.social_account_id, "content_hash" => content_hash.unpack1("H*")
      }.merge(content)
      [snapshot, content_hash]
    end

    # The DTO handed to an addon.
    def to_dto(snapshot)
      SignalCraft::SocialPublisher::TargetSnapshot.new(
        target_id: snapshot["target_id"], revision: snapshot["revision"], workspace_id: snapshot["workspace_id"],
        social_account_id: snapshot["social_account_id"], text: snapshot["text"],
        media: snapshot["media"].map(&:freeze).freeze, provider_options: snapshot["provider_options"].freeze,
        content_hash: snapshot["content_hash"]
      ).freeze
    end

    # Keys sorted at every level, so equal content always hashes equally.
    def canonical_json(value)
      JSON.generate(deep_sort(value))
    end

    def deep_sort(value)
      case value
      when Hash then value.keys.map(&:to_s).sort.to_h { |key| [key, deep_sort(value[key] || value[key.to_sym])] }
      when Array then value.map { |item| deep_sort(item) }
      else value
      end
    end
  end
end
