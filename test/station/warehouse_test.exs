defmodule Station.WarehouseTest do
  use Station.Case, async: false

  alias Station.Cargo
  alias Station.Leaderboard
  alias Station.Metrics
  alias Station.OpsPanel
  alias Station.Warehouse

  test "an accepted container is inspected by a clerk, stored and scored" do
    # Never the warehouse itself: one clerk on shift, and the checksum is theirs.
    assert Station.InspectionCrew.size() == 1
    [clerk] = Station.InspectionCrew.workers()
    {:reductions, before} = Process.info(Process.whereis(clerk), :reductions)

    [container] = Cargo.build_hold("ore", 1)
    Warehouse.accept("nostromo", container)
    settle()

    {:reductions, after_} = Process.info(Process.whereis(clerk), :reductions)
    assert after_ > before, "the clerk on shift did no work on the container"

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

  test "the shelf is published per cargo type, for the tiles on the television" do
    deliver("nostromo", "ice", 3)
    deliver("nostromo", "ore", 2)
    assert %{"ice" => 3, "ore" => 2, "machinery" => 0} = Warehouse.shelf()

    Warehouse.collect(self(), 2)
    settle()
    assert %{"ice" => 1, "ore" => 2} = Warehouse.shelf()

    Warehouse.flush()
    settle()
    assert %{"ice" => 0, "ore" => 0} = Warehouse.shelf()
  end

  test "the backlog is in the clerks' mailboxes and gets counted there" do
    OpsPanel.set_clerks(OpsPanel.default_clerks())

    clerks =
      Station.InspectionCrew.on_shift() |> Tuple.to_list() |> Enum.map(&Process.whereis/1)

    Enum.each(clerks, &:sys.suspend/1)

    deliver(nil, "ice", 6)
    Station.Watchdog.sample()

    stats = Warehouse.stats()
    assert stats.queue == 0
    assert stats.inspection_queue == 6
    assert stats.backlog == 6

    Enum.each(clerks, &:sys.resume/1)
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
    # The television colours the outgoing crates from this, per type.
    assert %{"machinery" => 3} = Warehouse.collected()
  end

  test "a whole crew does the checksums, and the count still adds up" do
    OpsPanel.set_clerks(OpsPanel.default_clerks())
    assert Station.InspectionCrew.size() > 1

    deliver("nostromo", "ore", 5)

    # The crew replies asynchronously, so wait for the count rather than the mailbox.
    assert eventually(fn -> Metrics.get(:stored) == 5 end)
    assert Metrics.get(:inspected) == 5
  end

  test "the crew switch reaches cargo that is already in the warehouse queue" do
    # The switch used to arrive as a message, so it queued behind the backlog it
    # was pressed to fix. At half a second a container that is a minute of ops
    # pressing a button and nothing happening.
    :sys.suspend(Warehouse)
    for container <- Cargo.build_hold("ore", 4), do: Warehouse.accept("nostromo", container)

    OpsPanel.set_clerks(OpsPanel.default_clerks())
    crew = Station.InspectionCrew.workers()
    Enum.each(crew, &:sys.suspend/1)

    :sys.resume(Warehouse)
    settle()

    # Nothing stored yet: all four went to a crew that is holding them, which is
    # only possible if the mailbox the switch never entered was read anyway.
    assert Metrics.get(:stored) == 0

    Enum.each(crew, &:sys.resume/1)
    assert eventually(fn -> Metrics.get(:stored) == 4 end)
  end

  test "stats never send the warehouse a message" do
    stats = Warehouse.stats()
    assert stats.alive?
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
