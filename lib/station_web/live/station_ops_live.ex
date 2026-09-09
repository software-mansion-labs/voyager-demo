defmodule StationWeb.StationOpsLive do
  @moduledoc """
  The television. The narrative half of the booth.

  It is a scene, not a dashboard with pictures on it. Visitors' ships fly in and
  dock along the left arm, containers cross the gap to the station one at a
  time, and haulers on the right pull cargo back out. The station in the middle
  is `Station.Warehouse` drawn as the pipeline it is, left to right: INTAKE,
  where crates land and the number is everything not yet on the shelf - the
  warehouse mailbox plus whatever the crew holds; INSPECTION, one lane per
  clerk, lit while it is checksumming; the HOLD, one tile per container in the
  process's state, coloured by cargo; and OUTBOUND, where the haulers collect.

  None of it is decoration. Every crate in flight is a delivery that actually
  happened in the last second, every tile is a container really on the shelf,
  and the lanes are the clerks ops just put on shift. The hold goes red when
  the warehouse is full and jettisoning. The visitor watches it here and then
  confirms every bit of it in Voyager, two feet to the left.

  The one honest compromise is the cap: at a busy moment the station moves a few
  hundred containers a second and no television can draw that, so past the cap
  the counters underneath carry the number.
  """

  use StationWeb, :live_view

  alias Station.Cargo
  alias Station.Dispatcher
  alias Station.DockingBay
  alias Station.FreighterLine
  alias Station.InspectionCrew
  alias Station.OpsPanel
  alias Station.Ship
  alias Station.Warehouse

  @refresh 1_000
  @voyager_url "https://voyager.swmansion.com"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh, :refresh)
    end

    url = Station.Booth.dock_url()

    socket
    |> assign(:page_title, "STATION OPS · VOYAGER STATION")
    |> assign(:previous, nil)
    |> assign(:dock_url, display_url(url))
    |> assign(:dock_qr, qr(url))
    |> assign(:voyager_url, display_url(@voyager_url))
    |> assign(:voyager_qr, qr(@voyager_url))
    |> refresh()
    |> ok()
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    stats = Warehouse.stats()
    fleet = Dispatcher.fleet()
    # Freighters dock on the same arm as visitors, ship the same way and count
    # the same: the television draws a station, and a ship is a ship on it.
    ships = ships() ++ FreighterLine.statuses()
    capacity = Application.fetch_env!(:station, :warehouse_capacity)
    full? = stats.stored >= capacity

    # Everything the screen says is in the snapshot: the station carries its
    # own figures, and the only fact about the room - who is docked - sits in
    # the corner of the scene. There is no dashboard row underneath any more.
    {scene, previous} = scene(ships, stats, fleet, capacity, full?, socket.assigns.previous)

    socket
    |> assign(:show_qr, OpsPanel.show_qr?())
    |> assign(:scene, scene)
    |> assign(:previous, previous)
  end

  # Drawn once at mount rather than cached: a television loads this page a
  # handful of times a day, and a stale QR code is the failure nobody notices
  # until somebody is standing there with a phone.
  defp qr(url) do
    url
    |> EQRCode.encode()
    |> EQRCode.svg(viewbox: true, color: "#0d1220", background_color: "#ffffff")
  end

  # The scheme is noise on a line somebody is going to type, and phones add it
  # back themselves.
  defp display_url(url) do
    url
    |> String.replace_prefix("https://", "")
    |> String.replace_prefix("http://", "")
    |> String.trim_trailing("/")
  end

  defp ships do
    for name <- DockingBay.list(),
        status = Ship.status(name),
        status != {:error, :gone},
        do: status
  end

  # One snapshot per second, and the deltas the scene animates from. On the
  # first tick every delta is zero, so a screen that has been up for an hour
  # does not open with an hour's worth of cargo in the air.
  defp scene(ships, stats, fleet, capacity, full?, previous) do
    delivered = Map.new(ships, &{&1.name, &1.delivered})

    lanes = max(InspectionCrew.size(), 1)

    # Berths are handed out in order of arrival and kept: a ship that moves is
    # a ship somebody loses track of, and the whole point of the screen is to
    # find your own. People take the column nearest the station, freighters
    # queue up behind them.
    scene_ships =
      for ship <- Enum.sort_by(ships, &{Map.get(&1, :freighter?, false), &1.berth}) do
        %{
          id: to_string(ship.name),
          label: to_string(ship.name),
          cargo: ship.cargo_type,
          delta: delta(previous && previous.delivered[ship.name], ship.delivered)
        }
      end

    payload = %{
      ships: scene_ships,
      haulers: fleet.haulers,
      haulerDelta: delta(previous && previous.collected, stats.collected),
      hauled: stats.collected,
      # Everything not yet on the shelf: the warehouse mailbox plus what the
      # crew has been handed and not yet checksummed. One number, wherever the
      # backlog happens to sit.
      waiting: stats.backlog,
      congested: stats.backlog >= Application.fetch_env!(:station, :congested_queue),
      memory: stats.memory,
      docked: length(ships),
      berths: DockingBay.capacity(),
      lanes: lanes,
      inspectedDelta: delta(previous && previous.inspected, stats.inspected),
      # One tile per container, by type and in the cargo colours. The hold is
      # ordered by type on purpose: the truth the tiles carry is what is on the
      # shelf, and drawing a FIFO the process never publishes would be a guess.
      hold: Map.merge(Map.new(Cargo.types(), &{&1, 0}), Warehouse.shelf()),
      # What the haulers took, per type, cumulative: the hook colours the
      # outgoing crates from the difference since its last tick.
      collected: Map.merge(Map.new(Cargo.types(), &{&1, 0}), Warehouse.collected()),
      capacity: capacity,
      full: full?
    }

    previous = %{delivered: delivered, collected: stats.collected, inspected: stats.inspected}

    {Jason.encode!(payload), previous}
  end

  # A box from StationArt as an inline style, so the panels sit in the windows
  # the art drew for them whatever size the television is.
  defp style(box), do: Enum.map_join(box, "; ", fn {k, v} -> "#{k}: #{v}" end)

  defp delta(nil, _current), do: 0
  defp delta(previous, current), do: max(current - previous, 0)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="tv crt relative flex h-screen w-screen flex-col gap-3 overflow-hidden bg-base-300 p-4">
        <header class="flex items-center justify-between gap-6">
          <div class="flex items-center gap-4">
            <Sprites.voyager_logo class="h-10" />
            <h1 class="font-pixel text-xl text-primary">STATION</h1>
          </div>
        </header>

        <div class={[
          "grid min-h-0 flex-1 gap-3",
          if(@show_qr, do: "grid-cols-[1fr_14rem]", else: "grid-cols-1")
        ]}>
          <div class="flex min-h-0 flex-col gap-3">
            <%!-- The scene. Every actor inside is created by the hook from the
                  snapshot on data-scene, so LiveView leaves the children alone. --%>
            <section
              id="station-scene"
              phx-hook="StationScene"
              phx-update="ignore"
              data-scene={@scene}
              class="scene pixel-panel min-h-0 flex-1"
            >
              <div class="scene-stars scene-stars-far"></div>
              <div class="scene-stars scene-stars-near"></div>

              <%!-- The station: Station.Warehouse drawn as the pipeline it is,
                    left to right. Every number and tile inside is written by
                    the hook from the snapshot - this whole section is behind
                    phx-update="ignore", so what the server renders here is
                    only the frame. --%>
              <div data-scene-station class="scene-station" style="left: 50%; top: 50%; width: 56%">
                <StationArt.hull class="scene-station-art" />

                <section
                  class="scene-stage"
                  data-stage="intake"
                  style={style(StationArt.window(:intake))}
                >
                  <h3>INTAKE</h3>
                  <p class="scene-stage-figure">
                    <b data-scene-waiting class="text-warning">0</b>
                    <span>waiting</span>
                  </p>
                </section>

                <section
                  class="scene-stage"
                  data-stage="inspection"
                  style={style(StationArt.window(:inspection))}
                >
                  <h3>INSPECTION</h3>
                  <div data-scene-lanes class="scene-lanes text-primary"></div>
                  <p class="scene-stage-figure">
                    <b data-scene-lane-count class="text-primary">1</b>
                    <span data-scene-lane-label>clerk</span>
                  </p>
                </section>

                <section
                  class="scene-stage scene-stage-hold"
                  data-stage="warehouse"
                  style={style(StationArt.window(:warehouse))}
                >
                  <h3>
                    WAREHOUSE
                    <span class="scene-stage-count">
                      <span data-scene-hold-count>0 / 0</span>
                      <span data-scene-memory class="text-primary">0 B</span>
                    </span>
                  </h3>
                  <div data-scene-hold class="scene-hold"></div>
                </section>

                <section
                  class="scene-stage"
                  data-stage="outbound"
                  style={style(StationArt.window(:outbound))}
                >
                  <h3>OUTBOUND</h3>
                  <p class="scene-stage-figure">
                    <b data-scene-hauled class="text-primary">0</b>
                    <span>hauled</span>
                  </p>
                </section>

                <%!-- The docking pads: invisible targets the hook flies crates
                      to. The rings themselves are in the art. --%>
                <span
                  data-scene-port="in"
                  class="scene-port text-primary"
                  style={style(StationArt.pad(:in))}
                >
                </span>
                <span
                  data-scene-port="out"
                  class="scene-port text-primary"
                  style={style(StationArt.pad(:out))}
                >
                </span>
              </div>

              <%!-- The one fact about the room rather than the warehouse. --%>
              <div data-scene-docked class="scene-badge">
                <span>DOCKED</span>
                <b data-scene-docked-count>0/0</b>
              </div>

              <div data-scene-actors class="absolute inset-0"></div>
            </section>
          </div>

          <div :if={@show_qr} id="tv-qr" class="flex min-h-0 flex-col gap-3">
            <%!-- The way in. It is on the television rather than only on the
                  desk because the queue behind the booth can read a screen from
                  the aisle, and that is where the next ship comes from. Ops can
                  hide the column when the booth wants the scene alone. --%>
            <section class="pixel-panel flex flex-col items-center gap-3 p-3 text-center">
              <div class="w-full bg-white p-2">
                {raw(@dock_qr)}
              </div>
              <div class="flex min-w-0 flex-col gap-2">
                <p class="font-pixel text-xs leading-relaxed text-primary">
                  SCAN TO<br />DOCK A SHIP
                </p>
                <p class="font-mono text-[0.6875rem] leading-tight text-base-content/60">
                  {@dock_url}
                </p>
              </div>
            </section>

            <section class="pixel-panel flex flex-col items-center gap-3 p-3 text-center">
              <div class="w-full bg-white p-2">
                {raw(@voyager_qr)}
              </div>
              <div class="flex min-w-0 flex-col gap-2">
                <p class="font-pixel text-xs leading-relaxed text-secondary">
                  CHECK OUR<br />WEBSITE
                </p>
                <p class="font-mono text-[0.6875rem] leading-tight text-base-content/60">
                  {@voyager_url}
                </p>
              </div>
            </section>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
