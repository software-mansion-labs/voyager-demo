defmodule StationWeb.StationOpsLive do
  @moduledoc """
  The television. The narrative half of the booth.

  Everything on this screen is also true on the laptop next to it, which is the
  whole trick: the visitor watches the station here and then confirms it in
  Voyager two feet to the left. The scene is deliberately literal - the queue
  in front of the warehouse is `message_queue_len`, the crates stacked inside
  it are the process state, the leaderboard is a dump of the ETS table.
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
  @queue_crates 28
  @shelf_slots 168

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh, :refresh)
      Events.subscribe()
    end

    socket
    |> assign(:page_title, "STATION OPS · STATION VOY-1")
    |> assign(:log, [])
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

    socket
    |> assign(:stats, stats)
    |> assign(:ships, ships())
    |> assign(:capacity, DockingBay.capacity())
    |> assign(:board, Leaderboard.top(9))
    |> assign(:board_size, Leaderboard.size())
    |> assign(:fleet, Dispatcher.fleet())
    |> assign(:inspectors, InspectionCrew.size())
    |> assign(:settings, OpsPanel.settings())
    |> assign(:queue_crates, min(stats.queue, @queue_crates))
    |> assign(:shelf_slots, @shelf_slots)
    |> assign(:congested?, stats.queue >= @queue_crates)
    |> assign(:processes, Metrics.get(:process_count))
    |> assign(:atoms, DockingBay.atom_budget())
    |> assign(:warehouse_capacity, Application.fetch_env!(:station, :warehouse_capacity))
    |> then(&assign(&1, :shelved, shelved(stats.stored, &1.assigns.warehouse_capacity)))
  end

  # The shelves are the warehouse's process state drawn as boxes. Whole crates
  # only - a half crate would be a progress bar wearing a costume.
  defp shelved(stored, capacity) do
    stored
    |> Kernel./(max(capacity, 1))
    |> min(1.0)
    |> Kernel.*(@shelf_slots)
    |> round()
  end

  defp ships do
    for name <- DockingBay.list(),
        status = Ship.status(name),
        status != {:error, :gone},
        do: status
  end

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
              {@processes} PROCESSES
            </span>
          </div>
        </header>

        <div class="grid min-h-0 flex-1 grid-cols-[1fr_1.4fr_1fr] gap-3">
          <%!-- Docking bays: one sprite per person standing in the room. --%>
          <section class="pixel-panel flex min-h-0 flex-col gap-2 p-3">
            <div class="flex items-baseline justify-between">
              <h2 class="font-pixel text-[10px] text-secondary">DOCKING BAY</h2>
              <span class="font-mono text-[11px] text-base-content/45">
                {length(@ships)}/{@capacity}
              </span>
            </div>

            <div class="flex items-center justify-between">
              <Sprites.dock :for={_ <- 1..5} class="size-8 text-base-content/25" />
            </div>

            <ul class="grid min-h-0 flex-1 grid-cols-2 content-start gap-2 overflow-hidden">
              <li
                :for={ship <- @ships}
                class="flex items-center gap-2 border-2 border-base-300 bg-base-100 p-2"
              >
                <Sprites.ship class={[
                  "size-6 shrink-0 animate-bob",
                  Sprites.cargo_color(ship.cargo_type)
                ]} />
                <div class="min-w-0">
                  <p class="truncate font-mono text-[11px] text-base-content/80">{ship.name}</p>
                  <p class="font-mono text-[10px] text-base-content/40">
                    {ship.hold} left · {ship.delivered} sent
                  </p>
                </div>
              </li>

              <li
                :if={@ships == []}
                class="col-span-2 border-2 border-dashed border-base-300 p-4 text-center font-mono text-[11px] text-base-content/35"
              >
                No visitors docked. The automatic fleet is holding the station.
              </li>
            </ul>
          </section>

          <%!-- The warehouse, its queue and what it is holding. --%>
          <section class="pixel-panel flex min-h-0 flex-col gap-3 p-3">
            <div class="flex items-baseline justify-between">
              <h2 class="font-pixel text-[10px] text-primary">WAREHOUSE</h2>
              <span class="font-mono text-[11px] text-base-content/45">
                {@inspectors} inspectors · {@fleet.freighters} freighters · {@fleet.haulers} haulers
              </span>
            </div>

            <div class="flex min-h-0 flex-1 flex-col justify-between gap-4">
              <div class="flex items-center gap-3">
                <div class={["conveyor h-12 flex-1", @congested? && "conveyor-stalled"]}></div>
                <Sprites.warehouse class={[
                  "size-28 shrink-0",
                  if(@congested?, do: "text-error animate-blink", else: "text-primary")
                ]} />
              </div>

              <div class="flex flex-col gap-2">
                <div class="flex items-baseline justify-between">
                  <span class="font-pixel text-[9px] text-base-content/50">MESSAGE QUEUE</span>
                  <span class={[
                    "font-pixel text-lg",
                    if(@congested?, do: "text-error", else: "text-base-content")
                  ]}>
                    {format_count(@stats.queue)}
                  </span>
                </div>

                <%!-- One crate per waiting message, up to the width of the panel.
                    Past that the number does the talking. --%>
                <div class="mt-2 flex h-8 items-end gap-[3px]">
                  <Sprites.crate_small
                    :for={_ <- 1..max(@queue_crates, 1)//1}
                    :if={@queue_crates > 0}
                    class="size-7 text-warning"
                  />
                  <span :if={@queue_crates == 0} class="font-mono text-xs text-base-content/35">
                    nothing waiting - the clerk is keeping up
                  </span>
                </div>
              </div>

              <div class="flex flex-col gap-2">
                <div class="flex items-baseline justify-between">
                  <span class="font-pixel text-[9px] text-base-content/50">SHELVES</span>
                  <span class="font-mono text-[11px] text-base-content/45">
                    {format_count(@stats.stored)} containers in process state
                  </span>
                </div>
                <div class="grid grid-cols-24 gap-[3px] content-start">
                  <Sprites.crate_small
                    :for={slot <- 1..@shelf_slots}
                    class={[
                      "w-full",
                      if(slot <= @shelved, do: "text-primary", else: "text-base-content/10")
                    ]}
                  />
                </div>
              </div>

              <div class="grid grid-cols-2 gap-2">
                <.readout
                  label="IN STATE"
                  value={format_count(@stats.stored)}
                  hint={"of #{format_count(@warehouse_capacity)} capacity"}
                  tone="text-primary"
                />
                <.readout
                  label="PROCESS MEMORY"
                  value={format_bytes(@stats.memory)}
                  hint={"#{format_count(@stats.accepted)} accepted · #{format_count(@stats.collected)} hauled away"}
                  tone="text-primary"
                />
              </div>
            </div>
          </section>

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
