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
  # Loading a container onto the ramp takes this long, in the ship's own
  # process. It is the rate limit and the lesson in one: a ship ships at ramp
  # speed however fast anyone taps, and the taps beyond it pile up as a real
  # message queue on the visitor's own process - findable in Voyager.
  ship_load_ms: 300,
  # Past this mailbox depth the cockpit stops accepting presses at all: an
  # autoclicker gets a bounded queue, not an unbounded one.
  ship_queue_cap: 30,
  # The warehouse queue depth at which the station tells everyone it is choking.
  congested_queue: 100,

  # --- cargo -----------------------------------------------------------------
  # `chunks` are 32 byte pieces, so they decide how fast warehouse memory grows.
  # `inspection_rounds` decide how long a single container takes to clear.
  # These two are knobs one and two of the four in the concept.
  #
  # The rounds below are the cost for ONE docked visitor - 40 / 400 / 400 /
  # 800 ms per container - and the crowd divides them: with N ships docked a
  # container costs a Nth (see Cargo.effective_rounds/1). The offered load per
  # clerk is then the same whoever shows up, about 130% when the room really
  # races, so congestion is reachable by two people and survivable by thirty,
  # and the warehouse absorbs cargo fast enough that a crowd fills its memory
  # to capacity in minutes instead of feeding an ever-deeper queue. Measured at
  # 6060 rounds per millisecond on an M-class laptop.
  #
  # Every number under here is downstream of those four: one clerk clears about
  # three containers a second, and the fleet, the click rate and the haulers are
  # all set against that ceiling. Re-measure before changing any of them -
  # `mix station.calibrate` prints the real cost per cargo type on the box that
  # will run the booth, and the offered load at each traffic level.
  cargo_types: %{
    "ice" => %{
      label: "ICE",
      chunks: 16,
      inspection_rounds: 240_000,
      blurb: "Light, cheap, endless."
    },
    "ore" => %{
      label: "ORE",
      chunks: 128,
      inspection_rounds: 2_400_000,
      blurb: "The balanced default."
    },
    "machinery" => %{
      label: "MACHINERY",
      chunks: 1_024,
      inspection_rounds: 2_400_000,
      blurb: "Bulky. Fills the warehouse fastest."
    },
    "antimatter" => %{
      label: "ANTIMATTER",
      chunks: 16,
      inspection_rounds: 4_800_000,
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
  # Many freighters, each of them slow. The count is what the tree shows and the
  # interval is what the warehouse feels, so they are tuned separately: twenty
  # children under FreighterLine, together offering about 1.7 containers a
  # second - a little over half of what one clerk can clear. The station hums
  # with nobody in the room and the queue still sits at zero, which is what
  # makes the queue climbing mean something when a crowd arrives.
  traffic_levels: %{
    quiet: %{freighters: 10, interval_ms: 5_000},
    normal: %{freighters: 20, interval_ms: 3_300},
    rush_hour: %{freighters: 40, interval_ms: 1_200}
  },
  # Antimatter is mostly a visitor's choice. If the background fleet carried it
  # in equal measure the sea level would be antimatter and the punchline about
  # one visitor's cargo costing twenty times another's would drown in it.
  freighter_cargo_weights: [ice: 40, ore: 35, machinery: 20, antimatter: 5],
  # A short trip, so freighters are visibly born and visibly die in the tree
  # rather than sitting there for eight minutes.
  freighter_runs: 15,
  haulers: 3,
  # Multipliers for `Dispatch extra haulers`. They have to be big: the point of
  # that button is that the memory trend turns around while somebody watches it,
  # and a small boost only slows the climb down.
  hauler_boosts: [1, 4, 8],
  # Deliberately just under what the fleet delivers, so an idle station creeps
  # upward instead of sitting flat, and a boost visibly turns the line around.
  hauler_interval_ms: 1_200,
  hauler_batch: 2,

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
