# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Station tuning. Everything the booth staff might have to change on the first
# morning lives here, in one block, so tuning is an edit and a restart rather
# than a code change. The leaderboard survives that restart.
config :station,
  # --- ships -----------------------------------------------------------------
  # The cap is for the human eye, not the runtime. Twenty five nodes is already
  # a dense tree on a television; the BEAM would carry twenty five thousand.
  max_ships: 25,
  # Ship names really do become atoms. Past this budget new visitors get a name
  # from a fixed pool instead of one derived from what they typed.
  max_ship_atoms: 2_000,
  ship_ttl_ms: :timer.minutes(5),
  # One click removes exactly one box from the grid on the phone, so this is
  # also the size of that grid.
  hold_size: 120,
  # Server side, because a cookie clicker on a public URL invites autoclickers.
  # The congested ceiling is what makes a backed up station feel heavy in the thumb.
  transfer_limits: [per_second: 10, congested_per_second: 3, congested_queue: 250],

  # --- cargo -----------------------------------------------------------------
  # `chunks` are 32 byte pieces, so they decide how fast warehouse memory grows.
  # `inspection_rounds` decide how expensive a single click is in reductions.
  # These two are knobs one and two of the four in the concept.
  #
  # The defaults land near 0.5 / 3 / 3 / 25 ms per container on an Apple M-class
  # laptop. They are the numbers most likely to need retuning on the actual box
  # on the first morning: `mix station.calibrate` prints the measured costs and
  # what the warehouse can absorb before its queue starts climbing.
  cargo_types: %{
    "ice" => %{
      label: "ICE",
      chunks: 16,
      inspection_rounds: 3_000,
      blurb: "Light, cheap, endless."
    },
    "ore" => %{
      label: "ORE",
      chunks: 128,
      inspection_rounds: 18_000,
      blurb: "The balanced default."
    },
    "machinery" => %{
      label: "MACHINERY",
      chunks: 1_024,
      inspection_rounds: 18_000,
      blurb: "Bulky. Fills the warehouse fastest."
    },
    "antimatter" => %{
      label: "ANTIMATTER",
      chunks: 16,
      inspection_rounds: 150_000,
      blurb: "Tiny, and a nightmare to inspect."
    }
  },

  # --- warehouse -------------------------------------------------------------
  warehouse_mode: :single_clerk,
  warehouse_capacity: 12_000,
  # Defaults to one inspector per scheduler when unset.
  inspectors: nil,

  # --- background fleet ------------------------------------------------------
  # Knobs three and four: the sea level the human waves are visible against,
  # and the producer/consumer ratio that makes warehouse memory creep upward.
  traffic: :normal,
  traffic_levels: %{
    quiet: %{freighters: 8, interval_ms: 500},
    normal: %{freighters: 20, interval_ms: 200},
    rush_hour: %{freighters: 48, interval_ms: 120}
  },
  # Antimatter is mostly a visitor's choice. If the background fleet carried it
  # in equal measure the sea level would be antimatter and the punchline about
  # one visitor's cargo costing twenty times another's would drown in it.
  freighter_cargo_weights: [ice: 40, ore: 35, machinery: 20, antimatter: 5],
  freighter_runs: 60,
  haulers: 3,
  # Multipliers for `Dispatch extra haulers`. They have to be big: the point of
  # that button is that the memory trend turns around while somebody watches it,
  # and a small boost only slows the climb down.
  hauler_boosts: [1, 4, 8],
  hauler_interval_ms: 400,
  hauler_batch: 6,

  # --- safety ----------------------------------------------------------------
  watchdog: [max_queue: 5_000, max_run_queue: 200],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :station, StationWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StationWeb.ErrorHTML, json: StationWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Station.PubSub,
  live_view: [signing_salt: "tGTFMFNq"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  station: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  station: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
