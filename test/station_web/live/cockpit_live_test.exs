defmodule StationWeb.CockpitLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.Cargo
  alias Station.Metrics

  test "a visitor without a ship is sent back to registration", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/ship")
  end

  test "the badge carries the string to hunt for on the big screen", %{conn: conn} do
    {conn, name} = with_ship(conn)
    {:ok, view, html} = live(conn, ~p"/ship")

    assert html =~ to_string(name)
    assert html =~ "#PID"
    assert has_element?(view, "#transfer-button")
    assert has_element?(view, "#hold-grid")
  end

  test "one press moves one container out of the hold", %{conn: conn} do
    {conn, name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    hold_size = Cargo.hold_size()

    assert view |> element("#hold-grid") |> render() =~ ~s(data-hold="#{hold_size}")

    render_click(view, "transfer")

    # The crate flies when the container leaves the ramp, not when the button
    # is pressed - the ship broadcasts each departure and the view follows.
    :sys.get_state(Process.whereis(name))
    assert_push_event(view, "station:transferred", %{refilled: false})

    # The press is a cast and the grid follows the poll, so let the ship work
    # and tick the poll by hand rather than sleeping through a refresh cycle.
    :sys.get_state(Process.whereis(name))
    send(view.pid, :refresh)

    assert view |> element("#hold-grid") |> render() =~ ~s(data-hold="#{hold_size - 1}")
    :sys.get_state(Station.Warehouse)
    assert Metrics.get(:accepted) == 1
  end

  # The autoclicker guard is the one thing standing between a public cookie
  # clicker and a booth that stops working: past a bounded mailbox on the
  # visitor's own ship, the cockpit refuses the press outright.
  test "hammering the button is stopped once the ship's mailbox is deep", %{conn: conn} do
    {conn, name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    # Freeze the ship mid-load, so every press stays in its mailbox.
    :sys.suspend(Process.whereis(name))
    cap = Application.fetch_env!(:station, :ship_queue_cap)
    for _ <- 1..(cap * 2), do: render_click(view, "transfer")

    assert Station.Ship.queue_len(name) <= cap + 1,
           "an autoclicker was allowed to grow an unbounded ship queue"

    assert render(view) =~ "RAMP BACKED UP"
    :sys.resume(Process.whereis(name))
  end

  test "an empty hold turns the button into a decision", %{conn: conn} do
    {conn, name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    for _ <- 1..Cargo.hold_size(), do: Station.Ship.transfer(name)
    :sys.get_state(Process.whereis(name))
    send(view.pid, :refresh)

    assert render(view) =~ "TAKE ON CARGO"

    render_click(view, "resupply")
    :sys.get_state(Process.whereis(name))
    send(view.pid, :refresh)

    assert render(view) =~ "TRANSFER CARGO"
    assert view |> element("#hold-grid") |> render() =~ ~s(data-hold="#{Cargo.hold_size()}")
  end

  test "a ship removed by ops takes its visitor back to registration", %{conn: conn} do
    {conn, name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    Station.DockingBay.remove(name)

    assert {:error, {:redirect, %{to: "/"}}} = render_click(view, "transfer")
  end
end
