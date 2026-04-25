defmodule Mix.Tasks.Parlinfo.Livebook do
  use Mix.Task

  @shortdoc "Print instructions for connecting Livebook to this app (dev only)"

  @node_name "parlinfo@127.0.0.1"
  @cookie "livebook_dev"
  @port 4040

  @impl Mix.Task
  def run(_args) do
    if Mix.env() != :dev do
      Mix.raise("mix parlinfo.livebook is only available in the dev environment")
    end

    notebook = Path.expand("priv/notebooks/backfill_analysis.livemd")

    IO.puts("""
    ─────────────────────────────────────────────────────
    Livebook setup for ParlInfo Search Agent
    ─────────────────────────────────────────────────────

    TERMINAL 1 — start the app as a named node:

      iex --name #{@node_name} --cookie #{@cookie} -S mix

    TERMINAL 2 — start Livebook with runtime pre-configured:

      LIVEBOOK_DEFAULT_RUNTIME="attached:#{@node_name}:#{@cookie}" livebook server --port #{@port}

    Then open http://localhost:#{@port} in your browser.
    Notebook: #{notebook}
    ─────────────────────────────────────────────────────
    """)
  end
end
