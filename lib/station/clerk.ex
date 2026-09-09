defmodule Station.Clerk do
  @moduledoc """
  One clerk in the inspection crew: checksum a container, hand it back.

  Runs at `:low` priority so a busy station never starves the LiveViews serving
  the visitors' phones. Named `clerk_01`, `clerk_02`, ... in the tree, so the
  crew reads on the television and in Voyager as the same word.
  """

  use GenServer, restart: :temporary

  alias Station.Cargo
  alias Station.Metrics
  alias Station.Warehouse

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    Process.flag(:priority, :low)
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:inspect, ship, container}, state) do
    _checksum = Cargo.inspect_container(container)
    Metrics.add(:inspected, 1)
    Warehouse.inspected(ship, container)
    {:noreply, state}
  end
end
