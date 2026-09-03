# Voyager Station

A booth demo for ElixirConf. The BEAM node _is_ a space station: visitors scan a
QR code, register a ship, and their ship joins this application's supervision
tree as a named process. Everything they do afterwards is ordinary message
passing between processes — and [Voyager](https://github.com/software-mansion/voyager),
running on a laptop next to the television, shows it as facts about a live node.

Two screens make the demo:

| Screen          | URL                        | What it is                         |
| --------------- | -------------------------- | ---------------------------------- |
| Laptop          | Voyager, attached over SSH | **the truth**                      |
| Television      | `/tv`                      | **the narrative**                  |
| Leaderboard     | `/leaderboard`             | the ETS table, on its own screen   |
| Visitor's phone | `/` then `/ship`           | the thing worth pressing           |
| Booth staff     | `/ops/<token>`             | the two switches that are the demo |

That head movement — left to the television, right to the laptop — is the whole
point.

The television is a scene, not a dashboard with pictures on it. Visitors' ships
fly in and dock along the left arm, containers cross the gap to the station one
at a time, the bay window fills up with what the warehouse is holding, and
haulers on the right pull cargo back out. None of it is a metaphor: **every
crate in flight is a delivery that actually happened in the last second**, the
pile outside the bay door is `message_queue_len`, the bay window is process
state, and the leaderboard is a dump of an ETS table. The phone shows the same
crossing at arm's length — press the button and watch your container leave your
ship.

The one honest compromise is a cap on crates in flight: at a busy moment the
station moves a few hundred containers a second, no television can draw that
many, and past the cap the counters underneath carry the number.

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

1. **"Register your ship."** `ship_*` slides into the supervision tree. _That
   dot is you._
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
rather than incidental — and all of it is visitors: nothing sends the warehouse
a message except the people in the room. Four knobs decide whether any of it is
visible, and all four live in one block at the top of `config/config.exs`:

1. **`:inspection_rounds`** per cargo — the cost of one press for one lone
   visitor. The crowd divides it, so a room saturates the clerk by the same
   margin as one racing thumb.
2. **`:chunks`** per cargo — how fast warehouse memory grows.
3. **`:ship_load_ms`** — the ramp: how fast one ship can ship, and what a
   faster thumb piles up on its own process.
4. **`:haulers` and `:hauler_boosts`** — the drain, and how hard the fix
   pulls the memory back down.

Measure before you turn anything:

```bash
mix station.calibrate
```

It prints the measured cost of one container of each cargo type on _this_
machine, what the warehouse can absorb before its queue starts climbing, and
the load a racing room offers per clerk. If that number is under 100%, the
bottleneck demo will not fire — raise `:inspection_rounds`.

## The ops panel

`/ops/<token>`, behind both an unguessable path segment and a password.

| Control                            | What it is for                                       |
| ---------------------------------- | ---------------------------------------------------- |
| `SINGLE CLERK` / `INSPECTION CREW` | the bottleneck demo, and its fix                     |
| `x1` / `x4` / `x8` haulers         | the producer/consumer demo, and its fix              |
| `REMOVE` next to a ship            | a name that got past the filter                      |
| `RESTART WAREHOUSE`                | shows a supervisor restart: cargo dies, ETS survives |
| `RESET STATION`                    | undock everyone, empty the shelves                   |
| `RESET LEADERBOARD`                | start a day from zero                                |

## Running the booth

The booth is one Linux laptop and the wifi it makes. There is no server, no
domain and no certificate: the laptop runs the station, drives the television
out of its second video output, and hands out the network the phones join.

```bash
BIND_IP=0.0.0.0 elixir --name station@127.0.0.1 --cookie station-voy-1 -S mix phx.server
```

`BIND_IP` is the whole difference between a station a phone can reach and one
only the laptop can see - the default is loopback, because a development
machine has no business being reachable from the room it is in.

Then, on that laptop:

| screen                                 | where                                            |
| -------------------------------------- | ------------------------------------------------ |
| television, second display, fullscreen | `/tv`                                            |
| Voyager, on the laptop's own screen    | attaches to `station@<hostname>` with the cookie |
| booth staff, on a phone                | `/ops/dev`, username and password `ops`          |

The television carries the QR code, and the QR code carries **the address the
laptop actually has on that network** - read off the running machine at page
load rather than written down the night before, because the one thing that is
certainly different at the venue is which address the laptop got. Reload `/tv`
after joining a different network and the code follows. `STATION_DOCK_URL`
overrides it when the guess is wrong, which happens when the laptop is on wifi
and ethernet at once.

Two things to test on the actual network before the doors open:

- **Client isolation.** Plenty of conference access points refuse to route
  between two clients, and a station nobody can reach is a black television.
  Scan the code from a phone on that network. If it fails, the laptop's own
  hotspot is the answer, and it is also the answer to the venue's wifi going
  down at eleven.
- **How many phones the hotspot really holds.** A laptop access point is
  usually good for something like ten clients, and the ship cap is
  twenty five. That gap is worth knowing about in advance rather than
  discovering it with a queue standing there.

Nothing is exposed beyond that network: the station listens on the laptop's
wifi address, and the node is only reachable from the laptop itself.

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
   │  ├─ Station.Dispatcher     – keeps the hauler crew staffed
   │  └─ Station.HaulerLine     – consumers, deliberately too few
   └─ Station.Watchdog          – samples the vitals, sounds the alarm
```

The scene is server-authoritative and client-drawn. The LiveView sends one JSON
snapshot per second — who is docked, what each of them shipped since the last
tick, how many haulers are on duty, how deep the queue is — and a single hook
turns that into ships, crossings and pickups. The scene sits behind
`phx-update="ignore"`, so everything inside it belongs to the hook; anything the
server renders in there freezes at mount.

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
- **The television became a scene.** The concept described a pixel-art station
  with ships and a conveyor; what it did not say is that a dashboard with sprites
  on it reads as a dashboard. Ships now fly in, cargo crosses, haulers leave.
- **`Station.ShipRegistry` does not exist.** Ships are registered under their
  own atom, so `Process.whereis/1` already does everything a `Registry` would
  have, one box fewer in the tree. `Station.Dispatcher` is the one addition:
  something has to keep the churning fleet staffed.

The background fleet also stays off the leaderboard. Robots outscoring the
humans fifty to one leaves nobody a row to look for.
