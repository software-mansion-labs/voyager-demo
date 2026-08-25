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
  alias Station.DockingBay
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.Ship
  alias Station.Warehouse
  alias StationWeb.DockController

  @refresh 1_000

  @impl true
  def mount(_params, session, socket) do
    case DockController.current_ship(session) do
      nil ->
        socket
        |> put_flash(:info, "Your ship has left the station. Register again to dock.")
        |> redirect(to: ~p"/")
        |> ok()

      ship ->
        if connected?(socket), do: :timer.send_interval(@refresh, :refresh)

        socket
        |> assign(:page_title, "#{ship} · STATION VOY-1")
        |> assign(:ship, ship)
        |> assign(:hold_size, Cargo.hold_size())
        |> assign(:flash_note, nil)
        |> refresh()
        |> ok()
    end
  end

  @impl true
  def handle_event("transfer", _params, socket) do
    case Ship.transfer(socket.assigns.ship) do
      {:ok, result} ->
        socket
        |> assign(:hold, result.hold)
        |> assign(:delivered, result.delivered)
        |> assign(:flash_note, if(result.refilled?, do: :refilled))
        |> push_event("station:transferred", %{hold: result.hold, refilled: result.refilled?})
        |> noreply()

      {:throttled, retry_in} ->
        socket
        |> assign(:flash_note, :throttled)
        |> push_event("station:throttled", %{retry_in: retry_in})
        |> noreply()

      {:error, :gone} ->
        socket
        |> put_flash(:info, "Your ship has left the station. Register again to dock.")
        |> redirect(to: ~p"/")
        |> noreply()
    end
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    ship = socket.assigns.ship

    case Ship.status(ship) do
      {:error, :gone} ->
        socket
        |> put_flash(:info, "Your ship has left the station. Register again to dock.")
        |> redirect(to: ~p"/")

      status ->
        stats = Warehouse.stats()

        socket
        |> assign(:status, status)
        |> assign(:hold, status.hold)
        |> assign(:delivered, status.delivered)
        |> assign(:stats, stats)
        |> assign(:congested?, stats.queue >= congestion_threshold())
        |> assign(:rank, Leaderboard.rank(status.slug))
        |> assign(:fleet_size, DockingBay.count())
        |> assign(:atoms, DockingBay.atom_budget())
        |> assign(:throttled, Metrics.get(:throttled))
    end
  end

  defp congestion_threshold do
    Application.fetch_env!(:station, :transfer_limits)[:congested_queue]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex min-h-screen w-full max-w-md flex-col gap-4 px-4 py-5">
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

        <div
          :if={@congested?}
          class="pixel-panel border-error/70 bg-error/10 p-3 font-pixel text-[10px] text-error animate-blink"
        >
          STATION CONGESTED - QUEUE: {format_count(@stats.queue)}
        </div>

        <section class="pixel-panel p-3">
          <div class="flex items-baseline justify-between">
            <span class="font-pixel text-[9px] text-base-content/50">HOLD</span>
            <span class="font-mono text-[11px] text-base-content/45">
              {@hold}/{@hold_size} {String.upcase(@status.cargo_type)} · {format_bytes(@status.memory)}
            </span>
          </div>

          <div
            id="hold-grid"
            phx-hook=".Hold"
            phx-update="ignore"
            data-hold={@hold}
            class="mt-3 grid grid-cols-10 gap-[3px]"
          >
            <span
              :for={index <- 1..@hold_size}
              data-index={index}
              class={["h-4 w-full transition-none", Sprites.cargo_color(@status.cargo_type)]}
            />
          </div>
        </section>

        <button
          type="button"
          id="transfer-button"
          phx-click="transfer"
          class="pixel-button bg-primary py-8 font-pixel text-base text-primary-content"
        >
          TRANSFER CARGO
        </button>

        <p class={[
          "text-center font-mono text-[11px]",
          note_tone(@flash_note)
        ]}>
          {note_text(@flash_note, @status.cargo_type)}
        </p>

        <section class="grid grid-cols-3 gap-2">
          <.readout label="DELIVERED" value={format_count(@delivered)} tone="text-success" />
          <.readout
            label="WH QUEUE"
            value={format_count(@stats.queue)}
            tone={queue_tone(@congested?)}
          />
          <.readout label="WH MEMORY" value={format_bytes(@stats.memory)} tone="text-primary" />
        </section>

        <section class="pixel-panel flex flex-col gap-2 p-3">
          <p class="font-pixel text-[9px] text-base-content/50">WHAT JUST HAPPENED</p>
          <p class="font-mono text-xs leading-relaxed text-base-content/60">
            Each press sends exactly one message from
            <span class="text-secondary">{@status.name}</span>
            to <span class="text-primary">Station.Warehouse</span>, and removes exactly one container
            from this ship's process state. The warehouse checksums it before it accepts it. Look at
            the laptop: your memory is falling, its memory is rising.
          </p>
          <p class="font-mono text-[11px] text-base-content/40">
            {@fleet_size} ships docked · {@atoms.used} atoms minted from ship names · this station has
            never freed one of them.
          </p>
        </section>

        <footer class="mt-auto flex items-center justify-between pt-2 font-mono text-[11px]">
          <a
            href="https://github.com/software-mansion/voyager"
            class="underline text-base-content/45 hover:text-primary"
          >
            What is Voyager?
          </a>
          <.link href={~p"/leave"} class="underline text-base-content/45 hover:text-error">
            UNDOCK
          </.link>
        </footer>
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

  defp note_tone(:throttled), do: "text-warning"
  defp note_tone(:refilled), do: "text-success"
  defp note_tone(_), do: "text-base-content/40"

  defp note_text(:throttled, _), do: "EASING OFF - the warehouse sets the pace, not your thumb."
  defp note_text(:refilled, type), do: "FRESH LOAD OF #{String.upcase(type)} TAKEN ON."
  defp note_text(_, _), do: "one press · one message · one container"
end
