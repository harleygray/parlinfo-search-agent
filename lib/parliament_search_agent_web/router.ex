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
  end
end
