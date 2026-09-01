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
        |> put_flash(:info, "Your ship has left the station. Register again to dock.")
        |> redirect(to: ~p"/")
        |> ok()

      ship ->
        if connected?(socket) do
          :timer.send_interval(@refresh, :refresh)
          Phoenix.PubSub.subscribe(Station.PubSub, Ship.topic(ShipNames.to_slug(ship)))
        end

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
    ship = socket.assigns.ship

    # The press is a cast: the ship loads containers at its own ramp speed and
    # a faster thumb piles messages up on the ship's own process, where Voyager
    # can find them. The only hard stop lives here - past the cap the mailbox
    # is deep enough to make the point, and an autoclicker gets a bounded queue.
    cond do
      Ship.queue_len(ship) >= queue_cap() ->
        socket
        |> assign(:flash_note, :backed_up)
        |> push_event("station:throttled", %{})
        |> noreply()

      true ->
        # No animation here: the crate flies on the ship's own {:shipped}
        # broadcast, once the container has really left the ramp.
        case Ship.transfer(ship) do
          :ok ->
            socket
            |> assign(:flash_note, nil)
            |> noreply()

          {:error, :gone} ->
            socket
            |> put_flash(:info, "Your ship has left the station. Register again to dock.")
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
    |> assign(:flash_note, if(shipped.refilled?, do: :refilled, else: socket.assigns.flash_note))
    |> push_event("station:transferred", %{refilled: shipped.refilled?})
    |> noreply()
  end

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
    end
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
      <div class="mx-auto flex h-dvh w-full max-w-md flex-col gap-2 overflow-y-auto overscroll-contain px-4 py-3">
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

        <%!-- The same thing the television shows, at arm's length: the
              container leaves this ship and crosses to the station. A throttled
              press turns back short of the door, so backpressure is something
              the visitor watches as well as feels. --%>
        <%!-- The congestion notice lies on top of the flight strip instead of
              taking a row of its own: it appears exactly when a thumb is going
              fastest, and any band of pixels entering the layout at that moment
              moves the button out from under that thumb mid-press. --%>
        <div class="relative shrink-0">
          <div
            :if={@congested?}
            class="pixel-panel absolute inset-x-2 top-2 z-10 flex items-center border-error/70 bg-error/10 px-3 py-2 font-pixel text-[10px] text-error animate-blink"
          >
            STATION CONGESTED - QUEUE: {format_count(@stats.queue)}
          </div>

          <section
            id="cockpit-flight"
            phx-hook=".Flight"
            phx-update="ignore"
            class="scene pixel-panel relative h-14"
          >
            <div class="scene-stars scene-stars-far"></div>

            <div
              class={["scene-actor w-12", Sprites.cargo_color(@status.cargo_type)]}
              style="left: 14%; top: 50%"
            >
              <div class="scene-hover relative">
                <span class="scene-thruster"></span>
                <Sprites.ship class="w-full" />
              </div>
            </div>

            <span data-flight-port class="scene-port text-primary" style="left: 74%; top: 50%"></span>

            <div class="scene-actor w-24 text-primary" style="left: 84%; top: 50%">
              <Sprites.station_hub class="w-full" />
            </div>

            <div data-flight-lane class="absolute inset-0"></div>
          </section>
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

        <p class={[
          "flex min-h-8 items-center justify-center text-center font-mono text-[11px]",
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
          <.readout label="MEMORY" value={format_bytes(@stats.memory)} tone="text-primary" />
        </section>

        <%!-- Never clipped: a sentence cut in half reads as a bug, so the
              explainer keeps its whole height and the hold grid above is what
              absorbs a short viewport - its bars just draw thinner. --%>
        <section class="pixel-panel flex shrink-0 flex-col gap-2 p-3">
          <p class="font-pixel text-[9px] text-base-content/50">WHAT JUST HAPPENED</p>
          <p class="font-mono text-[11px] leading-snug text-base-content/60">
            Every press is a real message to <span class="text-primary">Station.Warehouse</span>. Look at the laptop: this ship's
            memory is falling, the warehouse's is rising.
          </p>
        </section>

        <footer class="flex shrink-0 items-center justify-between pt-1 font-mono text-[11px]">
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

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Flight">
        export default {
          mounted() {
            this.lane = this.el.querySelector("[data-flight-lane]");
            this.port = this.el.querySelector("[data-flight-port]");
            this.tone = (this.el.querySelector(".scene-actor").className.match(/text-\S+/) || ["text-primary"])[0];

            this.handleEvent("station:transferred", ({refilled}) => !refilled && this.launch(true));
            this.handleEvent("station:throttled", () => this.launch(false));
          },

          // One press, one container, one crossing.
          launch(arrives) {
            const crate = document.createElement("div");
            crate.className = `scene-crate w-5 ${arrives ? this.tone : "text-warning"}`;
            crate.style.left = "22%";
            crate.style.top = "50%";
            crate.innerHTML = `<svg viewBox="0 0 16 16" class="pixelated w-full"><use href="#sprite-container"></use></svg>`;
            this.lane.appendChild(crate);

            const frames = arrives
              ? [
                  {left: "22%", top: "50%", opacity: 0.4},
                  {left: "48%", top: "34%", opacity: 1, offset: 0.5},
                  {left: "74%", top: "50%", opacity: 1},
                ]
              : [
                  {left: "22%", top: "50%", opacity: 0.4},
                  {left: "42%", top: "42%", opacity: 1, offset: 0.5},
                  {left: "24%", top: "62%", opacity: 0},
                ];

            const animation = crate.animate(frames, {duration: 520, easing: "steps(14, end)"});

            animation.onfinish = () => {
              crate.remove();
              if (!arrives) { return; }

              this.port.classList.add("is-hot");
              setTimeout(() => this.port.classList.remove("is-hot"), 140);
            };

            // A backgrounded tab can swallow the finish event, and a phone in a
            // pocket is a backgrounded tab. Bound the leak.
            setTimeout(() => crate.remove(), 1500);
          }
        }
      </script>

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

  defp note_tone(:backed_up), do: "text-warning"
  defp note_tone(:refilled), do: "text-success"
  defp note_tone(_), do: "text-base-content/40"

  defp note_text(:backed_up, _),
    do: "RAMP BACKED UP - your ship's mailbox is full, watch it drain in Voyager."

  defp note_text(:refilled, type), do: "FRESH LOAD OF #{String.upcase(type)} TAKEN ON."
  defp note_text(_, _), do: "one press · one message · one container"
end
