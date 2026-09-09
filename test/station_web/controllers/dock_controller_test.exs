defmodule StationWeb.DockControllerTest do
  use StationWeb.ConnCase, async: false

  alias Station.DockingBay
  alias Station.ShipNames

  test "scanning the code is the whole registration", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/ship"

    slug = get_session(conn, :ship)
    assert slug in ShipNames.pool()

    [name] = DockingBay.list()
    assert ShipNames.to_slug(name) == slug
  end

  test "a full station sends the visitor to the television in observer mode", %{conn: conn} do
    for _ <- 1..DockingBay.capacity(), do: {:ok, _} = DockingBay.dock()

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/tv"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "station is full"
    assert get_session(conn, :ship) == nil
  end

  test "an already docked visitor is sent straight back to their cockpit", %{conn: conn} do
    {conn, _name} = with_ship(conn)

    assert conn |> get(~p"/") |> redirected_to() == ~p"/ship"
    assert length(DockingBay.list()) == 1
  end

  test "undocking stops the process, clears the session and offers a way back", %{conn: conn} do
    {conn, name} = with_ship(conn)
    ref = Process.monitor(Process.whereis(name))

    conn = get(conn, ~p"/leave")

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert get_session(conn, :ship) == nil

    html = html_response(conn, 200)
    assert html =~ to_string(name)
    assert html =~ ~s(id="dock-again")
  end

  test "leaving without a ship is not an error", %{conn: conn} do
    assert conn |> get(~p"/leave") |> html_response(200) =~ "NO SHIP DOCKED"
  end
end
