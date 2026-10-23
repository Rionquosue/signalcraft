# frozen_string_literal: true

# Per-platform actions on one target: its own content (design
# specifications/05, Editing a queued post for one platform) and its
# schedule, which is a separate action from content edits.
class PostTargetsController < ApplicationController
  include WorkspaceAccess

  before_action :set_target
  before_action -> { require_publisher!(@target.workspace_id) }

  rescue_from PostTarget::NotEditable, PostTarget::ScheduleError do |error|
    redirect_to edit_post_path(@target.post, target: @target.id), alert: error.message
  end

  # Text for this platform only. Submitting the shared text unchanged keeps
  # the field inheriting.
  def update
    body = params.dig(:post_target, :body).to_s
    if !@target.body_overridden? && body == @target.post.body
      redirect_to edit_post_path(@target.post, target: @target.id), notice: "No changes."
      return
    end

    @target.edit_for_platform!(by: current_user, body: body)
    redirect_to edit_post_path(@target.post, target: @target.id),
                notice: "Saved for #{@target.social_account.display_name}. Other platforms are unchanged."
  end

  def reset_body
    @target.reset_body_to_shared!(by: current_user)
    redirect_to edit_post_path(@target.post, target: @target.id), notice: "Text follows the shared draft again."
  end

  def publish_now
    @target.publish_now!(by: current_user)
    DispatchJob.perform_later
    redirect_back_or_to root_path, notice: publish_now_notice
  end

  def unschedule
    @target.unschedule!(by: current_user)
    redirect_back_or_to root_path, notice: "Moved back to drafts."
  end

  def cancel
    @target.cancel!(by: current_user)
    redirect_back_or_to root_path, notice: "Publication cancelled."
  end

  # "Copy to new draft" for targets that can no longer be edited.
  def copy
    post = Post.transaction do
      copy = Post.create!(workspace_id: @target.workspace_id, body: @target.effective_body, creator: current_user,
                          updater: current_user)
      copy.post_targets.create!(workspace_id: @target.workspace_id, social_account: @target.social_account,
                                mode: "queue", state: "draft", provider_options: @target.provider_options,
                                creator: current_user, updater: current_user)
      copy
    end
    redirect_to edit_post_path(post), notice: "Copied to a new draft. The original publication is unchanged."
  end

  private

  def set_target
    @target = PostTarget.where(workspace_id: accessible_workspace_ids).find(params[:id])
  end

  def publish_now_notice
    if @target.social_account.channel_queue&.paused?
      "#{@target.social_account.display_name} is paused, so this will not publish until the account is resumed."
    else
      "Publishing to #{@target.social_account.display_name} now."
    end
  end
end
