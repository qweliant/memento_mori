# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :memento_mori, :scopes,
  owner: [
    default: true,
    module: MementoMori.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:owner, :id],
    schema_key: :owner_id,
    schema_type: :binary_id,
    schema_table: :owners,
    test_data_fixture: MementoMori.AccountsFixtures,
    test_setup_helper: :register_and_log_in_owner
  ]

config :memento_mori,
  ecto_repos: [MementoMori.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :memento_mori, MementoMoriWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MementoMoriWeb.ErrorHTML, json: MementoMoriWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MementoMori.PubSub,
  live_view: [signing_salt: "rIjcWTQD"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :memento_mori, MementoMori.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  memento_mori: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  memento_mori: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Background jobs: dead-man's-switch timers, drand round watch, fixity sweeps
config :memento_mori, Oban,
  repo: MementoMori.Repo,
  queues: [default: 10, timers: 5, fixity: 3],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

# ── Event sourcing (Commanded + EventStore) ─────────────────────────────────
# The capsule contract engine dispatches through MementoMori.CommandedApp; its
# immutable event streams (and therefore the audit ledger) live in
# MementoMori.EventStore. The adapter is overridden to in-memory in test.
config :memento_mori, MementoMori.CommandedApp,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: MementoMori.EventStore
  ]

config :memento_mori, event_stores: [MementoMori.EventStore]

config :memento_mori, MementoMori.EventStore,
  serializer: Commanded.Serialization.JsonSerializer,
  column_data_type: "jsonb"

# Whether to boot the async projection handlers (audit ledger + state
# projector). Turned off in test, where the in-memory adapter is used and the
# projection logic is exercised as pure functions instead.
config :memento_mori, start_projections: true

# Blind-index secret for HMAC lookup columns (email_hash). Dev/test values live
# in their env files; prod comes from CLOAK_HMAC_KEY at runtime. The algorithm
# is read from app config (cloak_ecto ignores the `use` opt), so it lives here.
config :memento_mori, MementoMori.Encryption.Vault.HashedHMAC,
  algorithm: :sha256,
  secret: Base.decode64!("gVdT6eL0m7wS3rH2yq8pXcJk9nB4vZ1aQ5fW0uY3tPg=")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
