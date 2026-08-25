defmodule Station.Freighter do
  @moduledoc """
  A robot doing exactly what a visitor does, without the thumb: dock, push
  containers at the warehouse one message at a time, undock.
  """

  use GenServer, restart: :temporary

  alias Station.Cargo
  alias Station.Warehouse

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:priority, :low)

    runs = Application.fetch_env!(:station, :freighter_runs)
    type = Cargo.random_type()
    interval = Keyword.fetch!(opts, :interval_ms)

    state = %{
      slug: opts |> Keyword.fetch!(:name) |> Atom.to_string(),
      hold: Cargo.build_hold(type, runs),
      interval: interval
    }

    schedule(interval)
    {:ok, state}
  end

  @impl true
  def handle_info(:deliver, %{hold: []} = state), do: {:stop, :normal, state}

  def handle_info(:deliver, %{hold: [container | rest]} = state) do
    Warehouse.accept(state.slug, container)
    schedule(state.interval)
    {:noreply, %{state | hold: rest}}
  end

  # Jittered so the whole fleet does not beat in unison, which would look like
  # one big periodic spike instead of steady background traffic.
  defp schedule(interval) do
    Process.send_after(self(), :deliver, interval + :rand.uniform(interval))
  end
end
