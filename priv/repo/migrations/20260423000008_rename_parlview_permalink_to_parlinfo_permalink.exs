defmodule ParlInfoSearchAgent.Repo.Migrations.RenameParlviewPermalinkToParlinfoPermanlink do
  use Ecto.Migration

  def change do
    rename table(:reports), :parlview_permalink, to: :parlinfo_permalink
    rename table(:hearing_transcripts), :parlview_permalink, to: :parlinfo_permalink
  end
end
