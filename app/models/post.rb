# frozen_string_literal: true

# The shared draft. Each destination is a PostTarget with its own schedule,
# state and optional overrides (design specifications/02, Scheduling semantics).
class Post < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :updated_by, class_name: "User", optional: true
  has_many :post_media, -> { order(:position) }, class_name: "PostMedia", dependent: :destroy, inverse_of: :post
  has_many :post_targets, dependent: :restrict_with_error

  validates :body, length: { maximum: 20_000 }

  scope :active, -> { where(archived_at: nil) }

  # Editing the shared draft bumps the post revision and the revision of every
  # target that still inherits the shared text, so in-flight publications
  # notice the change. Targets with their own text are untouched.
  def update_shared_body!(new_body, by:)
    transaction do
      lock!
      update!(body: new_body, revision: revision + 1, updated_by: by)
      post_targets.inheriting_body.editable.find_each { |target| target.bump_revision!(by: by) }
    end
  end
end
