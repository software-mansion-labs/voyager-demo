defmodule StationWeb.CockpitLive do
  @moduledoc """
  The visitor's phone.

  One badge with the string to hunt for on the big screen, one hold that
  visibly empties, and one button that is worth pressing. Everything else on
  this page exists to make the two facts underneath it land: the box that left
  the grid is the memory that left the ship, and the queue in the header is the
  reason the button sometimes feels heavy.
  """

  use StationWeb, :live_view

  alias Station.Cargo
  alias Station.Leaderboard
  alias Station.Ship
  alias Station.ShipNames
  alias Station.Warehouse
  alias StationWeb.DockController

  @refresh 1_000

  @impl true
  def mount(_params, session, socket) do
    case DockController.current_ship(session) do
      nil ->
        socket
        |> put_flash(:info, gone_notice(session))
        |> redirect(to: ~p"/")
        |> ok()

      ship ->
        if connected?(socket) do
          :timer.send_interval(@refresh, :refresh)
          Phoenix.PubSub.subscribe(Station.PubSub, Ship.topic(ShipNames.to_slug(ship)))
          # From here the ship watches this process: when the phone goes dark
          # for good, the ship parks itself and frees the berth.
          Ship.board(ship, self())
        end

        socket
        |> assign(:page_title, "#{ship} · VOYAGER STATION")
        |> assign(:ship, ship)
        |> assign(:hold_size, Cargo.hold_size())
        |> refresh()
        |> ok()
    end
  end

  @impl true
  def handle_event("transfer", _params, socket) do
    ship = socket.assigns.ship

    # The press is a cast: the ship loads containers at its own ramp speed and
    # a faster thumb piles messages up on the ship's own process, where Voyager
    # can find them. The only hard stop lives here - past the cap the mailbox
    # is deep enough to make the point, and an autoclicker gets a bounded queue.
    cond do
      Ship.queue_len(ship) >= queue_cap() ->
        socket
        |> push_event("station:throttled", %{})
        |> noreply()

      true ->
        # No animation here: the crate flies on the ship's own {:shipped}
        # broadcast, once the container has really left the ramp.
        case Ship.transfer(ship) do
          :ok ->
            noreply(socket)

          {:error, :gone} ->
            socket
            |> put_flash(:info, "Your ship has left the station. Docking a fresh one.")
            |> redirect(to: ~p"/")
            |> noreply()
        end
    end
  end

  def handle_event("resupply", _params, socket) do
    Ship.resupply(socket.assigns.ship)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  def handle_info({:shipped, shipped}, socket) do
    socket
    |> assign(:hold, shipped.hold)
    |> assign(:delivered, shipped.delivered)
    |> push_event("station:transferred", %{refilled: shipped.refilled?})
    |> noreply()
  end

  defp refresh(socket) do
    ship = socket.assigns.ship

    case Ship.status(ship) do
      {:error, :gone} ->
        socket
        |> put_flash(:info, "Your ship has left the station. Docking a fresh one.")
        |> redirect(to: ~p"/")

      status ->
        stats = Warehouse.stats()

        socket
        |> assign(:status, status)
        |> assign(:hold, status.hold)
        |> assign(:delivered, status.delivered)
        |> assign(:stats, stats)
        |> assign(:congested?, stats.backlog >= congestion_threshold())
        |> assign(:rank, Leaderboard.rank(status.slug))
    end
  end

  # The ship is gone, but the reason decides what the next page says: a ship
  # that parked itself while the phone was dark comes straight back.
  defp gone_notice(session) do
    if DockController.returning?(session),
      do: "Welcome back. Docking your ship again.",
      else: "Your ship has left the station. Docking a fresh one."
  end

  defp congestion_threshold do
    Application.fetch_env!(:station, :congested_queue)
  end

  defp queue_cap do
    Application.fetch_env!(:station, :ship_queue_cap)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%!-- Locked to the viewport: the cockpit is a controller, not a page.
            There is nothing to scroll, so a fast thumb has nothing to drag,
            and the button never leaves the reachable half of the screen. The
            hold grid is the one flexible element - it absorbs whatever height
            this particular phone has to give. --%>
      <div class="mx-auto flex h-dvh w-full max-w-md select-none flex-col gap-2 overflow-y-auto overscroll-contain px-4 py-3">
        <header class={[
          "pixel-panel flex items-center gap-3 p-3",
          if(@congested?, do: "border-error/70", else: "pixel-panel-accent")
        ]}>
          <Sprites.ship class={[
            "size-10 shrink-0 animate-bob",
            Sprites.cargo_color(@status.cargo_type)
          ]} />
          <div class="min-w-0 flex-1">
            <p class="font-pixel text-[9px] text-base-content/50">YOUR SHIP</p>
            <p class="truncate font-pixel text-xs text-secondary">{@status.name}</p>
            <p class="truncate font-mono text-[11px] text-base-content/45">{@status.pid}</p>
          </div>
          <div class="text-right">
            <p class="font-pixel text-[9px] text-base-content/50">RANK</p>
            <p class="font-pixel text-sm text-primary">{if @rank, do: "##{@rank}", else: "-"}</p>
          </div>
        </header>

        <%!-- A fixed-height line, whether or not it says anything: the
              congestion notice appears exactly when a thumb is going fastest,
              and any band of pixels entering the layout at that moment moves
              the button out from under that thumb mid-press. --%>
        <div class="flex h-8 shrink-0 items-center">
          <div
            :if={@congested?}
            class="pixel-panel flex w-full items-center border-error/70 bg-error/10 px-3 py-1 font-pixel text-[10px] text-error animate-blink"
          >
            STATION CONGESTED - QUEUE: {format_count(@stats.backlog)}
          </div>
        </div>

        <section class="pixel-panel flex min-h-24 flex-1 flex-col p-3">
          <div class="flex items-baseline justify-between">
            <span class="font-pixel text-[9px] text-base-content/50">HOLD</span>
            <span class="font-mono text-[11px] text-base-content/45">
              {@hold}/{@hold_size} {String.upcase(@status.cargo_type)} · {format_bytes(@status.memory)}<span
                :if={@status.queue > 0}
                class="text-warning"
              > · {@status.queue} in mailbox</span>
            </span>
          </div>

          <div
            id="hold-grid"
            phx-hook=".Hold"
            phx-update="ignore"
            data-hold={@hold}
            class="mt-3 grid min-h-0 flex-1 auto-rows-fr grid-cols-10 gap-[3px]"
          >
            <span
              :for={index <- 1..@hold_size}
              data-index={index}
              class={["w-full transition-none", Sprites.cargo_color(@status.cargo_type)]}
            />
          </div>
        </section>

        <%!-- An empty ship stays empty until its owner decides otherwise: the
              same button changes job, so the decision is one thumb away and
              the pause before it is the visitor's own. --%>
        <button
          type="button"
          id="transfer-button"
          phx-click={if @hold == 0, do: "resupply", else: "transfer"}
          class={[
            "pixel-button shrink-0 py-5 font-pixel text-base",
            if(@hold == 0,
              do: "bg-secondary text-secondary-content",
              else: "bg-primary text-primary-content"
            )
          ]}
        >
          {if @hold == 0, do: "TAKE ON CARGO", else: "TRANSFER CARGO"}
        </button>

        <section class="grid grid-cols-3 gap-2">
          <.readout label="DELIVERED" value={format_count(@delivered)} tone="text-success" />
          <.readout
            label="WH QUEUE"
            value={format_count(@stats.backlog)}
            tone={queue_tone(@congested?)}
          />
          <.readout label="MEMORY" value={format_bytes(@stats.memory)} tone="text-primary" />
        </section>

        <%!-- The two exits: Voyager, where the visitor goes to check the
              numbers, and the way off the station. --%>
        <div class="grid shrink-0 grid-cols-2 gap-2">
          <a
            href="https://voyager.swmansion.com"
            target="_blank"
            rel="noopener"
            class="voyager-button flex items-center justify-center p-3"
          >
            <Sprites.voyager_logo class="h-8" />
          </a>
          <.link
            href={~p"/leave"}
            class="pixel-panel pixel-panel-danger flex items-center justify-center p-3 font-pixel text-sm text-error"
          >
            UNDOCK
          </.link>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Hold">
        export default {
          mounted() {
            this.cells = Array.from(this.el.children);
            this.paint();

            // Haptics only. Sound is off by default at a booth where twenty
            // people are standing shoulder to shoulder.
            this.handleEvent("station:transferred", ({refilled}) => {
              if (navigator.vibrate) { navigator.vibrate(refilled ? [12, 40, 12] : 8); }
            });

            this.handleEvent("station:throttled", () => {
              if (navigator.vibrate) { navigator.vibrate([3, 30, 3]); }
            });
          },

          updated() { this.paint(); },

          // The hold is 120 boxes. Sending 120 changed class attributes per press
          // would be the single biggest thing on the wire at a booth on
          // conference wifi, so the server sends one number and this paints it.
          paint() {
            const hold = parseInt(this.el.dataset.hold, 10);
            this.cells.forEach((cell, index) => {
              const full = index < hold;
              cell.style.backgroundColor = full ? "currentColor" : "";
              cell.style.opacity = full ? "1" : "0.12";
              cell.style.outline = full ? "" : "1px solid currentColor";
            });
          }
        }
      </script>
    </Layouts.app>
    """
  end

  defp queue_tone(true), do: "text-error"
  defp queue_tone(false), do: "text-base-content"
end
