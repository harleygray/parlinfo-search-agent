defmodule ParlInfoSearchAgent.Repo.Migrations.AddParlviewPermalinkToHearingTranscripts do
  use Ecto.Migration

  def change do
    alter table(:hearing_transcripts) do
      add :parlview_permalink, :string
    end
  end
end
