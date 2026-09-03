defmodule StationWeb.DockControllerTest do
  use StationWeb.ConnCase, async: false

  alias Station.DockingBay

  test "the registration screen offers every cargo type, cheapest first", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "VOYAGER STATION"
    assert html =~ ~s(id="dock-form")

    for type <- Station.Cargo.types() do
      assert html =~ ~s(value="#{type}")
    end
  end

  test "docking starts a named process and remembers it in the session", %{conn: conn} do
    conn = post(conn, ~p"/", %{"ship" => %{"name" => "Nostromo", "cargo" => "ore"}})

    assert redirected_to(conn) == ~p"/ship"
    assert get_session(conn, :ship) == "nostromo"
    assert is_pid(Process.whereis(:ship_nostromo))
  end

  test "a rejected name comes back with the form, not a crash", %{conn: conn} do
    conn = post(conn, ~p"/", %{"ship" => %{"name" => "kurwa", "cargo" => "ore"}})

    assert html_response(conn, 200) =~ "Pick another name"
    assert DockingBay.list() == []
  end

  test "a full station sends the visitor to the television in observer mode", %{conn: conn} do
    for n <- 1..DockingBay.capacity(), do: {:ok, _} = DockingBay.dock("ship #{n}", "ice")

    conn = post(conn, ~p"/", %{"ship" => %{"name" => "One Too Many", "cargo" => "ice"}})

    assert redirected_to(conn) == ~p"/tv"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "station is full"
  end

  test "an already docked visitor is sent straight back to their cockpit", %{conn: conn} do
    {conn, _name} = with_ship(conn)

    assert conn |> get(~p"/") |> redirected_to() == ~p"/ship"
  end

  test "undocking stops the process and clears the session", %{conn: conn} do
    {conn, name} = with_ship(conn)
    ref = Process.monitor(Process.whereis(name))

    conn = get(conn, ~p"/leave")

    assert_receive {:DOWN, ^ref, :process, _, _}
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :ship) == nil
  end
end
