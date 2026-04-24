defmodule Mix.Tasks.Parlinfo.ClearItems do
  use Mix.Task

  @shortdoc "Delete all rows from reports, hearing_transcripts, and broadcasts"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:parlinfo_search_agent)

    repo = ParlInfoSearchAgent.Repo

    {reports, _} = repo.delete_all(ParlInfoSearchAgent.Items.Report)
    {transcripts, _} = repo.delete_all(ParlInfoSearchAgent.Items.HearingTranscript)
    {broadcasts, _} = repo.delete_all(ParlInfoSearchAgent.Items.Broadcast)

    Mix.shell().info(
      "Deleted #{reports} reports, #{transcripts} hearing transcripts, #{broadcasts} broadcasts."
    )
  end
end
