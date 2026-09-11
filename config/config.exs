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
  # The cap is for the human eye, not the runtime. Eight ships is one legible
  # column on a television or a laptop lid; the BEAM would carry eight
  # thousand. Freighters count towards it like anyone else - a ship is a ship
  # on the screen.
  max_ships: 8,
  ship_ttl_ms: :timer.minutes(5),
  # A cockpit that goes dark undocks its ship after this long: enough for a
  # page reload or a wifi hiccup to reconnect unnoticed, short enough that a
  # locked phone frees its berth before the next visitor has read the QR code.
  # The ship waits in `Station.Hangar` for `ship_ttl_ms` and docks again, same
  # name and counters, when that session comes back.
  ship_leave_grace_ms: :timer.seconds(5),
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
  # `chunks` are 32 byte pieces, so they decide how fast warehouse memory grows -
  # the only thing the four types differ in. `inspection_rounds` decide how long
  # a container takes to clear, and they are the same for every type on purpose:
  # one cost per container makes the clerk maths legible from across the aisle
  # (N clerks clear N times as many a second, full stop).
  #
  # The rounds are the cost for ONE docked visitor - about 400 ms per container
  # - and the crowd divides them: with N ships docked a container costs a Nth
  # (see Cargo.effective_rounds/1). One visitor racing at ramp speed saturates
  # one clerk by about 130%; a room of them saturates it by the same margin.
  # A round is one `:erlang.phash2/1`, roughly 3 000 to 6 000 rounds per
  # millisecond on an M-class laptop depending on how warm it is;
  # `mix station.calibrate` prints the real numbers on the box that runs the booth.
  cargo_types: %{
    "ice" => %{
      label: "ICE",
      chunks: 16,
      inspection_rounds: 14_000_000,
      blurb: "Light, cheap, endless."
    },
    "ore" => %{
      label: "ORE",
      chunks: 128,
      inspection_rounds: 14_000_000,
      blurb: "The balanced default."
    },
    "machinery" => %{
      label: "MACHINERY",
      chunks: 1_024,
      inspection_rounds: 14_000_000,
      blurb: "Bulky. Fills the warehouse fastest."
    },
    "antimatter" => %{
      label: "ANTIMATTER",
      chunks: 16,
      inspection_rounds: 14_000_000,
      blurb: "Tiny, and just as much work as anything else."
    }
  },

  # --- warehouse -------------------------------------------------------------
  # Containers the shelf holds before the warehouse stops taking more. Nothing
  # is ever thrown away: a full warehouse holds the door and every container
  # that arrives waits in its mailbox until a hauler makes room. Sized so the
  # bay window on the television (96 cells) lights a cell every dozen
  # containers or so and a rush hour with the crew on fills it in minutes, not
  # an afternoon. A full hold with the queue climbing is the payoff - it has to
  # be reachable.
  warehouse_capacity: 1_200,
  # Clerks on shift when the station boots. Checksums always happen in clerk
  # processes, never in the warehouse itself; one clerk is the bottleneck demo,
  # and `OpsPanel.set_clerks/1` (or /ops) puts more on shift. The CREW button
  # on /ops is one per scheduler, capped at eight.
  clerks: 1,

  # --- haulers ---------------------------------------------------------------
  # The consumers. Deliberately few and slow at x1, so a room that has filled
  # the warehouse watches its memory creep down rather than vanish - and the
  # ops boost turns the drain up while somebody is looking at the line.
  haulers: 2,
  # Multipliers for `Dispatch extra haulers`. They have to be big: the point of
  # that button is that the memory trend turns around while somebody watches it,
  # and a small boost only slows the climb down.
  hauler_boosts: [1, 2, 4],
  # Deliberately just under what the fleet delivers, so an idle station creeps
  # upward instead of sitting flat, and a boost visibly turns the line around.
  hauler_interval_ms: 1_200,
  hauler_batch: 2,

  # --- freighters ------------------------------------------------------------
  # Simulated visitors, for a quiet aisle. Off until ops turns them on with
  # `OpsPanel.set_traffic/1`; the named levels are what the staff types.
  freighters: 0,
  traffic_levels: %{off: 0, quiet: 2, normal: 4, rush: 8},
  # Freighters step aside for people: with this on, every visitor who docks
  # sends one freighter home, so the screen holds a steady crowd whoever is in
  # it, and a station full of freighters still has a berth for a real visitor.
  # Off, freighters hold their berths and a full station is full.
  yield_to_visitors: true,
  # One container per tick per freighter, jittered around this. Freighters do
  # not divide the inspection cost the way visitors do, so their count is the
  # load: at 1.5 s a container and the average cargo mix, 2 freighters offer
  # about 45% of one clerk, 4 about 90%, 8 about 180% - quiet is a heartbeat,
  # normal is on the line, rush congests on its own and the queue climbs a few
  # a second. `mix station.calibrate` prints the real numbers for this box;
  # lower this and every level gets heavier in proportion.
  freighter_interval_ms: 1_500,
  # The pause with an empty hold before taking on a fresh one.
  freighter_resupply_ms: 4_000,

  # --- scenarios -------------------------------------------------------------
  # The rehearsed demos, one button each on /ops, in the order they are told.
  # A scenario names only the knobs it cares about (`clerks`, `freighters`,
  # `haulers`, `freighter_interval_ms`, `hauler_interval_ms`); anything it does
  # not name goes back to the baseline above, so two presses in a row always
  # land on the same station. `steps` is the presenter's script, printed on the
  # card: which Voyager tab to open, what to click, what should be happening
  # there, and the live fix to finish on.
  scenarios: [
    %{
      id: :steady_state,
      title: "Steady state",
      steps: [
        "Processes: find Station.Warehouse, clerk_01, the two freighters and the " <>
          "two haulers. Sort by message queue - everything sits at zero. One " <>
          "clerk keeps up with two freighters and two haulers take the cargo " <>
          "away as fast as it clears.",
        "Node Info: memory flat, run queues at zero. This is the baseline to " <>
          "compare the other stories against, and the place to come back to " <>
          "between them."
      ],
      clerks: 1,
      freighters: 2,
      haulers: 2
    },
    %{
      id: :inspection_queue,
      title: "Growing inspection queue",
      steps: [
        "Processes: sort by message queue length. clerk_01 goes to the top and " <>
          "keeps climbing - eight freighters, one mailbox. Station.Warehouse " <>
          "itself stays near zero: it only routes.",
        "Open clerk_01: message_queue_len and memory grow together, reductions " <>
          "never stop. Every container in that queue is a term in one " <>
          "process's heap.",
        "Node Info: the memory card. The processes slice rises with the queue - " <>
          "the whole node grows because one mailbox does.",
        "Fix live: press CREW under INSPECTION below. New clerk processes appear " <>
          "in Processes and the queue drains across them while the load spreads " <>
          "over every scheduler."
      ],
      clerks: 1,
      freighters: 8
    },
    %{
      id: :warehouse_filling,
      title: "Warehouse filling up",
      steps: [
        "Processes: sort by memory. Station.Warehouse climbs to the top and " <>
          "stays there - two clerks clear cargo faster than one hauler takes " <>
          "it away, and every accepted container is kept in process state.",
        "Open Station.Warehouse: browse the inbox. Once the shelf is full the " <>
          "warehouse holds the door and the containers pile up there instead " <>
          "- nothing is ever thrown away.",
        "Try fetching its state. Under load the call may time out, and that is " <>
          "the lesson: a dashboard asking a busy process about itself queues " <>
          "behind the cargo it is trying to measure.",
        "Television: the bay window fills; once FULL, QUEUE on this panel " <>
          "starts climbing. Fix live: x4 under HAULERS below and watch the " <>
          "warehouse's memory turn around in Processes."
      ],
      clerks: 2,
      freighters: 8,
      haulers: 1
    },
    %{
      id: :cpu_bottleneck,
      title: "CPU bottleneck",
      steps: [
        "Processes: clerk_01 to clerk_08 are on shift. Sort by message queue - " <>
          "the queue spreads over all eight and keeps growing, yet some of them " <>
          "show as waiting, not running, while their queue climbs.",
        "Node Info: the schedulers card. Two schedulers online, run queues " <>
          "stacked - the machine has only two cores, so only two clerks ever " <>
          "run at once. More processes is not more CPU.",
        "Ease off: set the freighter pace back up under SIMULATED VISITORS, or " <>
          "press Steady state."
      ],
      clerks: 8,
      freighters: 8,
      freighter_interval_ms: 300
    }
  ],

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
