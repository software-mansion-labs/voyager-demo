import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :station, StationWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "SHUse7zFzEXhd+uD5W4ZrJyFMEFtdqbCESqb5lDL7xPchWYbbtrHqlrT/jKIZnvD",
  server: false

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

# Station: local defaults. The prod values come from the environment, see
# config/runtime.exs.
# Haulers are off in tests - a drain running in the background makes assertions
# about the warehouse flaky. Cargo is tiny and the inspection is cheap so the
# suite stays fast.
config :station,
  haulers: 0,
  hold_size: 5,
  warehouse_capacity: 10,
  hauler_batch: 2,
  max_ships: 3,
  # The ramp is instant in tests - the suite asserts on flow, not on pacing.
  ship_load_ms: 0,
  ship_queue_cap: 5,
  congested_queue: 250,
  cargo_types: %{
    "ice" => %{label: "ICE", chunks: 1, inspection_rounds: 10, blurb: "Light, cheap, endless."},
    "ore" => %{label: "ORE", chunks: 2, inspection_rounds: 2_000, blurb: "The balanced default."},
    "machinery" => %{
      label: "MACHINERY",
      chunks: 8,
      inspection_rounds: 2_000,
      blurb: "Bulky. Fills the warehouse fastest."
    },
    "antimatter" => %{
      label: "ANTIMATTER",
      chunks: 1,
      inspection_rounds: 40_000,
      blurb: "Tiny, and a nightmare to inspect."
    }
  },
  leaderboard_path: "priv/leaderboard_test.ets",
  ops_token: "dev",
  ops_username: "ops",
  ops_password: "ops"
