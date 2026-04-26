defmodule ParliamentSearchAgent.Repo.Migrations.TextColumnsForLongFields do
  use Ecto.Migration

  # varchar(255) is too short for some ParlInfo titles and URLs.
  # Changing to text (unlimited) — no storage cost difference in Postgres.
  def change do
    for table <- [:reports, :hearing_transcripts] do
      alter table(table) do
        modify :title, :text
        modify :source_url, :text
        modify :pdf_url, :text
        modify :committee_name, :text
      end
    end

    alter table(:broadcasts) do
      modify :title, :text
      modify :source_url, :text
    end
  end
end
