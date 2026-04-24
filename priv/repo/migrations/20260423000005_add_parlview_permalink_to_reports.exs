defmodule ParlInfoSearchAgent.Repo.Migrations.AddParlviewPermalinkToReports do
  use Ecto.Migration

  def change do
    alter table(:reports) do
      add :parlview_permalink, :string
    end
  end
end
