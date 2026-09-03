defmodule StationWeb.LeaderboardLive do
  @moduledoc """
  The leaderboard on its own screen.

  Styled as what it is: a dump of an ETS table. Process state dies with the
  process, this table survives it, and its snapshot on disk survives the node.
  """

  use StationWeb, :live_view

  alias Station.Leaderboard

  @refresh 1_000
  @rows 30

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh, :refresh)

    socket
    |> assign(:page_title, "LEADERBOARD · STATION VOY-1")
    |> refresh()
    |> ok()
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    socket
    |> assign(:board, Leaderboard.top(@rows))
    |> assign(:board_size, Leaderboard.size())
    |> assign(:total_containers, Leaderboard.total_containers())
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
          <span class="border-2 border-base-content/20 px-3 py-2 font-pixel text-[10px] text-base-content/60">
            {format_count(@total_containers)} CONTAINERS
          </span>
        </header>

        <section class="pixel-panel mx-auto flex min-h-0 w-full max-w-4xl flex-1 flex-col gap-2 p-4">
          <div class="flex items-baseline justify-between">
            <h2 class="font-pixel text-sm text-success">:station_leaderboard</h2>
            <span class="font-mono text-sm text-base-content/45">{@board_size} rows</span>
          </div>

          <div class="min-h-0 flex-1 overflow-hidden">
            <table class="w-full table-fixed font-mono text-base">
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
                  <td class={["truncate py-1 pr-2", Sprites.cargo_color(row.cargo)]}>
                    {row.cargo}
                  </td>
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
          </div>

          <p class="mt-auto font-mono text-xs leading-relaxed text-base-content/40">
            Process state dies with the process. This table survives it, and its
            snapshot on disk survives the node. Three levels, one story.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
