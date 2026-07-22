defmodule ParliamentSearchAgentWeb.Router do
  use ParliamentSearchAgentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ParliamentSearchAgentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :gone
  end

  # Sunset (2026-07-22): this public API is retired. The data now lives in Civic
  # Forum's authenticated API — every /api request answers 410 with a pointer.
  def gone(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(
      410,
      ~s({"error":"gone","see":"https://civicforum.com.au/developers"})
    )
    |> Plug.Conn.halt()
  end

  scope "/", ParliamentSearchAgentWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
  end

  if Mix.env() == :dev do
    scope "/.well-known" do
      get "/appspecific/com.chrome.devtools.json",
          ParliamentSearchAgentWeb.DevNullController,
          :index
    end
  end

  scope "/api", ParliamentSearchAgentWeb do
    pipe_through :api

    get "/reports/latest", Api.ReportsController, :latest
    get "/reports/:id", Api.ReportsController, :show
    get "/reports", Api.ReportsController, :index

    get "/hearing_transcripts/latest", Api.HearingTranscriptsController, :latest
    get "/hearing_transcripts/:id", Api.HearingTranscriptsController, :show
    get "/hearing_transcripts", Api.HearingTranscriptsController, :index

    get "/broadcasts/latest", Api.BroadcastsController, :latest
    get "/broadcasts/:id", Api.BroadcastsController, :show
    get "/broadcasts", Api.BroadcastsController, :index

    # Never dispatches — the :gone pipeline plug halts first. Present so every
    # /api path (not just the nine routes above) answers 410 rather than 404.
    match :*, "/*path", Api.ReportsController, :index
  end
end
