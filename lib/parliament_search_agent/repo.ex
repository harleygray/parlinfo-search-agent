defmodule ParliamentSearchAgent.Repo do
  use Ecto.Repo,
    otp_app: :parliament_search_agent,
    adapter: Ecto.Adapters.Postgres
end
