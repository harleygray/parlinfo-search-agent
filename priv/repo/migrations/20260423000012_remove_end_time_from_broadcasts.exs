defmodule ParliamentSearchAgent.Repo.Migrations.RemoveEndTimeFromBroadcasts do
  use Ecto.Migration

  def change do
    alter table(:broadcasts) do
      remove :end_time
    end
  end
end
