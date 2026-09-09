defmodule StationWeb.OpsLive do
  @moduledoc """
  The panel behind the counter.

  Top to bottom, in the order the staff need it during a demo: who is on the
  screen right now and a way to send any of them home; the simulated visitors
  and their pace; the clerks who inspect and the haulers who drain; the
  warehouse's emergency handle; the television. Everything else the staff can
  flip still lives in `Station.OpsPanel` and a remote shell. A phone in a pocket
  beats a laptop with a shell open.
  """

  use StationWeb, :live_view

  alias Station.Dispatcher
  alias Station.DockingBay
  alias Station.FreighterLine
  alias Station.Hangar
  alias Station.InspectionCrew
  alias Station.OpsPanel
  alias Station.Ship
  alias Station.ShipNames
  alias Station.Warehouse

  @refresh 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, :refresh)

    socket
    |> assign(:page_title, "OPS · VOYAGER STATION")
    |> assign(:levels, levels())
    |> assign(:count_form, to_form(%{}, as: :traffic))
    |> assign(:clerks_form, to_form(%{}, as: :clerks))
    |> assign(:haulers_form, to_form(%{}, as: :haulers))
    |> assign(:freighter_pace_form, to_form(%{}, as: :freighter_pace))
    |> assign(:hauler_pace_form, to_form(%{}, as: :hauler_pace))
    |> assign(:default_clerks, OpsPanel.default_clerks())
    |> assign(:baseline_haulers, Application.fetch_env!(:station, :haulers))
    |> assign(:hauler_boosts, Application.fetch_env!(:station, :hauler_boosts))
    |> assign(:interval_bounds, OpsPanel.interval_bounds())
    |> refresh()
    |> ok()
  end

  # --- who is docked ---------------------------------------------------------

  # The slug comes off a button we rendered from a docked ship, but it is still
  # input from a browser: only a name from the pool ever becomes an atom.
  @impl true
  def handle_event("undock", %{"ship" => slug}, socket) do
    if slug in ShipNames.pool(), do: DockingBay.remove(ShipNames.to_process_name(slug))
    {:noreply, refresh(socket)}
  end

  def handle_event("undock_visitors", _params, socket) do
    OpsPanel.undock_visitors()
    {:noreply, refresh(socket)}
  end

  def handle_event("clear", _params, socket) do
    OpsPanel.set_traffic(0)
    {:noreply, refresh(socket)}
  end

  def handle_event("undock_everyone", _params, socket) do
    OpsPanel.set_traffic(0)
    OpsPanel.undock_visitors()
    {:noreply, refresh(socket)}
  end

  # --- simulated visitors ----------------------------------------------------

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

  def handle_event("freighter_pace", %{"freighter_pace" => %{"ms" => ms}}, socket) do
    set_interval(ms, &OpsPanel.set_freighter_interval/1)
    {:noreply, refresh(socket)}
  end

  def handle_event("yield", %{"yield" => yield}, socket) do
    OpsPanel.set_yield_to_visitors(yield == "true")
    {:noreply, refresh(socket)}
  end

  # --- inspection and haulers ------------------------------------------------

  def handle_event("clerks", %{"clerks" => %{"count" => count}}, socket) do
    set_clerks(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("clerks", %{"count" => count}, socket) do
    set_clerks(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("haulers", %{"haulers" => %{"count" => count}}, socket) do
    set_haulers(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("haulers", %{"count" => count}, socket) do
    set_haulers(count)
    {:noreply, refresh(socket)}
  end

  def handle_event("hauler_pace", %{"hauler_pace" => %{"ms" => ms}}, socket) do
    set_interval(ms, &OpsPanel.set_hauler_interval/1)
    {:noreply, refresh(socket)}
  end

  # --- warehouse and television ----------------------------------------------

  def handle_event("clear_warehouse", _params, socket) do
    OpsPanel.clear_warehouse()
    {:noreply, refresh(socket)}
  end

  def handle_event("qr", %{"show" => show}, socket) do
    OpsPanel.set_show_qr(show == "true")
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
    |> assign(:ships, ships())
    |> assign(:parked, Hangar.count())
    |> assign(:freighters, FreighterLine.list())
    |> assign(:stats, Warehouse.stats())
    |> assign(:clerks_on_shift, max(InspectionCrew.size(), 1))
  end

  # Every visitor's ship on the screen, oldest first, as its snapshot says.
  defp ships do
    DockingBay.list()
    |> Enum.map(&Ship.status/1)
    |> Enum.reject(&match?({:error, :gone}, &1))
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
          <h1 class="font-pixel text-lg text-primary">STATION OPS</h1>
        </header>

        <section class="grid grid-cols-3 gap-2">
          <.readout
            label="VISITORS"
            value={"#{@visitors}/#{@capacity}"}
            hint={if(@parked > 0, do: "#{@parked} in the hangar")}
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
                do: "#{format_count(@stats.inspection_queue)} at the clerks"
              )
            }
            tone={if(@stats.backlog > 0, do: "text-warning", else: "text-base-content")}
          />
        </section>

        <%!-- Who is on the screen, and the way to send any of them home. First,
              because it is the section somebody reaches for in a hurry. --%>
        <.panel title="DOCKED" tone="text-secondary">
          <:blurb>
            Everyone on the screen. UNDOCK sends a visitor's ship home now - they are
            told it left and get a fresh one on their next scan. A phone that goes
            dark parks its ship in the hangar by itself and gets it back on its own.
          </:blurb>

          <ul id="ship-list" class="flex flex-col gap-2">
            <li
              :for={ship <- @ships}
              id={"ship-#{ship.slug}"}
              class="flex items-center gap-3 border-2 border-base-300 px-3 py-2"
            >
              <Sprites.ship class={["size-6 shrink-0", Sprites.cargo_color(ship.cargo_type)]} />
              <div class="min-w-0 flex-1">
                <p class="truncate font-mono text-[11px] text-base-content">{ship.name}</p>
                <p class="truncate font-mono text-[10px] text-base-content/45">
                  {String.upcase(ship.cargo_type)} · {ship.hold}/{ship.hold_size} aboard · {format_count(
                    ship.delivered
                  )} delivered<span :if={ship.queue > 0} class="text-warning"> · {ship.queue} in mailbox</span>
                </p>
              </div>
              <button
                type="button"
                id={"undock-#{ship.slug}"}
                phx-click="undock"
                phx-value-ship={ship.slug}
                data-confirm={"Undock #{ship.name}? Its visitor gets a fresh ship on their next scan."}
                class="pixel-panel pixel-panel-danger shrink-0 px-3 py-2 font-pixel text-[9px] text-error"
              >
                UNDOCK
              </button>
            </li>
            <li :if={@ships == []} class="font-mono text-[11px] text-base-content/35">
              no visitors docked
            </li>
          </ul>

          <ul id="freighter-list" class="flex flex-wrap gap-2">
            <li
              :for={name <- @freighters}
              class="border-2 border-base-300 px-2 py-1 font-mono text-[11px] text-base-content/70"
            >
              {name}
            </li>
            <li :if={@freighters == []} class="font-mono text-[11px] text-base-content/35">
              no freighters on duty
            </li>
          </ul>

          <div class="grid grid-cols-2 gap-2">
            <.danger_button
              id="undock-visitors"
              event="undock_visitors"
              confirm="Undock every visitor's ship now, hangar included? Everyone gets a fresh ship on their next scan."
            >
              UNDOCK ALL VISITORS
            </.danger_button>
            <.danger_button
              id="clear-freighters"
              event="clear"
              confirm="Send every freighter home now? Traffic goes to OFF."
            >
              UNDOCK ALL FREIGHTERS
            </.danger_button>
          </div>
          <.danger_button
            id="undock-everyone"
            event="undock_everyone"
            confirm="Empty every berth - visitors, hangar and freighters? Traffic goes to OFF."
          >
            UNDOCK EVERY SHIP
          </.danger_button>
        </.panel>

        <.panel title="SIMULATED VISITORS" tone="text-primary" accent>
          <:blurb>
            Robot ships that dock, ship cargo and refill like a person with a
            timer for a thumb. Turn them up when the aisle is empty and down as
            people arrive. With yield on, every visitor who docks sends one
            freighter home, so the screen holds a steady crowd whoever is in it.
          </:blurb>

          <div id="traffic-levels" class="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <.choice
              :for={{name, count} <- @levels}
              id={"traffic-#{name}"}
              event="level"
              value={{"level", name}}
              pressed={@settings.freighters == count}
              tone="primary"
              title={name |> to_string() |> String.upcase()}
              sub={"#{count} freighters"}
            />
          </div>

          <.number_form
            form={@count_form}
            id="traffic-count-form"
            event="count"
            field="traffic[count]"
            label="EXACT NUMBER"
            min={0}
            max={99}
            value={@settings.freighters}
          />

          <.number_form
            form={@freighter_pace_form}
            id="freighter-pace-form"
            event="freighter_pace"
            field="freighter_pace[ms]"
            label="MS BETWEEN CONTAINERS, PER FREIGHTER"
            min={elem(@interval_bounds, 0)}
            max={elem(@interval_bounds, 1)}
            step={50}
            value={@settings.freighter_interval_ms}
            hint="Lower is heavier: the count is the load, this is its other half. Takes effect on each freighter's next container."
          />

          <.toggle
            prefix="yield"
            event="yield"
            param="yield"
            on={@settings.yield_to_visitors}
            tone="secondary"
            on_label="YIELD TO VISITORS"
            off_label="STAY"
          />
        </.panel>

        <.panel title="INSPECTION" tone="text-primary" accent>
          <:blurb>
            How many clerks run the checksums - the warehouse only routes. One
            clerk is the bottleneck: every container waits in one mailbox. More
            spread the load across the schedulers and the queue drains while
            everyone watches. Currently {@clerks_on_shift} on shift.
          </:blurb>

          <div class="grid grid-cols-2 gap-2">
            <.choice
              id="clerks-one"
              event="clerks"
              value={{"count", 1}}
              pressed={@clerks_on_shift == 1}
              tone="primary"
              title="SINGLE CLERK"
              sub="one mailbox, one bottleneck"
            />
            <.choice
              id="clerks-default"
              event="clerks"
              value={{"count", @default_clerks}}
              pressed={@clerks_on_shift == @default_clerks}
              tone="primary"
              title={"CREW OF #{@default_clerks}"}
              sub="one per scheduler"
            />
          </div>

          <.number_form
            form={@clerks_form}
            id="clerks-form"
            event="clerks"
            field="clerks[count]"
            label="EXACT NUMBER OF CLERKS"
            min={1}
            max={OpsPanel.max_clerks()}
            value={@clerks_on_shift}
          />
        </.panel>

        <.panel title="HAULERS" tone="text-secondary">
          <:blurb>
            Haulers take cargo off the shelf. Too few on purpose at the baseline,
            so the warehouse creeps up; send more and its memory turns around
            while everyone watches. Currently {@fleet.haulers} on duty.
          </:blurb>

          <div class="grid grid-cols-3 gap-2">
            <.choice
              :for={factor <- @hauler_boosts}
              id={"haulers-x#{factor}"}
              event="haulers"
              value={{"count", @baseline_haulers * factor}}
              pressed={@settings.haulers == @baseline_haulers * factor}
              tone="secondary"
              title={"x#{factor}"}
              sub={"#{@baseline_haulers * factor} haulers"}
            />
          </div>

          <.number_form
            form={@haulers_form}
            id="haulers-form"
            event="haulers"
            field="haulers[count]"
            label="EXACT NUMBER OF HAULERS"
            min={0}
            max={OpsPanel.max_haulers()}
            value={@settings.haulers}
          />

          <.number_form
            form={@hauler_pace_form}
            id="hauler-pace-form"
            event="hauler_pace"
            field="hauler_pace[ms]"
            label="MS BETWEEN PICKUPS, PER HAULER"
            min={elem(@interval_bounds, 0)}
            max={elem(@interval_bounds, 1)}
            step={50}
            value={@settings.hauler_interval_ms}
            hint="Lower drains faster: each hauler waits this long, give or take, then takes a batch. Takes effect on its next trip."
          />
        </.panel>

        <.panel title="WAREHOUSE" tone="text-secondary">
          <:blurb>
            Empties the shelf, the warehouse mailbox and every clerk's mailbox - {format_count(
              @stats.stored
            )} stored, {format_count(@stats.backlog)} waiting. The leaderboard
            keeps every delivery.
          </:blurb>

          <.danger_button
            id="clear-warehouse"
            event="clear_warehouse"
            confirm="Empty the warehouse and drop everything waiting in its queue and the clerks' queues?"
          >
            CLEAR WAREHOUSE AND QUEUES
          </.danger_button>
        </.panel>

        <.panel title="TELEVISION" tone="text-base-content/50">
          <.toggle
            prefix="qr"
            event="qr"
            param="show"
            on={@settings.show_qr}
            tone="neutral"
            on_label="SHOW QR CODES"
            off_label="HIDE QR CODES"
          />
        </.panel>

        <footer class="mt-auto flex items-center justify-between gap-4 pt-4 font-mono text-[11px] text-base-content/45">
          <span>everything else: <code>bin/station remote</code></span>
          <.link navigate={~p"/tv"} class="underline hover:text-primary">Station Ops screen</.link>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  # --- the panel's building blocks --------------------------------------------
  #
  # Five sections, three shapes of control. Each shape lives here once, so the
  # page reads as a list of decisions rather than a wall of markup, and a test
  # id on one control looks the same as on the next.

  attr :title, :string, required: true
  attr :tone, :string, default: "text-base-content/50"
  attr :accent, :boolean, default: false
  slot :blurb
  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <section class={["pixel-panel flex flex-col gap-3 p-4", @accent && "pixel-panel-accent"]}>
      <h2 class={["font-pixel text-[10px]", @tone]}>{@title}</h2>
      <p :for={blurb <- @blurb} class="font-mono text-[11px] text-base-content/50">
        {render_slot(blurb)}
      </p>
      {render_slot(@inner_block)}
    </section>
    """
  end

  # One preset among several: a title, a subtitle, pressed when it is the
  # current setting. `value` is the {param, value} the click sends.
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :value, :any, required: true
  attr :pressed, :boolean, required: true
  attr :tone, :string, values: ~w(primary secondary), required: true
  attr :title, :string, required: true
  attr :sub, :string, required: true

  defp choice(assigns) do
    {param, value} = assigns.value

    assigns =
      assign(assigns, :phx_value, %{("phx-value-" <> param) => value})

    ~H"""
    <button
      type="button"
      id={@id}
      phx-click={@event}
      {@phx_value}
      class={[
        "pixel-button flex flex-col items-start gap-1 p-3 text-left",
        pressed_class(@pressed, @tone)
      ]}
    >
      <span class="font-pixel text-[10px]">{@title}</span>
      <span class="font-mono text-[10px] opacity-70">{@sub}</span>
    </button>
    """
  end

  # Two buttons for one boolean; ids are `<prefix>-on` and `<prefix>-off`.
  attr :prefix, :string, required: true
  attr :event, :string, required: true
  attr :param, :string, required: true
  attr :on, :boolean, required: true
  attr :tone, :string, values: ~w(primary secondary neutral), required: true
  attr :on_label, :string, required: true
  attr :off_label, :string, required: true

  defp toggle(assigns) do
    assigns =
      assigns
      |> assign(:on_value, %{("phx-value-" <> assigns.param) => "true"})
      |> assign(:off_value, %{("phx-value-" <> assigns.param) => "false"})

    ~H"""
    <div class="grid grid-cols-2 gap-2">
      <button
        type="button"
        id={"#{@prefix}-on"}
        phx-click={@event}
        {@on_value}
        class={["pixel-button p-3 font-pixel text-[10px]", pressed_class(@on, @tone)]}
      >
        {@on_label}
      </button>
      <button
        type="button"
        id={"#{@prefix}-off"}
        phx-click={@event}
        {@off_value}
        class={["pixel-button p-3 font-pixel text-[10px]", pressed_class(not @on, @tone)]}
      >
        {@off_label}
      </button>
    </div>
    """
  end

  # A number and a SET button. `field` is the form field, `event` the submit.
  attr :form, Phoenix.HTML.Form, required: true
  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :min, :integer, required: true
  attr :max, :integer, required: true
  attr :step, :integer, default: 1
  attr :value, :integer, required: true
  attr :hint, :string, default: nil

  defp number_form(assigns) do
    ~H"""
    <.form for={@form} id={@id} phx-submit={@event} class="flex flex-col gap-2">
      <div class="flex items-end gap-2">
        <label class="flex flex-1 flex-col gap-1">
          <span class="font-pixel text-[9px] text-base-content/50">{@label}</span>
          <input
            type="number"
            name={@field}
            id={"#{@id}-input"}
            min={@min}
            max={@max}
            step={@step}
            value={@value}
            class="w-full border-2 border-base-300 bg-base-300 px-3 py-2 font-mono text-base text-base-content outline-none focus:border-primary"
          />
        </label>
        <button
          type="submit"
          class="pixel-button bg-base-200 px-4 py-3 font-pixel text-[10px] text-base-content/70"
        >
          SET
        </button>
      </div>
      <p :if={@hint} class="font-mono text-[11px] text-base-content/50">{@hint}</p>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :confirm, :string, required: true
  slot :inner_block, required: true

  defp danger_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-click={@event}
      data-confirm={@confirm}
      class="pixel-panel pixel-panel-danger flex items-center justify-center p-3 font-pixel text-[10px] text-error"
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp pressed_class(false, _tone), do: "bg-base-200 text-base-content/70"
  defp pressed_class(true, "primary"), do: "bg-primary text-primary-content"
  defp pressed_class(true, "secondary"), do: "bg-secondary text-secondary-content"
  defp pressed_class(true, "neutral"), do: "bg-base-content text-base-300"

  defp freighter_hint(%{yield_to_visitors: true, freighters: wanted}, on_duty)
       when on_duty < wanted,
       do: "#{wanted} asked, #{wanted - on_duty} yielded"

  defp freighter_hint(_settings, _on_duty), do: nil
end
