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
  # The cap is for the human eye, not the runtime. Sixteen ships is two full
  # columns on the television; the BEAM would carry sixteen thousand. Freighters
  # count towards it like anyone else - a ship is a ship on the screen.
  max_ships: 16,
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
  # 6060 rounds per millisecond on an M-class laptop; `mix station.calibrate`
  # prints the real numbers on the box that will run the booth.
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
  # Containers held before the oldest go over the side. Sized so the bay window
  # on the television (96 cells) lights a cell every dozen containers or so and
  # a rush hour with the crew on fills it in minutes, not an afternoon. The
  # jettison line on the wall is the payoff - it has to be reachable.
  warehouse_capacity: 1_200,
  # Defaults to one inspector per scheduler when unset.
  inspectors: nil,

  # --- haulers ---------------------------------------------------------------
  # The consumers. Deliberately few and slow at x1, so a room that has filled
  # the warehouse watches its memory creep down rather than vanish - and the
  # ops boost turns the drain up while somebody is looking at the line.
  haulers: 3,
  # Multipliers for `Dispatch extra haulers`. They have to be big: the point of
  # that button is that the memory trend turns around while somebody watches it,
  # and a small boost only slows the climb down.
  hauler_boosts: [1, 4, 8],
  # Deliberately just under what the fleet delivers, so an idle station creeps
  # upward instead of sitting flat, and a boost visibly turns the line around.
  hauler_interval_ms: 1_200,
  hauler_batch: 2,

  # --- freighters ------------------------------------------------------------
  # Simulated visitors, for a quiet aisle. Off until ops turns them on with
  # `OpsPanel.set_traffic/1`; the named levels are what the staff types.
  freighters: 0,
  traffic_levels: %{off: 0, quiet: 3, normal: 8, rush: 16},
  # Freighters step aside for people: with this on, every visitor who docks
  # sends one freighter home, so the screen holds a steady crowd whoever is in
  # it, and a station full of freighters still has a berth for a real visitor.
  # Off, freighters hold their berths and a full station is full.
  yield_to_visitors: true,
  # One container per tick per freighter, jittered around this. Freighters do
  # not divide the inspection cost the way visitors do, so their count is the
  # load: at 2.5 s a container and the average cargo mix, 3 freighters offer
  # about 40% of one clerk, 8 about 100%, 16 about 200% - quiet is a heartbeat,
  # normal is on the line, rush congests on its own and the queue climbs a few
  # a second. `mix station.calibrate` prints the real numbers for this box;
  # lower this and every level gets heavier in proportion.
  freighter_interval_ms: 2_500,
  # The pause with an empty hold before taking on a fresh one.
  freighter_resupply_ms: 4_000,

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
