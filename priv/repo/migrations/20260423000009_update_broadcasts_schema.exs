defmodule ParliamentSearchAgent.Repo.Migrations.UpdateBroadcastsSchema do
  use Ecto.Migration

  def change do
    alter table(:broadcasts) do
      remove :date_tabled
      add :parlview_url, :string
      add :start_time, :naive_datetime
      add :end_time, :naive_datetime
      add :duration, :string
      add :parlinfo_permalink, :string
    end
  end
end
