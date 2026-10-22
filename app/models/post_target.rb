# frozen_string_literal: true

# One scheduled publication of a post to one account. Each platform's copy
# can be edited on its own before publishing begins (design specifications/05,
# Editing a queued post for one platform; 02, Publishing state and delivery).
class PostTarget < ApplicationRecord
  MODES = %w[manual queue now].freeze
  STATES = %w[
    draft scheduled preparing publishing awaiting_provider published
    retry_wait blocked needs_attention failed cancelled
  ].freeze
  ATTENTION_REASONS = %w[publication_unconfirmed schedule_missed unsupported_checkpoint_version].freeze
  BLOCKED_REASONS = %w[
    account_disconnected reauthorization_required plugin_unavailable plugin_disabled
    validation_failed budget_exhausted protected_media_incompatible media_unavailable
    fetch_url_unavailable
  ].freeze

  # Content can change only before publishing begins. A target that may
  # already be on the platform (publication_unconfirmed) is never edited.
  EDITABLE_STATES = %w[draft scheduled retry_wait blocked].freeze

  # Marker for "leave this field as it is" in #edit_for_platform!.
  UNCHANGED = Object.new.freeze

  class NotEditable < StandardError
    def initialize(target)
      super("#{target.social_account&.display_name || 'This target'} can no longer be edited (#{target.state}); " \
            "copy it to a new draft instead")
    end
  end

  belongs_to :workspace
  belongs_to :post
  belongs_to :social_account
  belongs_to :creator, class_name: "User", foreign_key: :created_by, optional: true
  belongs_to :updater, class_name: "User", foreign_key: :updated_by, optional: true
  has_many :post_target_media, -> { order(:position) }, class_name: "PostTargetMedia",
                                                         dependent: :destroy, inverse_of: :post_target
  has_one :queue_entry, dependent: :destroy
  has_many :publish_intents, dependent: :restrict_with_error
  has_many :publish_attempts, dependent: :restrict_with_error

  string_enum :mode, MODES
  string_enum :state, STATES
  string_enum :attention_reason, ATTENTION_REASONS, prefix: :attention, validate: { allow_nil: true }
  string_enum :blocked_reason, BLOCKED_REASONS, prefix: :blocked_by, validate: { allow_nil: true }

  validates :body_override, length: { maximum: 20_000 }
  validates :occurrence, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :reasons_match_state
  validate :manual_targets_have_a_time

  scope :editable, lambda {
    where(state: EDITABLE_STATES).or(where(state: "needs_attention", attention_reason: "schedule_missed"))
  }
  scope :inheriting_body, -> { where(body_override: nil) }

  def editable?
    EDITABLE_STATES.include?(state) || (needs_attention? && attention_schedule_missed?)
  end

  def body_overridden?
    !body_override.nil?
  end

  # Text this platform will publish.
  def effective_body
    body_overridden? ? body_override : post.body
  end

  # Media this platform will publish, in order.
  def effective_media
    media_overridden? ? post_target_media : post.post_media
  end

  # Changes only this platform's copy. Fields passed as UNCHANGED keep their
  # current value (inherited or overridden). The schedule, queue slot and
  # sibling targets are never touched. `media` is a list of
  # { media_asset:, alt_text: } in publishing order.
  def edit_for_platform!(by:, body: UNCHANGED, media: UNCHANGED, provider_options: UNCHANGED)
    transaction do
      lock!
      raise NotEditable, self unless editable?

      self.body_override = body unless body.equal?(UNCHANGED)
      self.provider_options = provider_options unless provider_options.equal?(UNCHANGED)
      replace_media!(media) unless media.equal?(UNCHANGED)
      self.revision += 1
      self.updater = by
      save!
    end
    self
  end

  # "Reset to shared" for the text.
  def reset_body_to_shared!(by:)
    transaction do
      lock!
      raise NotEditable, self unless editable?

      update!(body_override: nil, revision: revision + 1, updater: by)
    end
  end

  # "Reset to shared" for the media.
  def reset_media_to_shared!(by:)
    transaction do
      lock!
      raise NotEditable, self unless editable?

      post_target_media.delete_all
      update!(media_overridden: false, revision: revision + 1, updater: by)
    end
  end

  def bump_revision!(by:)
    update!(revision: revision + 1, updater: by)
  end

  private

  def replace_media!(items)
    post_target_media.delete_all
    Array(items).each_with_index do |item, position|
      post_target_media.create!(workspace_id: workspace_id, media_asset: item.fetch(:media_asset),
                                alt_text: item[:alt_text], position: position)
    end
    self.media_overridden = true
  end

  def reasons_match_state
    errors.add(:attention_reason, "is required when the target needs attention") if needs_attention? && attention_reason.nil?
    errors.add(:attention_reason, "must be empty unless the target needs attention") if !needs_attention? && attention_reason
    errors.add(:blocked_reason, "is required when the target is blocked") if blocked? && blocked_reason.nil?
    errors.add(:blocked_reason, "must be empty unless the target is blocked") if !blocked? && blocked_reason
  end

  def manual_targets_have_a_time
    return unless manual? && !draft? && !cancelled? && due_at.nil?

    errors.add(:due_at, "is required for a fixed-time publication")
  end
end
