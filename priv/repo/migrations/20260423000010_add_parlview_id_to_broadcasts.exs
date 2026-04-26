defmodule ParliamentSearchAgent.Repo.Migrations.AddParlviewIdToBroadcasts do
  use Ecto.Migration

  def change do
    alter table(:broadcasts) do
      add :parlview_id, :string
      modify :parlinfo_id, :string, null: true
    end

    create unique_index(:broadcasts, [:parlview_id], where: "parlview_id IS NOT NULL")
  end
end
