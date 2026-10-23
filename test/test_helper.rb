ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    PASSWORD = "correct horse battery staple"
  end
end

# Builds posts, targets and queue slots for scheduling and publishing tests.
module SchedulingHelper
  def daily_slots!(queue, *times)
    queue.replace_slots!((1..7).to_a.product(times), timezone: queue.timezone, by: users(:alice))
  end

  def new_target(account: social_accounts(:studio_bluesky), body: "Queued post", occurrence: 1)
    post = Post.create!(workspace: account.workspace, body: body, creator: users(:alice))
    PostTarget.create!(workspace: account.workspace, post: post, social_account: account, occurrence: occurrence,
                       mode: "queue", state: "draft", creator: users(:alice))
  end

  def queued_target(**options)
    new_target(**options).schedule!(by: users(:alice), mode: "queue")
  end
end

class ActiveSupport::TestCase
  include SchedulingHelper
end

module SignInHelper
  def sign_in_as(user, password: ActiveSupport::TestCase::PASSWORD)
    post session_path, params: { email: user.email, password: password }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
end
