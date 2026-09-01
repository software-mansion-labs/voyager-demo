defmodule Station.ShipTest do
  use Station.Case, async: false

  alias Station.DockingBay
  alias Station.Metrics
  alias Station.Ship

  setup do
    {:ok, name} = DockingBay.dock("Nostromo", "ice")
    %{ship: name}
  end

  test "one click moves exactly one container", %{ship: ship} do
    hold_size = Station.Cargo.hold_size()

    assert :ok = Ship.transfer(ship)
    drain(ship)

    assert %{hold: hold, delivered: 1, refills: 0} = Ship.status(ship)
    assert hold == hold_size - 1

    settle()
    assert Metrics.get(:accepted) == 1
  end

  test "an empty hold stays empty until its owner takes on cargo", %{ship: ship} do
    hold_size = Station.Cargo.hold_size()

    for _ <- 1..(hold_size + 3), do: Ship.transfer(ship)
    drain(ship)

    # The three presses past the last container died at the ramp: no refill
    # happens on its own, and nothing shipped that was never aboard.
    assert %{refills: 0, hold: 0, delivered: ^hold_size} = Ship.status(ship)

    :ok = Ship.resupply(ship)
    drain(ship)

    assert %{refills: 1, hold: ^hold_size} = Ship.status(ship)
  end

  test "presses beyond ramp speed queue on the ship itself", %{ship: ship} do
    # A slow ramp, so casts pile up in the mailbox the way fast thumbs do.
    original = Application.fetch_env!(:station, :ship_load_ms)
    Application.put_env(:station, :ship_load_ms, 40)
    on_exit(fn -> Application.put_env(:station, :ship_load_ms, original) end)

    for _ <- 1..5, do: Ship.transfer(ship)

    assert Ship.queue_len(ship) > 0, "a fast thumb left no trace on the ship's own mailbox"

    drain(ship)
    assert %{delivered: 5} = Ship.status(ship)
  end

  test "status is what the phone shows on its badge, and costs no message", %{ship: ship} do
    assert %{name: ^ship, slug: "nostromo", cargo_type: "ice", pid: "#PID" <> _, queue: 0} =
             Ship.status(ship)
  end

  # Idle means "nobody is pressing", not "nobody is connected". The cockpit polls
  # this process every second to redraw its counters, so a ship that measured its
  # own idleness from the last message would stay docked for as long as a tab was
  # open on a table somewhere - holding one of twenty five berths with a queue of
  # people behind it.
  #
  # The poller here never stops, which is the point: it has to be the silence on
  # the button that ends the ship, not the silence on the socket.
  test "a ship that stops shipping drifts off while the cockpit is still polling",
       %{ship: ship} do
    with_ttl(250)
    # The shortened ttl arms on the next press - nothing else touches the
    # process's clock any more, status included, which is the point.
    Ship.transfer(ship)
    ref = Process.monitor(Process.whereis(ship))
    poller = poll_status(ship, 40)

    assert_receive {:DOWN, ^ref, :process, _, :normal}, 2_000

    Process.exit(poller, :kill)
  end

  test "a press keeps the ship docked", %{ship: ship} do
    with_ttl(300)
    ref = Process.monitor(Process.whereis(ship))

    for _ <- 1..3 do
      Process.sleep(120)
      Ship.transfer(ship)
    end

    refute_receive {:DOWN, ^ref, :process, _, _}, 100
    assert is_pid(Process.whereis(ship))
  end

  test "talking to a ship that has already left does not blow up", %{ship: ship} do
    Ship.undock(ship)
    assert {:error, :gone} = Ship.transfer(ship)
    assert {:error, :gone} = Ship.status(ship)
  end

  defp with_ttl(milliseconds) do
    original = Application.fetch_env!(:station, :ship_ttl_ms)
    Application.put_env(:station, :ship_ttl_ms, milliseconds)
    on_exit(fn -> Application.put_env(:station, :ship_ttl_ms, original) end)
  end

  # Blocks until the ship has worked through everything already in its mailbox.
  defp drain(ship) do
    :sys.get_state(Process.whereis(ship))
    :ok
  end

  # Stands in for the cockpit's refresh timer: asks and asks and never presses.
  defp poll_status(ship, every) do
    spawn(fn ->
      Stream.repeatedly(fn ->
        Ship.status(ship)
        Process.sleep(every)
      end)
      |> Stream.run()
    end)
  end
end
