defmodule ParlInfoSearchAgent.Repo.Migrations.AddReportTypeRemoveChamberFromReports do
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add :report_type, :string
      remove :chamber
    end
  end
end
