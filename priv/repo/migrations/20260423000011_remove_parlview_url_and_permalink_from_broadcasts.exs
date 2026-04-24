defmodule ParlInfoSearchAgent.Repo.Migrations.RemoveParlviewUrlAndPermalinkFromBroadcasts do
  use Ecto.Migration

  def change do
    alter table(:broadcasts) do
      remove :parlview_url
      remove :parlinfo_permalink
    end
  end
end
