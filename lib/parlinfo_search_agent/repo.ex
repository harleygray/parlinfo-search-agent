defmodule ParlInfoSearchAgent.Repo do
  use Ecto.Repo,
    otp_app: :parlinfo_search_agent,
    adapter: Ecto.Adapters.Postgres
end
