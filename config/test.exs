import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, rounds: 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :memento_mori, MementoMori.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "memento_mori_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :memento_mori, MementoMoriWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MPbplyU5OAlm54GVsSvlhxevfBIMCBIrqfodbvAGk8ksGe/V16c31b4JYA56jC81",
  server: false

# In test we don't send emails
config :memento_mori, MementoMori.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Run Oban jobs manually in tests (no queues/plugins running)
config :memento_mori, Oban, testing: :manual

# In test, dispatch against an in-memory event store (fast, no Postgres event
# store) and don't boot the Postgres event store or the async projection
# handlers — the aggregate and hash chain are covered as pure functions.
config :memento_mori, MementoMori.CommandedApp,
  event_store: [adapter: Commanded.EventStore.Adapters.InMemory],
  serializer: Commanded.Serialization.JsonSerializer

config :memento_mori, event_stores: []
config :memento_mori, start_projections: false

# Blind-index secret for HMAC lookup columns in test.
config :memento_mori, MementoMori.Encryption.Vault.HashedHMAC,
  secret: Base.decode64!("Zm9vYmFydGVzdHNlY3JldGtleWZvcmhtYWMxMjM0NTY3OA==")

# Application-level encryption (test key)
config :memento_mori, MementoMori.Encryption.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("8BgLhbl3uz9DafEUy7gsjmldKWP8w9yYG5VhEq2+Odw=")}
  ]
