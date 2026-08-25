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

  # The ops panel gets both defences the concept asks for: an unguessable path
  # segment and a password. Neither is much on its own; together they keep the
  # station's kill switches off a QR code that a few hundred people scanned.
  pipeline :ops do
    plug :basic_auth
  end

  scope "/", StationWeb do
    pipe_through :browser

    get "/", DockController, :new
    post "/", DockController, :create
    get "/leave", DockController, :delete

    live_session :ship do
      live "/ship", CockpitLive, :show
      live "/tv", StationOpsLive, :show
    end
  end

  scope "/ops", StationWeb do
    pipe_through [:browser, :ops]

    live_session :ops do
      live "/:token", OpsLive, :show
    end
  end

  if Application.compile_env(:station, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: StationWeb.Telemetry
    end
  end

  defp basic_auth(conn, _opts) do
    Plug.BasicAuth.basic_auth(conn,
      username: Application.fetch_env!(:station, :ops_username),
      password: Application.fetch_env!(:station, :ops_password)
    )
  end
end
