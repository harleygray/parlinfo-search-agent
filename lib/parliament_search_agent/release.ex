defmodule ParliamentSearchAgent.Release do
  @app :parliament_search_agent

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def backfill_reports do
    load_app()

    Ecto.Migrator.with_repo(ParliamentSearchAgent.Repo, fn repo ->
      changeset =
        ParliamentSearchAgent.Workers.BackfillReportsWorker.new(%{page: 0, total: 0})

      {:ok, _} = repo.insert(changeset)
      IO.puts("Backfill reports job enqueued — the running app will process it via Oban")
    end)
  end

  def backfill_transcripts do
    load_app()

    Ecto.Migrator.with_repo(ParliamentSearchAgent.Repo, fn repo ->
      changeset =
        ParliamentSearchAgent.Workers.BackfillTranscriptsWorker.new(%{page: 0, total: 0})

      {:ok, _} = repo.insert(changeset)
      IO.puts("Backfill transcripts job enqueued — the running app will process it via Oban")
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
