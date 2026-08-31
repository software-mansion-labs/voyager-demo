defmodule StationWeb.StationOpsLive do
  @moduledoc """
  The television. The narrative half of the booth.

  It is a scene, not a dashboard with pictures on it. Visitors' ships fly in and
  dock along the left arm, containers cross the gap to the station one at a
  time, the bay window fills with what the warehouse is holding, and haulers on
  the right pull cargo back out.

  None of it is decoration. Every crate in flight is a delivery that actually
  happened in the last second, the pile outside the bay door is
  `message_queue_len`, and the bay window is process state. The visitor watches
  it here and then confirms every bit of it in Voyager, two feet to the left.

  The one honest compromise is the cap: at a busy moment the station moves a few
  hundred containers a second and no television can draw that, so past the cap
  the counters underneath carry the number.
  """

  use StationWeb, :live_view

  alias Station.Dispatcher
  alias Station.DockingBay
  alias Station.Events
  alias Station.InspectionCrew
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.OpsPanel
  alias Station.Ship
  alias Station.Warehouse

  @refresh 1_000
  @log_size 7
  @queue_crates 16

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh, :refresh)
      Events.subscribe()
    end

    socket
    |> assign(:log, [])
    |> assign(:page_title, "STATION OPS · STATION VOY-1")
    |> assign(:previous, nil)
    |> refresh()
    |> ok()
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  def handle_info({:station_event, event}, socket) do
    {:noreply, assign(socket, :log, log(socket.assigns.log, event))}
  end

  # The same line arriving twice in a row becomes one line with a counter. A
  # television that scrolls the same sentence eight times reads as broken.
  defp log([%{text: text} = last | rest], %{text: text}) do
    [%{last | repeats: last.repeats + 1} | rest]
  end

  defp log(entries, event) do
    Enum.take([Map.put(event, :repeats, 1) | entries], @log_size)
  end

  defp refresh(socket) do
    stats = Warehouse.stats()
    fleet = Dispatcher.fleet()
    ships = ships()
    capacity = Application.fetch_env!(:station, :warehouse_capacity)
    congested? = stats.queue >= @queue_crates

    {scene, previous} = scene(ships, stats, fleet, capacity, congested?, socket.assigns.previous)

    socket
    |> assign(:stats, stats)
    |> assign(:fleet, fleet)
    |> assign(:ships, ships)
    |> assign(:congested?, congested?)
    |> assign(:capacity, DockingBay.capacity())
    |> assign(:warehouse_capacity, capacity)
    |> assign(:board, Leaderboard.top(12))
    |> assign(:board_size, Leaderboard.size())
    |> assign(:inspectors, InspectionCrew.size())
    |> assign(:settings, OpsPanel.settings())
    |> assign(:processes, Metrics.get(:process_count))
    |> assign(:atoms, DockingBay.atom_budget())
    |> assign(:scene, scene)
    |> assign(:previous, previous)
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
  defp scene(ships, stats, fleet, capacity, congested?, previous) do
    delivered = Map.new(ships, &{&1.name, &1.delivered})

    # Sorted by the board, because the scene draws the ranking: whoever has
    # moved the most cargo takes the berth nearest the station.
    scene_ships =
      for ship <- Enum.sort_by(ships, & &1.delivered, :desc) do
        %{
          id: to_string(ship.name),
          label: to_string(ship.name),
          cargo: ship.cargo_type,
          delta: delta(previous && previous.delivered[ship.name], ship.delivered)
        }
      end

    visitor_delta = scene_ships |> Enum.map(& &1.delta) |> Enum.sum()
    accepted_delta = delta(previous && previous.accepted, stats.accepted)

    payload = %{
      ships: scene_ships,
      haulers: fleet.haulers,
      freighters: fleet.freighters,
      haulerDelta: delta(previous && previous.collected, stats.collected),
      fleetDelta: max(accepted_delta - visitor_delta, 0),
      queue: stats.queue,
      queueCrates: min(stats.queue, @queue_crates),
      stored: safe_ratio(stats.stored, capacity),
      congested: congested?
    }

    previous = %{delivered: delivered, accepted: stats.accepted, collected: stats.collected}

    {Jason.encode!(payload), previous}
  end

  defp delta(nil, _current), do: 0
  defp delta(previous, current), do: max(current - previous, 0)

  defp safe_ratio(_value, 0), do: 0.0
  defp safe_ratio(value, max), do: Float.round(min(value / max, 1.0), 4)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="crt relative flex h-screen w-screen flex-col gap-3 overflow-hidden bg-base-300 p-4">
        <header class="flex items-center justify-between gap-6">
          <div class="flex items-center gap-3">
            <Sprites.warehouse class="size-10 text-primary" />
            <h1 class="font-pixel text-xl text-primary">STATION VOY-1</h1>
          </div>

          <div class="flex items-center gap-2 font-pixel text-[10px]">
            <span class={[
              "border-2 px-3 py-2",
              if(@settings.warehouse_mode == :single_clerk,
                do: "border-warning text-warning",
                else: "border-success text-success"
              )
            ]}>
              {@settings.warehouse_mode |> to_string() |> String.upcase() |> String.replace("_", " ")}
            </span>
            <span class="border-2 border-secondary px-3 py-2 text-secondary">
              {@settings.traffic |> to_string() |> String.upcase() |> String.replace("_", " ")}
            </span>
            <span class="border-2 border-base-content/20 px-3 py-2 text-base-content/60">
              {@inspectors} INSPECTORS
            </span>
            <span class="border-2 border-base-content/20 px-3 py-2 text-base-content/60">
              {format_count(@processes)} PROCESSES
            </span>
          </div>
        </header>

        <div class="grid min-h-0 flex-1 grid-cols-[1fr_20rem] gap-3">
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

              <span class="absolute left-3 top-3 font-pixel text-[10px] text-secondary">
                ARRIVALS
              </span>
              <span class="absolute right-3 top-3 font-pixel text-[10px] text-success">
                OUTBOUND
              </span>

              <%!-- The station itself, and the bay window the hook fills with
                    whatever the warehouse is holding. --%>
              <%!-- The ports light up as cargo lands, so the eye is pulled to
                    where the work is happening rather than to the counters. --%>
              <span data-scene-port="in" class="scene-port text-primary" style="left: 28%; top: 50%">
              </span>
              <span data-scene-port="out" class="scene-port text-success" style="left: 72%; top: 50%">
              </span>

              <div class="scene-actor" style="left: 50%; top: 50%; width: 48%">
                <Sprites.station_hub class="w-full text-primary" />
                <div
                  data-scene-bay
                  class="scene-bay text-primary"
                  style="left: 30.5%; top: 39%; width: 39%; height: 32%; grid-template-columns: repeat(16, 1fr); grid-auto-rows: 1fr"
                >
                </div>
              </div>

              <%!-- The pile outside the bay door: message_queue_len, drawn as
                    the queue it is. Both the crates and the caption belong to
                    the hook - everything in here is behind phx-update="ignore",
                    so anything the server rendered would freeze at mount. --%>
              <div class="absolute bottom-4 left-1/2 flex w-1/2 -translate-x-1/2 flex-col items-center gap-2">
                <div
                  data-scene-queue
                  class="flex min-h-[1.75rem] w-full flex-wrap items-end justify-center gap-[3px] text-warning"
                >
                </div>
                <p data-scene-queue-label class="font-pixel text-sm text-base-content/60"></p>
              </div>

              <div data-scene-actors class="absolute inset-0"></div>
            </section>

            <section class="grid grid-cols-5 gap-2">
              <.readout
                label="DOCKED"
                value={"#{length(@ships)}/#{@capacity}"}
                tone="text-secondary"
              />
              <.readout
                label="WH QUEUE"
                value={format_count(@stats.queue)}
                tone={if(@congested?, do: "text-error", else: "text-base-content")}
              />
              <.readout
                label="IN STATE"
                value={format_count(@stats.stored)}
                hint={"of #{format_count(@warehouse_capacity)}"}
                tone="text-primary"
              />
              <.readout
                label="WH MEMORY"
                value={format_bytes(@stats.memory)}
                hint={"#{format_count(@stats.dropped)} jettisoned"}
                tone="text-primary"
              />
              <.readout
                label="HAULED AWAY"
                value={format_count(@stats.collected)}
                hint={"#{@fleet.haulers} haulers · #{@fleet.freighters} freighters"}
                tone="text-success"
              />
            </section>
          </div>

          <%!-- The leaderboard, styled as what it is: a dump of an ETS table. --%>
          <section class="pixel-panel flex min-h-0 flex-col gap-2 p-3">
            <div class="flex items-baseline justify-between">
              <h2 class="font-pixel text-[10px] text-success">:station_leaderboard</h2>
              <span class="font-mono text-[11px] text-base-content/45">{@board_size} rows</span>
            </div>

            <table class="w-full table-fixed font-mono text-[11px]">
              <colgroup>
                <col class="w-[52%]" />
                <col class="w-[22%]" />
                <col class="w-[15%]" />
                <col class="w-[11%]" />
              </colgroup>
              <thead class="text-base-content/40">
                <tr class="border-b-2 border-base-300">
                  <th class="py-1 text-left font-normal">ship</th>
                  <th class="py-1 text-left font-normal">cargo</th>
                  <th class="py-1 text-right font-normal">boxes</th>
                  <th class="py-1 text-right font-normal">last</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{row, index} <- Enum.with_index(@board, 1)}
                  class="border-b border-base-300/60"
                >
                  <td class="truncate py-1 pr-2 text-base-content/80">
                    <span class="text-base-content/35">{index}.</span> {row.ship}
                  </td>
                  <td class={["truncate py-1 pr-2", Sprites.cargo_color(row.cargo)]}>{row.cargo}</td>
                  <td class="py-1 text-right text-primary">{format_count(row.containers)}</td>
                  <td class="py-1 text-right text-base-content/40">
                    {format_ago(row.last_delivery)}
                  </td>
                </tr>
                <tr :if={@board == []}>
                  <td colspan="4" class="py-4 text-center text-base-content/35">
                    no deliveries yet - the board only counts visitors
                  </td>
                </tr>
              </tbody>
            </table>

            <p class="mt-auto font-mono text-[10px] leading-relaxed text-base-content/40">
              Process state dies with the process. This table survives it, and its
              snapshot on disk survives the node. Three levels, one story.
            </p>
          </section>
        </div>

        <footer class="pixel-panel flex h-16 items-center gap-4 overflow-hidden p-3">
          <span class="font-pixel text-[9px] text-base-content/50">LOG</span>
          <ul class="flex min-w-0 flex-1 flex-col justify-center gap-[2px]">
            <li
              :for={event <- Enum.take(@log, 3)}
              class={["truncate font-mono text-[11px]", event_tone(event.level)]}
            >
              {event.text}<span :if={event.repeats > 1} class="opacity-60">&nbsp;x{event.repeats}</span>
            </li>
            <li :if={@log == []} class="font-mono text-[11px] text-base-content/35">
              station nominal
            </li>
          </ul>
          <span class="shrink-0 font-mono text-[11px] text-base-content/40">
            {@atoms.used} {if @atoms.used == 1, do: "atom", else: "atoms"} minted · never freed
          </span>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  defp event_tone(:error), do: "text-error"
  defp event_tone(:warning), do: "text-warning"
  defp event_tone(_), do: "text-base-content/65"
end
