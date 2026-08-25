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
    {conn, _name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    hold_size = Cargo.hold_size()

    assert view |> element("#hold-grid") |> render() =~ ~s(data-hold="#{hold_size}")

    render_click(view, "transfer")

    assert view |> element("#hold-grid") |> render() =~ ~s(data-hold="#{hold_size - 1}")
    :sys.get_state(Station.Warehouse)
    assert Metrics.get(:accepted) == 1
  end

  # The autoclicker guard is the one thing standing between a public cookie
  # clicker and a booth that stops working.
  test "hammering the button is throttled by the server", %{conn: conn} do
    {conn, _name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    limit = Application.fetch_env!(:station, :transfer_limits)[:per_second]
    for _ <- 1..(limit * 3), do: render_click(view, "transfer")

    assert Metrics.get(:throttled) > 0
    assert render(view) =~ "EASING OFF"
  end

  test "a ship removed by ops takes its visitor back to registration", %{conn: conn} do
    {conn, name} = with_ship(conn)
    {:ok, view, _html} = live(conn, ~p"/ship")

    Station.DockingBay.remove(name)

    assert {:error, {:redirect, %{to: "/"}}} = render_click(view, "transfer")
  end
end
