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

  # A schedule without a fixed wall-clock time.
  NO_FIXED_TIME = { scheduled_local_at: nil, scheduled_timezone: nil, scheduled_utc_offset_seconds: nil }.freeze

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
    while_editable do
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
    while_editable do
      update!(body_override: nil, revision: revision + 1, updater: by)
    end
  end

  # "Reset to shared" for the media.
  def reset_media_to_shared!(by:)
    while_editable do
      post_target_media.delete_all
      update!(media_overridden: false, revision: revision + 1, updater: by)
    end
  end

  def bump_revision!(by:)
    update!(revision: revision + 1, updater: by)
  end

  # --- Scheduling (design specifications/02, Scheduling semantics) ---------
  #
  # Changing the time is separate from editing content: these methods never
  # touch the text, media or revision. The account's queue row is locked
  # before the target row, the same order allocation and claims use.

  # A schedule that cannot be applied; the message is shown to the user.
  class ScheduleError < StandardError; end

  def requires_media?
    social_account.plugin.manifest.dig("capabilities", "requires_media") == true
  end

  # Why this target cannot be scheduled yet, or nil.
  def scheduling_problem
    "Needs a photo or video" if requires_media? && effective_media.empty?
  end

  # mode "queue": next free slot in the account's queue.
  # mode "manual": a fixed wall-clock time (`local_at`, a floating Time) in
  #   `timezone`; `utc_offset` picks one instant of a repeated DST time.
  # mode "now": due immediately; the dispatcher is notified.
  def schedule!(by:, mode:, local_at: nil, timezone: nil, utc_offset: nil, now: Time.current)
    mode = mode.to_s
    raise ScheduleError, "Unknown schedule mode" unless MODES.include?(mode)

    while_editable(with_queue: true) do |queue|
      problem = scheduling_problem
      raise ScheduleError, problem if problem

      case mode
      when "manual" then schedule_manual(local_at, timezone || social_account.timezone, utc_offset, now)
      when "now" then schedule_now(now)
      when "queue" then schedule_in_queue
      end
      self.updater = by
      save!
      sync_queue_membership!(queue, now)
      OutboxEvent.announce!(now? ? "post_target.publish_requested" : "post_target.scheduled",
                            subject: self, workspace: workspace, payload: { mode: mode })
      AuditEvent.record!(action: "post_target.scheduled", actor: by, workspace: workspace, subject: self,
                         details: { mode: mode, due_at: due_at&.iso8601 })
    end
    self
  end

  def publish_now!(by:, now: Time.current)
    schedule!(by: by, mode: "now", now: now)
  end

  # Back to draft ("Save draft"); leaves the queue.
  def unschedule!(by:, now: Time.current)
    change_to!("draft", by: by, now: now)
  end

  def cancel!(by:, now: Time.current)
    change_to!("cancelled", by: by, now: now)
  end

  private

  # Runs the block in a transaction holding this row's lock, after checking
  # that the locked row is still editable. With `with_queue`, the account's
  # queue row is locked first and passed to the block.
  def while_editable(with_queue: false)
    queue = ChannelQueue.for_account!(social_account) if with_queue
    transaction do
      queue&.lock!
      lock!
      raise NotEditable, self unless editable?

      yield queue
    end
  end

  def change_to!(new_state, by:, now:)
    while_editable(with_queue: true) do |queue|
      publish_intents.state_open.each(&:close!)
      update!(state: new_state, attention_reason: nil, blocked_reason: nil, retry_at: nil,
              due_at: manual? && new_state == "draft" ? due_at : nil, updater: by)
      sync_queue_membership!(queue, now)
      AuditEvent.record!(action: "post_target.#{new_state == 'draft' ? 'unscheduled' : 'cancelled'}",
                         actor: by, workspace: workspace, subject: self)
    end
    self
  end

  def schedule_manual(local_at, zone, utc_offset, now)
    raise ScheduleError, "Choose a date and time" if local_at.nil?

    due = Scheduling::WallClock.resolve(zone, local_at, utc_offset: utc_offset)
    raise ScheduleError, "Choose a time in the future" if due <= now

    assign_attributes(mode: "manual", due_at: due, scheduled_local_at: local_at, scheduled_timezone: zone,
                      scheduled_utc_offset_seconds: (local_at - due).to_i)
    become_scheduled
  rescue Scheduling::WallClock::Nonexistent, Scheduling::WallClock::Ambiguous => e
    raise ScheduleError, e.message
  end

  def schedule_now(now)
    assign_attributes(mode: "now", due_at: now, **NO_FIXED_TIME)
    become_scheduled
  end

  def schedule_in_queue
    # due_at is set by the queue allocator in the same transaction.
    assign_attributes(mode: "queue", **NO_FIXED_TIME)
    self.due_at = nil unless queue_entry
    become_scheduled
  end

  def become_scheduled
    assign_attributes(state: "scheduled", attention_reason: nil, blocked_reason: nil, retry_at: nil)
  end

  # Only scheduled queue-mode targets belong to the queue.
  def sync_queue_membership!(queue, now)
    if scheduled? && queue?
      queue.enqueue!(self, now: now)
    elsif QueueEntry.exists?(post_target_id: id)
      queue.dequeue!(self, now: now)
    end
    reload
  end

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
