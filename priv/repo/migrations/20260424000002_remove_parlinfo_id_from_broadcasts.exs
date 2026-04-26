defmodule ParliamentSearchAgent.Repo.Migrations.RemoveParlInfoIdFromBroadcasts do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:broadcasts, [:parlinfo_id])

    alter table(:broadcasts) do
      remove :parlinfo_id
    end
  end
end
