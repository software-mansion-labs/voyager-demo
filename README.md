# Voyager Station

A booth demo for ElixirConf. The BEAM node _is_ a space station: visitors scan a
QR code, register a ship, and their ship joins this application's supervision
tree as a named process. [Voyager](https://github.com/software-mansion/voyager),
attached to the node from a laptop next to the television, shows it as facts
about a live node. The concept and the reasoning are in
[docs/concept.md](docs/concept.md).

| Screen          | URL              |
| --------------- | ---------------- |
| Television      | `/tv`            |
| Leaderboard     | `/leaderboard`   |
| Visitor's phone | `/` then `/ship` |

## Development

```bash
mix setup
mix phx.server
```

Open `/` in a phone-sized window and `/tv` in a wide one.

## Deploying to a server

Needs a box with Docker, a domain with an A record pointing at it, and ports 80
and 443 open. Everything else is in `docker-compose.yml`.

```bash
git clone git@github.com:software-mansion-labs/voyager-demo.git && cd voyager-demo
cp .env.example .env
```

Fill in `.env`:

| Variable          | Value                                                              |
| ----------------- | ------------------------------------------------------------------ |
| `PHX_HOST`        | the domain the phones will reach; it goes into the QR code as well |
| `SECRET_KEY_BASE` | `openssl rand -base64 48`                                          |
| `STATION_COOKIE`  | any private string; Voyager needs it to attach                     |
| `EPMD_PORT`       | leave `4369` unless the host runs its own Erlang                   |

Then:

```bash
docker compose up -d --build
```

Caddy answers on 80/443 with a Let's Encrypt certificate for `PHX_HOST` and
proxies to the station. The leaderboard survives redeploys in the `leaderboard`
volume. Redeploy with `git pull && docker compose up -d --build`; `up` alone
does not rebuild the image.

Check: `docker compose ps` shows `healthy`, `https://<PHX_HOST>/tv` opens and
the QR code on it leads to `https://<PHX_HOST>/`.

Two things the release insists on, in case the stack runs behind a different
reverse proxy than the bundled Caddy:

- **TLS is not optional.** `force_ssl` is compiled in, so the proxy has to
  terminate TLS and pass `X-Forwarded-Proto: https`. Without it every host but
  `localhost` redirects in a loop.
- **Open the pages through `PHX_HOST`.** LiveView rejects a websocket from any
  other origin, which shows up as "Attempting to reconnect" on the page. The
  proxy also has to pass the `Upgrade` and `Connection` headers.

## Attaching Voyager

EPMD and one fixed distribution port are published on the server's loopback
only. From the laptop, tunnel both and attach to `station@127.0.0.1` with
`STATION_COOKIE`:

```bash
ssh -N -L 4369:127.0.0.1:4369 -L 9100:127.0.0.1:9100 user@<server>
```

If the laptop runs its own Erlang, port 4369 is taken locally; set `EPMD_PORT`
on the server and tunnel that port instead.

## The staff's switches

There is no ops page. The switches live in `Station.OpsPanel` and are flipped
from a shell on the node:

```bash
docker compose exec station bin/station remote
```

| Call                                            | What it is for                                       |
| ----------------------------------------------- | ---------------------------------------------------- |
| `OpsPanel.set_warehouse_mode(:inspection_crew)` | the bottleneck demo, and its fix                     |
| `OpsPanel.set_hauler_boost(4)`                  | the producer/consumer demo, and its fix              |
| `DockingBay.remove(:ship_name)`                 | a name that got past the filter                      |
| `OpsPanel.restart_warehouse()`                  | shows a supervisor restart: cargo dies, ETS survives |
| `OpsPanel.reset_station()`                      | undock everyone, empty the shelves                   |
| `OpsPanel.reset_leaderboard()`                  | start a day from zero                                |

## Running on a laptop instead

The booth can also be one Linux laptop and the wifi it makes: no server, no
domain, no certificate. Run the dev server bound to the wifi address and the QR
code picks up the laptop's address on that network by itself
(`STATION_DOCK_URL` overrides it when the guess is wrong):

```bash
BIND_IP=0.0.0.0 elixir --name station@127.0.0.1 --cookie station-voy-1 -S mix phx.server
```

Voyager attaches to `station@127.0.0.1` with that cookie on the same machine.
Test on the actual network before the doors open: conference access points
often refuse to route between two clients, and a laptop hotspot holds around
ten phones.

## Tuning

Load is designed, not incidental, and the knobs sit in one block at the top of
`config/config.exs`. Run `mix station.calibrate` on the target machine first:
it prints the cost of each cargo type there and whether the bottleneck demo
will fire.
