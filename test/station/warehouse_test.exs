defmodule Station.WarehouseTest do
  use Station.Case, async: false

  alias Station.Cargo
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.OpsPanel
  alias Station.Warehouse

  test "an accepted container is inspected, stored and scored" do
    [container] = Cargo.build_hold("ore", 1)
    Warehouse.accept("nostromo", container)
    settle()

    assert Metrics.get(:accepted) == 1
    assert Metrics.get(:inspected) == 1
    assert Metrics.get(:stored) == 1
    assert Metrics.get(:stored_bytes) == Cargo.container_bytes("ore")
    assert %{containers: 1, cargo: "ore"} = Leaderboard.get("nostromo")
  end

  test "over capacity the oldest cargo goes over the side" do
    capacity = Application.fetch_env!(:station, :warehouse_capacity)
    deliver("nostromo", "ice", capacity + 3)

    assert Metrics.get(:stored) == capacity
    assert Metrics.get(:dropped) == 3

    # The leaderboard counts what was delivered, not what is still on the shelf.
    # A visitor's score must not shrink because the station ran out of room.
    delivered = capacity + 3
    assert %{containers: ^delivered} = Leaderboard.get("nostromo")
  end

  test "a hauler takes cargo away and the memory goes with it" do
    deliver("nostromo", "machinery", 4)
    stored_bytes = Metrics.get(:stored_bytes)

    Warehouse.collect(self(), 3)
    settle()

    assert_receive {:cargo_collected, containers}
    assert length(containers) == 3
    assert Metrics.get(:stored) == 1
    assert Metrics.get(:stored_bytes) < stored_bytes
  end

  test "the inspection crew does the checksums instead, and the count still adds up" do
    OpsPanel.set_warehouse_mode(:inspection_crew)
    assert Station.InspectionCrew.size() > 0

    deliver("nostromo", "ore", 5)

    # The crew replies asynchronously, so wait for the count rather than the mailbox.
    assert eventually(fn -> Metrics.get(:stored) == 5 end)
    assert Metrics.get(:inspected) == 5
  end

  test "stats never send the warehouse a message" do
    stats = Warehouse.stats()
    assert stats.alive?
    assert stats.mode == :single_clerk
    assert is_integer(stats.queue)
  end

  defp deliver(ship, type, count) do
    for container <- Cargo.build_hold(type, count) do
      Warehouse.accept(ship, container)
    end

    settle()
  end

  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end
end
