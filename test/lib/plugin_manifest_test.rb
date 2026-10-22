# frozen_string_literal: true

require_relative "lib_test_helper"
require "signal_craft/plugins/manifest"

class PluginManifestTest < Minitest::Test
  Manifest = SignalCraft::Plugins::Manifest

  def social_manifest(overrides = {})
    {
      "id" => "example_social",
      "kind" => "social",
      "name" => "Example Social",
      "version" => "1.0.0",
      "plugin_api" => ">=1.2 <2.0",
      "entrypoint" => "ExampleSocial::Adapter",
      "auth" => { "strategy" => "oauth2_pkce", "scopes" => %w[profile publish] },
      "capabilities" => { "text" => true, "images" => true, "link_placement" => "in_post",
                          "metrics" => %w[likes replies] },
      "settings" => [{ "key" => "default_visibility", "type" => "enum",
                       "values" => %w[public unlisted], "default" => "public" }]
    }.merge(overrides)
  end

  def errors_for(data)
    Manifest.build(data)
    flunk "expected manifest to be invalid"
  rescue Manifest::Invalid => e
    e.errors
  end

  def test_valid_social_manifest_gets_defaults
    manifest = Manifest.build(social_manifest)

    assert manifest.social?
    assert_equal "example_social", manifest.id
    assert_equal Gem::Version.new("1.0.0"), manifest.version
    assert_equal true, manifest.capabilities["text"]
    assert_equal false, manifest.capabilities["video"], "missing capabilities default to false"
    assert_equal %w[likes replies], manifest.capabilities["metrics"]
    assert_equal 1, manifest.checkpoint_schema_version
    assert manifest.frozen?
  end

  def test_valid_commerce_manifest
    manifest = Manifest.build({
      "id" => "example_store", "kind" => "commerce", "name" => "Example Store", "version" => "0.1.0",
      "plugin_api" => ">= 1.2, < 2.0", "entrypoint" => "ExampleStore::Adapter",
      "auth" => { "strategy" => "api_key" },
      "capabilities" => { "webhooks" => true, "attribution_codes" => "discount" }
    })

    assert manifest.commerce?
    assert_equal "discount", manifest.capabilities["attribution_codes"]
    assert_equal false, manifest.capabilities["refunds_visible"]
  end

  def test_missing_required_fields
    errors = errors_for({})
    %w[id kind name version plugin_api entrypoint].each do |key|
      assert_includes errors, "missing required field '#{key}'"
    end
  end

  def test_rejects_bad_id_and_entrypoint
    errors = errors_for(social_manifest("id" => "Bad-ID", "entrypoint" => "not::a constant"))
    assert(errors.any? { |e| e.start_with?("'id' must match") })
    assert_includes errors, "'entrypoint' must be a Ruby constant name"
  end

  def test_rejects_incompatible_api_range
    errors = errors_for(social_manifest("plugin_api" => ">=2.0 <3.0"))
    assert(errors.any? { |e| e.include?("not compatible with this host's addon API") })
  end

  def test_rejects_unknown_fields_and_capabilities
    errors = errors_for(social_manifest("homepage" => "x",
                                        "capabilities" => { "txt" => true, "attribution_codes" => "none" }))
    assert_includes errors, "unknown manifest field 'homepage'"
    assert_includes errors, "unknown social capability 'txt'"
    assert_includes errors, "unknown social capability 'attribution_codes'", "commerce-only key on a social addon"
  end

  def test_rejects_invalid_capability_values
    errors = errors_for(social_manifest("capabilities" => {
                                          "text" => "yes", "link_placement" => "bio", "metrics" => %w[likes vibes]
                                        }))
    assert_includes errors, "capability 'text' must be true or false"
    assert(errors.any? { |e| e.start_with?("capability 'link_placement'") })
    assert(errors.any? { |e| e.start_with?("capability 'metrics'") })
  end

  def test_validates_settings_descriptors
    errors = errors_for(social_manifest("settings" => [
                                          { "key" => "a", "type" => "enum" },
                                          { "key" => "a", "type" => "colour" },
                                          { "key" => "token", "type" => "secret", "default" => "x" },
                                          { "key" => "privacy", "type" => "enum", "values_from" => "creator_info" }
                                        ]))
    assert_includes errors, "settings[0]: enum settings need a non-empty 'values' list or 'values_from'"
    assert_includes errors, "settings[1]: duplicate key 'a'"
    assert(errors.any? { |e| e.start_with?("settings[1]: 'type' must be one of") })
    assert_includes errors, "settings[2]: secret settings cannot have a default"
    refute(errors.any? { |e| e.start_with?("settings[3]") }, "dynamic enum values are allowed")
  end

  def test_rejects_unknown_auth_strategy
    errors = errors_for(social_manifest("auth" => { "strategy" => "magic" }))
    assert(errors.any? { |e| e.start_with?("'auth.strategy' must be one of") })
  end
end
