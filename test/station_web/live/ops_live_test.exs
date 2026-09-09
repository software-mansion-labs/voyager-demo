defmodule StationWeb.OpsLiveTest do
  use StationWeb.ConnCase, async: false

  alias Station.Dispatcher
  alias Station.OpsPanel

  setup %{conn: conn} do
    password = Application.fetch_env!(:station, :ops_password)
    credentials = Plug.BasicAuth.encode_basic_auth("ops", password)
    %{conn: put_req_header(conn, "authorization", credentials)}
  end

  test "the panel is not reachable without the password" do
    assert build_conn() |> get(~p"/ops") |> response(401)
  end

  test "a traffic level is one press", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#traffic-quiet") |> render_click()

    assert OpsPanel.freighters() == OpsPanel.traffic_levels().quiet
    assert Dispatcher.fleet().freighters == OpsPanel.traffic_levels().quiet
    assert render(view) =~ "freighter_01"
  end

  test "an exact number is a form, and nonsense is ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view
    |> form("#traffic-count-form", traffic: %{count: "2"})
    |> render_submit()

    assert OpsPanel.freighters() == 2

    view
    |> form("#traffic-count-form", traffic: %{count: "500"})
    |> render_submit()

    assert OpsPanel.freighters() == 2
  end

  test "yield is a switch and undock-all is a button", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/ops")

    view |> element("#yield-off") |> render_click()
    refute OpsPanel.yield_to_visitors?()

    view |> element("#yield-on") |> render_click()
    assert OpsPanel.yield_to_visitors?()

    OpsPanel.set_traffic(3)
    view |> element("#clear-freighters") |> render_click()

    assert OpsPanel.freighters() == 0
    assert Dispatcher.fleet().freighters == 0
  end
end
