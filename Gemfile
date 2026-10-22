source "https://rubygems.org"

ruby ">= 3.3"

# Rails 8.1 is the planning baseline (design specifications/02).
gem "rails", "~> 8.1.4"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Existing PostgreSQL server (design specifications/02, Deployment topology)
gem "pg", "~> 1.1"
# Web server
gem "puma", ">= 5.0"
# Hotwire: JavaScript with import maps, Turbo and Stimulus
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

# has_secure_password (bcrypt cost 12; design specifications/02, Credential storage)
gem "bcrypt", "~> 3.1.7"

# Database-backed Active Job backend in the application database; no Redis.
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Addons (design specifications/04). Each addon is a gem in its own
# directory under plugins/ (/var/www/signalcraft/plugins in a deployment).
# They are resolved when the image is built; nothing is installed at runtime.
Dir.glob(File.join(__dir__, "plugins", "*", "*.gemspec")).sort.each do |gemspec|
  gem File.basename(gemspec, ".gemspec"), path: File.dirname(gemspec)
end

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"

  # Audits gems for known security defects
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
