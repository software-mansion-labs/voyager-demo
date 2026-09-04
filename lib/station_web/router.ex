defmodule StationWeb.Router do
  use StationWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StationWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", StationWeb do
    pipe_through :browser

    get "/", DockController, :new
    post "/", DockController, :create
    get "/leave", DockController, :delete

    live_session :ship do
      live "/ship", CockpitLive, :show
      live "/tv", StationOpsLive, :show
      live "/leaderboard", LeaderboardLive, :show
    end
  end

  if Application.compile_env(:station, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: StationWeb.Telemetry
    end
  end
end
