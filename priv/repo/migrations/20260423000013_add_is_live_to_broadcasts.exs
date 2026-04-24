defmodule ParlInfoSearchAgent.Repo.Migrations.AddIsLiveToBroadcasts do
  use Ecto.Migration

  def change do
    alter table(:broadcasts) do
      add :is_live, :boolean, null: false, default: false
    end
  end
end
