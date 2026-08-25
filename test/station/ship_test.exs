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

    assert {:ok, %{hold: hold, delivered: 1, refilled?: false}} = Ship.transfer(ship)
    assert hold == hold_size - 1

    settle()
    assert Metrics.get(:accepted) == 1
  end

  test "an empty hold is refilled rather than stranding the visitor", %{ship: ship} do
    hold_size = Station.Cargo.hold_size()

    result =
      Enum.reduce(1..hold_size, nil, fn _, _ ->
        wait_for_token()
        Ship.transfer(ship)
      end)

    assert {:ok, %{refilled?: true, hold: ^hold_size}} = result
  end

  test "the rate limit lives on the server, not in the browser", %{ship: ship} do
    limit = Application.fetch_env!(:station, :transfer_limits)[:per_second]

    results = for _ <- 1..(limit * 3), do: Ship.transfer(ship)

    assert Enum.any?(results, &match?({:throttled, _}, &1)),
           "an autoclicker was allowed to run unbounded"

    assert Metrics.get(:throttled) > 0
  end

  test "status is what the phone shows on its badge", %{ship: ship} do
    assert %{name: ^ship, slug: "nostromo", cargo_type: "ice", pid: "#PID" <> _} =
             Ship.status(ship)
  end

  test "talking to a ship that has already left does not blow up", %{ship: ship} do
    Ship.undock(ship)
    assert {:error, :gone} = Ship.transfer(ship)
    assert {:error, :gone} = Ship.status(ship)
  end

  # The bucket refills continuously, so a test that wants every transfer to land
  # has to wait for a token like a real thumb would.
  defp wait_for_token do
    Process.sleep(div(1000, Application.fetch_env!(:station, :transfer_limits)[:per_second]) + 5)
  end
end
