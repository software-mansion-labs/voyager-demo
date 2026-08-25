# Station VOY-1

A booth demo for ElixirConf. The BEAM node *is* a space station: visitors scan a
QR code, register a ship, and their ship joins this application's supervision
tree as a named process. Everything they do afterwards is ordinary message
passing between processes — and [Voyager](https://github.com/software-mansion/voyager),
running on a laptop next to the television, shows it as facts about a live node.

Two screens make the demo:

| Screen | URL | What it is |
| --- | --- | --- |
| Laptop | Voyager, attached over SSH | **the truth** |
| Television | `/tv` | **the narrative** |
| Visitor's phone | `/` then `/ship` | the thing worth pressing |
| Booth staff | `/ops/<token>` | the two switches that are the demo |

That head movement — left to the television, right to the laptop — is the whole
point. Nothing on the television is a metaphor: the crates queueing outside the
warehouse are `message_queue_len`, the shelves inside it are process state, and
the leaderboard is a dump of an ETS table.

The full concept, including the reasoning behind each decision, is in
[docs/concept.md](docs/concept.md).

## Running it locally

```bash
mix setup
mix phx.server
```

Then open `/` on a phone-sized window, `/tv` on a wide one, and `/ops/dev` with
the username and password `ops` / `ops`.

To attach Voyager to a station running on your own machine, start it as a named
node so there is something to connect to:

```bash
elixir --sname station --cookie station-voy-1 -S mix phx.server
```

## The demo, in ninety seconds

Not a script to get through — a running order the staff can join and leave at
any point.

1. **"Register your ship."** `ship_*` slides into the supervision tree. *That
   dot is you.*
2. **"Keep pressing."** Ship memory falls, warehouse memory rises, warehouse
   reductions climb. Two processes, one press.
3. **"He is carrying ice, you are carrying antimatter."** Same press, twenty
   times the cost. Compare the reductions.
4. **"Now everybody at once."** The warehouse queue climbs into the hundreds and
   the phones start to feel heavy.
5. **"Find the bottleneck."** Sort processes by reductions → `Station.Warehouse`
   → read the queue in the details panel.
6. **Staff flips `INSPECTION CREW`.** The queue drains while everyone watches,
   the load spreads across every scheduler, the process count jumps.
7. **"So why is memory still climbing?"** Too few haulers → `Dispatch extra
   haulers` → the memory trend turns around.
8. **"And your score?"** The ETS browser, your row in `:station_leaderboard`,
   which outlives all of it.
9. **"Ask it something."** MCP answers in a normal sentence.

Steps 5 to 7 are the heart of it: **problem → diagnosis → fix → confirmation,
all of it in Voyager, inside a minute.**

## Tuning on the first morning

Twenty-five idle GenServers are nothing on the BEAM, so the load is designed
rather than incidental. Four knobs decide whether any of it is visible, and all
four live in one block at the top of `config/config.exs`:

1. **`:inspection_rounds`** per cargo — whether one press is visible at all.
2. **`:chunks`** per cargo — how fast warehouse memory grows.
3. **`:traffic_levels`** — the sea level the human waves show up against.
4. **`:haulers` and `:hauler_boosts`** — how fast memory creeps up, and how
   hard the fix pulls it back.

Measure before you turn anything:

```bash
mix station.calibrate
```

It prints the measured cost of one container of each cargo type on *this*
machine, what the warehouse can absorb before its queue starts climbing, and
the offered load at each traffic level. If a full house cannot push the station
past 100%, the bottleneck demo will not fire — raise `:inspection_rounds`. If
the station saturates with nobody in front of it, lower them.

## The ops panel

`/ops/<token>`, behind both an unguessable path segment and a password.

| Control | What it is for |
| --- | --- |
| `SINGLE CLERK` / `INSPECTION CREW` | the bottleneck demo, and its fix |
| `x1` / `x4` / `x8` haulers | the producer/consumer demo, and its fix |
| `QUIET` / `NORMAL` / `RUSH HOUR` | background traffic |
| `REMOVE` next to a ship | a name that got past the filter |
| `RESTART WAREHOUSE` | shows a supervisor restart: cargo dies, ETS survives |
| `RESET STATION` | undock everyone, empty the shelves |
| `RESET LEADERBOARD` | start a day from zero |

## Deploying to the booth

The station needs to be a **named node with a known cookie**, because the
laptop has to be able to attach to it. Distribution ports stay closed: Voyager
reaches it through an SSH tunnel with a proxied EPMD, which is itself one of the
features being demonstrated.

```bash
MIX_ENV=prod mix station.release
```

Then on the box:

```bash
export STATION_NODE_NAME=station@127.0.0.1
export STATION_COOKIE=...              # dedicated, rotated after the conference
export SECRET_KEY_BASE=...             # mix phx.gen.secret
export STATION_OPS_TOKEN=...           # mix phx.gen.secret 32
export STATION_OPS_PASSWORD=...
export STATION_LEADERBOARD_PATH=/var/lib/station/leaderboard.ets
export PHX_HOST=... PORT=4000
bin/server
```

`STATION_NODE_NAME` and `STATION_COOKIE` are required rather than defaulted on
purpose. A station that quietly came up unnamed would look perfect on the
television and be invisible to the laptop, which is the one failure nobody
notices until the doors open.

Keep `STATION_LEADERBOARD_PATH` **outside** the release directory. It is the
one file that has to survive a redeploy — it is the third level of the
persistence story the booth tells:

```
process state  →  dies with the process
ETS            →  survives the process, dies with the node
file           →  survives the node
```

Other deployment notes, in the order they will bite:

- **Put the VPS near the venue.** A tree walk is roughly `6 + 2 × depth`
  round trips inside a five second deadline, so latency multiplies by about
  fourteen at depth four. At 30–50 ms the walk finishes in about a second; at
  150 ms it is grazing the deadline.
- **Take a machine with room** (4+ vCPU). It does not weaken the demo, it
  sharpens it: a queue backing up on one process while three quarters of the
  machine sits idle is exactly what the run queues should show.
- **Treat the credentials as burned.** A single-use VPS, a dedicated cookie, a
  dedicated SSH key, all rotated afterwards. Visitors touch the laptop.

## How it is built

One application, one supervision tree, one system. No Ecto: all state is in
processes, one ETS table, and one file on disk.

```
station (app)
└─ Station.Supervisor
   ├─ Station.OpsPanel          – the staff's switches
   ├─ Station.Leaderboard       – owns the ETS table and its snapshot
   ├─ Station.InspectionCrew    – the checksum pool (empty in SINGLE CLERK)
   ├─ Station.Warehouse         – every container ever sent, in process state
   ├─ Station.DockingBay        – visitors' ships
   │  ├─ ship_millennium_falcon
   │  └─ …                      (capped at ~25)
   ├─ Station.TrafficControl
   │  ├─ Station.Dispatcher     – keeps both lines staffed
   │  ├─ Station.FreighterLine  – producers, many
   │  └─ Station.HaulerLine     – consumers, deliberately too few
   └─ Station.Watchdog          – samples the vitals, cuts traffic if drowning
```

Two rules the code sticks to, both of which the demo depends on:

- **Nothing asks the warehouse about itself.** It is the process we deliberately
  congest, so a dashboard sending it a message would queue behind the cargo it
  is trying to measure. `Station.Watchdog` samples it once per tick into
  `Station.Metrics` (lock-free `:counters`), and every phone, screen and rate
  limiter reads from there.
- **Cargo is terms, not one big binary.** A large refc binary would be shared
  rather than copied, so ship memory would not fall and warehouse memory would
  not rise — and the whole visual would quietly stop being true.

### Ship names really do become atoms

That is the lesson, not an oversight: the atom counter on the television goes up
with every new name and never comes back down. The blast radius is bounded on
purpose — a fixed character set, a length cap, a profanity filter, exact
accounting of every name minted, and a hard budget past which visitors get a
name from a finite pool instead of one derived from their input.

## Where this differs from the concept

Three things the concept in `docs/concept.md` did not anticipate, all found
while building it:

- **The warehouse collects its own garbage** once haulers have taken enough
  away. Dropping references does not shrink a process heap, so "dispatch extra
  haulers and watch the memory fall" simply did not happen on screen without it.
- **Overflow is jettisoned in batches.** At the capacity ceiling every single
  arrival is an overflow, and one-in-one-out filled the event log with the same
  line hundreds of times a second.
- **`Station.ShipRegistry` does not exist.** Ships are registered under their
  own atom, so `Process.whereis/1` already does everything a `Registry` would
  have, one box fewer in the tree. `Station.Dispatcher` is the one addition:
  something has to keep the churning fleet staffed.

The background fleet also stays off the leaderboard. Robots outscoring the
humans fifty to one leaves nobody a row to look for.
