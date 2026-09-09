defmodule StationWeb.OpsLive do
  @moduledoc """
  The traffic panel behind the counter.

  The knobs that get turned during a demo: how many simulated visitors are on
  duty and whether they make room for real ones, how many clerks inspect
  cargo, how many haulers drain it, whether the television shows its QR codes,
  and a way to empty the warehouse. Everything else the staff can flip still
  lives in `Station.OpsPanel` and a remote shell. A phone in a pocket beats a
  laptop with a shell open.
  """

  use StationWeb, :live_view

  alias Station.Dispatcher
  alias Station.DockingBay
  alias Station.FreighterLine
  alias Station.InspectionCrew
  alias Station.OpsPanel
  alias Station.Warehouse

  @refresh 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, :refresh)

    socket
    |> assign(:page_title, "TRAFFIC · VOYAGER STATION")
    |> assign(:levels, levels())
    |> assign(:count_form, to_form(%{}, as: :traffic))
    |> assign(:clerks_form, to_form(%{}, as: :clerks))
    |> assign(:haulers_form, to_form(%{}, as: :haulers))
    |> assign(:freighter_pace_form, to_form(%{}, as: :freighter_pace))
    |> assign(:hauler_pace_form, to_form(%{}, as: :hauler_pace))
    |> assign(:default_clerks, OpsPanel.default_clerks())
    |> assign(:baseline_haulers, Application.fetch_env!(:station, :haulers))
    |> assign(:hauler_boosts, Application.fetch_env!(:station, :hauler_boosts))
    |> refresh()
    |> ok()
  end

  @impl true
  def handle_event("level", %{"level" => level}, socket) do
    case Enum.find(levels(), fn {name, _count} -> to_string(name) == level end) do
      {name, _count} -> OpsPanel.set_traffic(name)
      nil -> :ok
    end

    {:noreply, refresh(socket)}
  end

  def handle_event("count", %{"traffic" => %{"count" => count}}, socket) do
    case Integer.parse(count) do
      {n, ""} when n >= 0 and n <= 99 -> OpsPanel.set_traffic(n)
      _ -> :ok
    end

    {:noreply, refresh(socket)}
  end

  def handle_event("yield", %{"yield" => yield}, socket) do
    OpsPanel.set_yield_to_visitors(yield == "true")
    {:noreply, refresh(socket)}
  end

  def handle_event("clear", _params, socket) do
    OpsPanel.set_traffic(0)
    {:noreply, refresh(socket)}
  end

  def handle_event("clear_warehouse", _params, socket) do
    OpsPanel.clear_warehouse()
    {:noreply, refresh(socket)}
  end

  def handle_event("clerks", %{"count" => count}, socket) do
    set_clerks(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("haulers", %{"count" => count}, socket) do
    set_haulers(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("haulers", %{"haulers" => %{"count" => count}}, socket) do
    set_haulers(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("freighter_pace", %{"freighter_pace" => %{"ms" => ms}}, socket) do
    set_interval(ms, &OpsPanel.set_freighter_interval/1)
    {:noreply, refresh(socket)}
  end

  def handle_event("hauler_pace", %{"hauler_pace" => %{"ms" => ms}}, socket) do
    set_interval(ms, &OpsPanel.set_hauler_interval/1)
    {:noreply, refresh(socket)}
  end

  def handle_event("qr", %{"show" => show}, socket) do
    OpsPanel.set_show_qr(show == "true")
    {:noreply, refresh(socket)}
  end

  def handle_event("clerks", %{"clerks" => %{"count" => count}}, socket) do
    set_clerks(count)
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    settings = OpsPanel.settings()
    fleet = Dispatcher.fleet()

    socket
    |> assign(:settings, settings)
    |> assign(:fleet, fleet)
    |> assign(:visitors, DockingBay.count())
    |> assign(:capacity, DockingBay.capacity())
    |> assign(:freighters, FreighterLine.list())
    |> assign(:stats, Warehouse.stats())
    |> assign(:clerks_on_shift, clerks_on_shift())
  end

  # What the warehouse is actually working with right now, as the scene draws it.
  defp clerks_on_shift do
    case OpsPanel.warehouse_mode() do
      :inspection_crew -> max(InspectionCrew.size(), 1)
      :single_clerk -> 1
    end
  end

  defp set_interval(ms, setter) do
    {min, max} = OpsPanel.interval_bounds()

    case Integer.parse(to_string(ms)) do
      {n, ""} when n >= min and n <= max -> setter.(n)
      _ -> :ok
    end
  end

  defp set_haulers(count) do
    max = OpsPanel.max_haulers()

    case Integer.parse(to_string(count)) do
      {n, ""} when n >= 0 and n <= max -> OpsPanel.set_haulers(n)
      _ -> :ok
    end
  end

  defp set_clerks(count) do
    max = OpsPanel.max_clerks()

    case Integer.parse(to_string(count)) do
      {n, ""} when n >= 1 and n <= max -> OpsPanel.set_clerks(n)
      _ -> :ok
    end
  end

  # Cheapest first, so the buttons read left to right as the aisle fills up.
  defp levels do
    OpsPanel.traffic_levels()
    |> Enum.sort_by(fn {_name, count} -> count end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex min-h-screen w-full max-w-xl select-none flex-col gap-4 px-4 py-6">
        <header class="flex items-center gap-4">
          <Sprites.voyager_logo class="h-8" />
          <h1 class="font-pixel text-lg text-primary">TRAFFIC</h1>
        </header>

        <section class="grid grid-cols-3 gap-2">
          <.readout
            label="VISITORS"
            value={"#{@visitors}/#{@capacity}"}
            tone="text-secondary"
          />
          <.readout
            label="FREIGHTERS"
            value={to_string(@fleet.freighters)}
            hint={freighter_hint(@settings, @fleet.freighters)}
            tone="text-primary"
          />
          <.readout
            label="QUEUE"
            value={format_count(@stats.backlog)}
            hint={
              if(@stats.inspection_queue > 0,
                do: "#{format_count(@stats.inspection_queue)} at the crew"
              )
            }
            tone={if(@stats.backlog > 0, do: "text-warning", else: "text-base-content")}
          />
        </section>

        <section class="pixel-panel pixel-panel-accent flex flex-col gap-4 p-4">
          <div>
            <h2 class="font-pixel text-[10px] text-primary">SIMULATED VISITORS</h2>
            <p class="mt-1 font-mono text-[11px] text-base-content/50">
              Robot ships that dock, ship cargo and refill like a person with a
              timer for a thumb. Turn them up when the aisle is empty and down
              as people arrive.
            </p>
            <div id="traffic-levels" class="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
              <button
                :for={{name, count} <- @levels}
                type="button"
                id={"traffic-#{name}"}
                phx-click="level"
                phx-value-level={name}
                class={[
                  "pixel-button flex flex-col items-start gap-1 p-3 text-left",
                  if(@settings.freighters == count,
                    do: "bg-primary text-primary-content",
                    else: "bg-base-200 text-base-content/70"
                  )
                ]}
              >
                <span class="font-pixel text-[10px]">{name |> to_string() |> String.upcase()}</span>
                <span class="font-mono text-[10px] opacity-70">{count} freighters</span>
              </button>
            </div>
          </div>

          <.form
            for={@count_form}
            id="traffic-count-form"
            phx-submit="count"
            class="flex items-end gap-2"
          >
            <label class="flex flex-1 flex-col gap-1">
              <span class="font-pixel text-[9px] text-base-content/50">EXACT NUMBER</span>
              <input
                type="number"
                name="traffic[count]"
                id="traffic-count"
                min="0"
                max="99"
                value={@settings.freighters}
                class="w-full border-2 border-base-300 bg-base-300 px-3 py-2 font-mono text-base text-base-content outline-none focus:border-primary"
              />
            </label>
            <button
              type="submit"
              class="pixel-button bg-base-200 px-4 py-3 font-pixel text-[10px] text-base-content/70"
            >
              SET
            </button>
          </.form>

          <.form
            for={@freighter_pace_form}
            id="freighter-pace-form"
            phx-submit="freighter_pace"
            class="flex items-end gap-2"
          >
            <label class="flex flex-1 flex-col gap-1">
              <span class="font-pixel text-[9px] text-base-content/50">
                MS BETWEEN CONTAINERS, PER FREIGHTER
              </span>
              <input
                type="number"
                name="freighter_pace[ms]"
                id="freighter-pace"
                min={elem(OpsPanel.interval_bounds(), 0)}
                max={elem(OpsPanel.interval_bounds(), 1)}
                step="50"
                value={@settings.freighter_interval_ms}
                class="w-full border-2 border-base-300 bg-base-300 px-3 py-2 font-mono text-base text-base-content outline-none focus:border-primary"
              />
            </label>
            <button
              type="submit"
              class="pixel-button bg-base-200 px-4 py-3 font-pixel text-[10px] text-base-content/70"
            >
              SET
            </button>
          </.form>
          <p class="font-mono text-[11px] text-base-content/50">
            Lower is heavier: the count is the load, this is its other half. Takes effect on each freighter's next container.
          </p>
        </section>

        <section class="pixel-panel flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-secondary">MAKE ROOM FOR PEOPLE</h2>
          <p class="font-mono text-[11px] text-base-content/50">
            With yield on, every visitor who docks sends one freighter home, so
            the screen holds a steady crowd whoever is in it. Off, freighters
            stay and visitors come on top.
          </p>
          <div class="grid grid-cols-2 gap-2">
            <button
              type="button"
              id="yield-on"
              phx-click="yield"
              phx-value-yield="true"
              class={[
                "pixel-button p-3 font-pixel text-[10px]",
                if(@settings.yield_to_visitors,
                  do: "bg-secondary text-secondary-content",
                  else: "bg-base-200 text-base-content/70"
                )
              ]}
            >
              YIELD TO VISITORS
            </button>
            <button
              type="button"
              id="yield-off"
              phx-click="yield"
              phx-value-yield="false"
              class={[
                "pixel-button p-3 font-pixel text-[10px]",
                if(@settings.yield_to_visitors,
                  do: "bg-base-200 text-base-content/70",
                  else: "bg-secondary text-secondary-content"
                )
              ]}
            >
              STAY
            </button>
          </div>

          <button
            type="button"
            id="clear-freighters"
            phx-click="clear"
            data-confirm="Send every freighter home now? Traffic goes to OFF."
            class="pixel-panel pixel-panel-danger flex items-center justify-center p-3 font-pixel text-[10px] text-error"
          >
            UNDOCK ALL FREIGHTERS NOW
          </button>
        </section>

        <section class="pixel-panel pixel-panel-accent flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-primary">INSPECTION</h2>
          <p class="font-mono text-[11px] text-base-content/50">
            Who runs the checksums. One clerk is the warehouse process itself -
            the bottleneck. More is a crew of clerks, the warehouse only
            routing, the queue draining while everyone watches. Currently {@clerks_on_shift} on shift.
          </p>
          <div class="grid grid-cols-2 gap-2">
            <button
              type="button"
              id="clerks-one"
              phx-click="clerks"
              phx-value-count="1"
              class={[
                "pixel-button flex flex-col items-start gap-1 p-3 text-left",
                if(@clerks_on_shift == 1,
                  do: "bg-primary text-primary-content",
                  else: "bg-base-200 text-base-content/70"
                )
              ]}
            >
              <span class="font-pixel text-[10px]">SINGLE CLERK</span>
              <span class="font-mono text-[10px] opacity-70">one process does everything</span>
            </button>
            <button
              type="button"
              id="clerks-default"
              phx-click="clerks"
              phx-value-count={@default_clerks}
              class={[
                "pixel-button flex flex-col items-start gap-1 p-3 text-left",
                if(@clerks_on_shift == @default_clerks,
                  do: "bg-primary text-primary-content",
                  else: "bg-base-200 text-base-content/70"
                )
              ]}
            >
              <span class="font-pixel text-[10px]">CREW OF {@default_clerks}</span>
              <span class="font-mono text-[10px] opacity-70">one per scheduler</span>
            </button>
          </div>

          <.form for={@clerks_form} id="clerks-form" phx-submit="clerks" class="flex items-end gap-2">
            <label class="flex flex-1 flex-col gap-1">
              <span class="font-pixel text-[9px] text-base-content/50">EXACT NUMBER OF CLERKS</span>
              <input
                type="number"
                name="clerks[count]"
                id="clerks-count"
                min="1"
                max={OpsPanel.max_clerks()}
                value={@clerks_on_shift}
                class="w-full border-2 border-base-300 bg-base-300 px-3 py-2 font-mono text-base text-base-content outline-none focus:border-primary"
              />
            </label>
            <button
              type="submit"
              class="pixel-button bg-base-200 px-4 py-3 font-pixel text-[10px] text-base-content/70"
            >
              SET
            </button>
          </.form>
        </section>

        <section class="pixel-panel flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-secondary">OUTBOUND</h2>
          <p class="font-mono text-[11px] text-base-content/50">
            Haulers take cargo off the shelf. Too few on purpose at the baseline,
            so the warehouse creeps up; send more and its memory turns around
            while everyone watches. Currently {@fleet.haulers} on duty.
          </p>
          <div class="grid grid-cols-3 gap-2">
            <button
              :for={factor <- @hauler_boosts}
              type="button"
              id={"haulers-x#{factor}"}
              phx-click="haulers"
              phx-value-count={@baseline_haulers * factor}
              class={[
                "pixel-button flex flex-col items-start gap-1 p-3 text-left",
                if(@settings.haulers == @baseline_haulers * factor,
                  do: "bg-secondary text-secondary-content",
                  else: "bg-base-200 text-base-content/70"
                )
              ]}
            >
              <span class="font-pixel text-[10px]">x{factor}</span>
              <span class="font-mono text-[10px] opacity-70">
                {@baseline_haulers * factor} haulers
              </span>
            </button>
          </div>

          <.form
            for={@haulers_form}
            id="haulers-form"
            phx-submit="haulers"
            class="flex items-end gap-2"
          >
            <label class="flex flex-1 flex-col gap-1">
              <span class="font-pixel text-[9px] text-base-content/50">EXACT NUMBER OF HAULERS</span>
              <input
                type="number"
                name="haulers[count]"
                id="haulers-count"
                min="0"
                max={OpsPanel.max_haulers()}
                value={@settings.haulers}
                class="w-full border-2 border-base-300 bg-base-300 px-3 py-2 font-mono text-base text-base-content outline-none focus:border-primary"
              />
            </label>
            <button
              type="submit"
              class="pixel-button bg-base-200 px-4 py-3 font-pixel text-[10px] text-base-content/70"
            >
              SET
            </button>
          </.form>

          <.form
            for={@hauler_pace_form}
            id="hauler-pace-form"
            phx-submit="hauler_pace"
            class="flex items-end gap-2"
          >
            <label class="flex flex-1 flex-col gap-1">
              <span class="font-pixel text-[9px] text-base-content/50">
                MS BETWEEN PICKUPS, PER HAULER
              </span>
              <input
                type="number"
                name="hauler_pace[ms]"
                id="hauler-pace"
                min={elem(OpsPanel.interval_bounds(), 0)}
                max={elem(OpsPanel.interval_bounds(), 1)}
                step="50"
                value={@settings.hauler_interval_ms}
                class="w-full border-2 border-base-300 bg-base-300 px-3 py-2 font-mono text-base text-base-content outline-none focus:border-primary"
              />
            </label>
            <button
              type="submit"
              class="pixel-button bg-base-200 px-4 py-3 font-pixel text-[10px] text-base-content/70"
            >
              SET
            </button>
          </.form>
          <p class="font-mono text-[11px] text-base-content/50">
            Lower drains faster: each hauler waits this long, give or take, then takes a batch. Takes effect on its next trip.
          </p>
        </section>

        <section class="pixel-panel flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-base-content/50">TELEVISION</h2>
          <div class="grid grid-cols-2 gap-2">
            <button
              type="button"
              id="qr-on"
              phx-click="qr"
              phx-value-show="true"
              class={[
                "pixel-button p-3 font-pixel text-[10px]",
                if(@settings.show_qr,
                  do: "bg-base-content text-base-300",
                  else: "bg-base-200 text-base-content/70"
                )
              ]}
            >
              SHOW QR CODES
            </button>
            <button
              type="button"
              id="qr-off"
              phx-click="qr"
              phx-value-show="false"
              class={[
                "pixel-button p-3 font-pixel text-[10px]",
                if(@settings.show_qr,
                  do: "bg-base-200 text-base-content/70",
                  else: "bg-base-content text-base-300"
                )
              ]}
            >
              HIDE QR CODES
            </button>
          </div>
        </section>

        <section class="pixel-panel flex flex-col gap-3 p-4">
          <h2 class="font-pixel text-[10px] text-secondary">WAREHOUSE</h2>
          <p class="font-mono text-[11px] text-base-content/50">
            Empties the shelf, the warehouse mailbox and every clerk's mailbox - {format_count(
              @stats.stored
            )} stored, {format_count(@stats.backlog)} waiting.
            The leaderboard keeps every delivery.
          </p>
          <button
            type="button"
            id="clear-warehouse"
            phx-click="clear_warehouse"
            data-confirm="Empty the warehouse and drop everything waiting in its queue and the clerks' queues?"
            class="pixel-panel pixel-panel-danger flex items-center justify-center p-3 font-pixel text-[10px] text-error"
          >
            CLEAR WAREHOUSE AND QUEUES
          </button>
        </section>

        <section class="pixel-panel flex flex-col gap-2 p-4">
          <h2 class="font-pixel text-[10px] text-base-content/50">ON DUTY</h2>
          <ul id="freighter-list" class="flex flex-wrap gap-2">
            <li
              :for={name <- @freighters}
              class="border-2 border-base-300 px-2 py-1 font-mono text-[11px]"
            >
              {name}
            </li>
            <li :if={@freighters == []} class="font-mono text-[11px] text-base-content/35">
              no freighters on duty
            </li>
          </ul>
        </section>

        <footer class="mt-auto flex items-center justify-between gap-4 pt-4 font-mono text-[11px] text-base-content/45">
          <span>everything else: <code>bin/station remote</code></span>
          <.link navigate={~p"/tv"} class="underline hover:text-primary">Station Ops screen</.link>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  defp freighter_hint(%{yield_to_visitors: true, freighters: wanted}, on_duty)
       when on_duty < wanted,
       do: "#{wanted} asked, #{wanted - on_duty} yielded"

  defp freighter_hint(_settings, _on_duty), do: nil
end
