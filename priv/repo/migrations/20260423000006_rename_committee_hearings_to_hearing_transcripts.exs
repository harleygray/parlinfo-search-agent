defmodule ParliamentSearchAgent.Repo.Migrations.RenameCommitteeHearingsToHearingTranscripts do
  use Ecto.Migration

  def change do
    rename table(:committee_hearings), to: table(:hearing_transcripts)
  end
end
