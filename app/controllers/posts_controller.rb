# frozen_string_literal: true

# The composer (design specifications/05, Composer and independent
# publishing times): one shared draft, one target per selected account,
# each with its own mode and time. Per-platform content edits go through
# PostTargetsController.
class PostsController < ApplicationController
  include WorkspaceAccess

  before_action :set_post, only: %i[edit update]

  def new
    @workspace = current_user.workspaces.active.find_by(id: params[:workspace_id]) ||
                 current_user.workspaces.active.order(:name).first
    return redirect_to(root_path, alert: "You're not a member of any workspace yet.") unless @workspace

    require_publisher!(@workspace.id)
    @accounts = @workspace.social_accounts.includes(:plugin, :channel_queue).order(:display_name)
    @post = @workspace.posts.new
  end

  def create
    @workspace = current_user.workspaces.active.find(params.require(:workspace_id))
    require_publisher!(@workspace.id)
    accounts = @workspace.social_accounts.where(id: Array(params[:account_ids]))
    if accounts.empty?
      redirect_to new_post_path(workspace_id: @workspace.id), alert: "Choose at least one account."
      return
    end

    @post = Post.transaction do
      post = @workspace.posts.create!(body: params.dig(:post, :body).to_s, creator: current_user, updater: current_user)
      accounts.each do |account|
        post.post_targets.create!(workspace: @workspace, social_account: account, mode: "queue", state: "draft",
                                  creator: current_user, updater: current_user)
      end
      post
    end
    AuditEvent.record!(action: "post.created", workspace: @workspace, subject: @post,
                       details: { targets: accounts.size })
    redirect_to edit_post_path(@post), notice: "Draft saved. Choose when each account publishes."
  end

  def edit
    @composer = Composer.new(@post).check!
    @tab = @post.post_targets.find_by(id: params[:target]) || @composer.rows.first&.target
  end

  # Saves the shared text, then applies the footer action to the schedule table.
  def update
    require_publisher!(@post.workspace_id)
    body = params.dig(:post, :body)
    @post.update_shared_body!(body.to_s, by: current_user) if body && body != @post.body
    @composer = Composer.new(@post.reload, schedule_params)

    case params[:commit_action]
    when "schedule", "schedule_ready"
      return confirm_publish_now if needs_now_confirmation?

      count = @composer.schedule!(by: current_user, only_ready: params[:commit_action] == "schedule_ready")
      if count.zero? && !@composer.all_ready?
        @tab = @composer.rows.first&.target
        flash.now[:alert] = "Fix the highlighted publications, or schedule only the ready ones."
        render :edit, status: :unprocessable_content
      else
        DispatchJob.perform_later if @composer.now_rows.any?
        redirect_to root_path(workspace_id: @post.workspace_id),
                    notice: "#{helpers.pluralize(count, 'publication')} scheduled."
      end
    else
      @composer.save_choices!(by: current_user)
      redirect_to edit_post_path(@post), notice: "Draft saved."
    end
  end

  private

  # Mixed immediate and future targets get a confirmation listing which
  # accounts publish now (05, Composer and independent publishing times).
  def needs_now_confirmation?
    @composer.check!
    proceeding = params[:commit_action] == "schedule_ready" || @composer.all_ready?
    proceeding && params[:confirmed_now].blank? && @composer.now_rows.any?
  end

  def confirm_publish_now
    @confirm_now = @composer.now_rows
    @confirm_action = params[:commit_action]
    @tab = @composer.rows.first&.target
    render :edit
  end

  def set_post
    @post = Post.where(workspace_id: accessible_workspace_ids).find(params[:id])
    membership_for(@post.workspace_id)
  end

  def schedule_params
    params.fetch(:schedule, {}).permit!.to_h.transform_values do |row|
      row.slice("mode", "local_at", "timezone", "utc_offset")
    end
  end
end
