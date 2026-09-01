defmodule StationWeb.OpsLive do
  @moduledoc """
  The panel behind the counter.

  Two of these buttons are the demo: `INSPECTION CREW` drains the warehouse
  queue in front of the audience, and `DISPATCH EXTRA HAULERS` turns the memory
  trend around. The rest are the tools that keep a booth running for two days -
  remove a ship whose name got through the filter, restart the warehouse, reset
  the board in the morning.
  """

  use StationWeb, :live_view

  alias Station.Dispatcher
  alias Station.DockingBay
  alias Station.Events
  alias Station.InspectionCrew
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.OpsPanel
  alias Station.Warehouse

  @refresh 1_000
  @log_size 12

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    unless authorised?(token), do: raise(StationWeb.NotFound)

    if connected?(socket) do
      :timer.send_interval(@refresh, :refresh)
      Events.subscribe()
    end

    socket
    |> assign(:page_title, "OPS · STATION VOY-1")
    |> assign(:token, token)
    |> assign(:log, [])
    |> refresh()
    |> ok()
  end

  @impl true
  def handle_event("warehouse_mode", %{"mode" => mode}, socket) do
    OpsPanel.set_warehouse_mode(String.to_existing_atom(mode))
    {:noreply, refresh(socket)}
  end

  def handle_event("haulers", %{"factor" => factor}, socket) do
    OpsPanel.set_hauler_boost(String.to_integer(factor))
    {:noreply, refresh(socket)}
  end

  def handle_event("restart_warehouse", _params, socket) do
    OpsPanel.restart_warehouse()
    {:noreply, refresh(socket)}
  end

  def handle_event("reset_leaderboard", _params, socket) do
    OpsPanel.reset_leaderboard()
    {:noreply, refresh(socket)}
  end

  def handle_event("reset_station", _params, socket) do
    OpsPanel.reset_station()
    {:noreply, refresh(socket)}
  end

  def handle_event("remove_ship", %{"ship" => ship}, socket) do
    ship |> String.to_existing_atom() |> DockingBay.remove()
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  def handle_info({:station_event, event}, socket) do
    {:noreply, assign(socket, :log, Enum.take([event | socket.assigns.log], @log_size))}
  end

  defp refresh(socket) do
    socket
    |> assign(:settings, OpsPanel.settings())
    |> assign(:stats, Warehouse.stats())
    |> assign(:ships, DockingBay.list())
    |> assign(:fleet, Dispatcher.fleet())
    |> assign(:inspectors, InspectionCrew.size())
    |> assign(:run_queue, Metrics.get(:run_queue))
    |> assign(:processes, Metrics.get(:process_count))
    |> assign(:throttled, Metrics.get(:throttled))
    |> assign(:dropped, Metrics.get(:dropped))
    |> assign(:board_size, Leaderboard.size())
    |> assign(:total_containers, Leaderboard.total_containers())
    |> assign(:atoms, DockingBay.atom_budget())
  end

  defp authorised?(token) do
    Plug.Crypto.secure_compare(token, Application.fetch_env!(:station, :ops_token))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex min-h-screen w-full max-w-5xl flex-col gap-4 p-4">
        <header class="flex flex-wrap items-center justify-between gap-3">
          <h1 class="font-pixel text-base text-primary">STATION OPS</h1>
          <div class="flex flex-wrap gap-2 font-mono text-[11px] text-base-content/50">
            <span>{@processes} processes</span>
            <span>· run queue {@run_queue}</span>
            <span>· {@throttled} throttled</span>
            <span>· {@dropped} jettisoned</span>
            <span>· {@atoms.used}/{@atoms.budget} atoms</span>
          </div>
        </header>

        <section class="grid gap-2 sm:grid-cols-4">
          <.readout label="WH QUEUE" value={format_count(@stats.queue)} tone="text-warning" />
          <.readout label="WH MEMORY" value={format_bytes(@stats.memory)} tone="text-primary" />
          <.readout label="IN STATE" value={format_count(@stats.stored)} />
          <.readout
            label="LEADERBOARD"
            value={format_count(@total_containers)}
            hint={"#{@board_size} ships"}
            tone="text-success"
          />
        </section>

        <%!-- The two switches the whole demo turns on. --%>
        <section class="pixel-panel pixel-panel-accent flex flex-col gap-4 p-4">
          <div>
            <h2 class="font-pixel text-[10px] text-primary">WAREHOUSE MODE</h2>
            <p class="mt-1 font-mono text-[11px] text-base-content/50">
              Who runs the checksums: the warehouse process itself, or a pool it
              delegates to. Flip it while the queue is deep.
            </p>
            <div class="mt-3 grid gap-2 sm:grid-cols-2">
              <.ops_button
                active={@settings.warehouse_mode == :single_clerk}
                event="warehouse_mode"
                values={%{"mode" => "single_clerk"}}
                label="SINGLE CLERK"
                hint="one process does everything"
              />
              <.ops_button
                active={@settings.warehouse_mode == :inspection_crew}
                event="warehouse_mode"
                values={%{"mode" => "inspection_crew"}}
                label="INSPECTION CREW"
                hint={"#{@inspectors} workers on shift"}
              />
            </div>
          </div>

          <div>
            <h2 class="font-pixel text-[10px] text-primary">HAULERS</h2>
            <p class="mt-1 font-mono text-[11px] text-base-content/50">
              More consumers. Warehouse memory should start falling within about
              ten seconds - currently {@fleet.haulers} on duty.
            </p>
            <div class="mt-3 grid gap-2 sm:grid-cols-3">
              <.ops_button
                :for={factor <- Application.fetch_env!(:station, :hauler_boosts)}
                active={@settings.hauler_boost == factor}
                event="haulers"
                values={%{"factor" => to_string(factor)}}
                label={"x#{factor}"}
                hint={hauler_hint(factor)}
              />
            </div>
          </div>
        </section>

        <section class="pixel-panel flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-secondary">DOCKED SHIPS</h2>
          <ul class="flex flex-wrap gap-2">
            <li :for={ship <- @ships} class="flex items-center gap-2 border-2 border-base-300 p-2">
              <span class="font-mono text-[11px]">{ship}</span>
              <button
                type="button"
                phx-click="remove_ship"
                phx-value-ship={ship}
                data-confirm={"Remove #{ship} from the station?"}
                class="font-pixel text-[9px] text-error hover:underline"
              >
                REMOVE
              </button>
            </li>
            <li :if={@ships == []} class="font-mono text-[11px] text-base-content/40">
              nobody docked
            </li>
          </ul>
        </section>

        <section class="pixel-panel border-error/40 flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-error">DESTRUCTIVE</h2>
          <div class="grid gap-2 sm:grid-cols-3">
            <.ops_button
              event="restart_warehouse"
              values={%{}}
              label="RESTART WAREHOUSE"
              hint="cargo dies, ETS survives"
              confirm="Kill the warehouse process? Its supervisor restarts it and the leaderboard survives, but everything in its state is gone."
              tone="error"
            />
            <.ops_button
              event="reset_station"
              values={%{}}
              label="RESET STATION"
              hint="undock everyone, empty the shelves"
              confirm="Undock every ship and empty the warehouse?"
              tone="error"
            />
            <.ops_button
              event="reset_leaderboard"
              values={%{}}
              label="RESET LEADERBOARD"
              hint="clears ETS and the file"
              confirm="Wipe the leaderboard table and its snapshot on disk?"
              tone="error"
            />
          </div>
        </section>

        <section class="pixel-panel flex flex-col gap-2 p-4">
          <h2 class="font-pixel text-[10px] text-base-content/50">LOG</h2>
          <ul class="flex flex-col gap-1">
            <li :for={event <- @log} class={["font-mono text-[11px]", event_tone(event.level)]}>
              {event.text}
            </li>
            <li :if={@log == []} class="font-mono text-[11px] text-base-content/35">
              nothing yet
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :event, :string, required: true
  attr :values, :map, default: %{}
  attr :active, :boolean, default: false
  attr :confirm, :string, default: nil
  attr :tone, :string, default: "primary"

  defp ops_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-mode={@values["mode"]}
      phx-value-level={@values["level"]}
      phx-value-factor={@values["factor"]}
      data-confirm={@confirm}
      class={["pixel-button flex flex-col items-start gap-1 p-3 text-left", tone(@active, @tone)]}
    >
      <span class="font-pixel text-[10px]">{@label}</span>
      <span :if={@hint} class="font-mono text-[10px] opacity-70">{@hint}</span>
    </button>
    """
  end

  # Written out rather than interpolated: Tailwind reads these class names out of
  # the source, and a `bg-#{tone}` it cannot see is a class it does not build.
  defp tone(true, "error"), do: "bg-error text-error-content"
  defp tone(true, _), do: "bg-primary text-primary-content"
  defp tone(false, "error"), do: "bg-base-200 text-error"
  defp tone(false, _), do: "bg-base-200 text-base-content/70"

  defp hauler_hint(1), do: "baseline, too few on purpose"
  defp hauler_hint(factor), do: "#{factor} times the crew"

  defp event_tone(:error), do: "text-error"
  defp event_tone(:warning), do: "text-warning"
  defp event_tone(_), do: "text-base-content/65"
end
