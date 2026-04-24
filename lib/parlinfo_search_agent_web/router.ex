defmodule ParlInfoSearchAgentWeb.Router do
  use ParlInfoSearchAgentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ParlInfoSearchAgentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ParlInfoSearchAgentWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
  end

  if Mix.env() == :dev do
    scope "/.well-known" do
      get "/appspecific/com.chrome.devtools.json",
          ParlInfoSearchAgentWeb.DevNullController,
          :index
    end
  end

  scope "/api", ParlInfoSearchAgentWeb do
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
