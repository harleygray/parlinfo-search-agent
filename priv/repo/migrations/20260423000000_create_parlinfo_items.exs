defmodule ParliamentSearchAgent.Repo.Migrations.CreateParlinfoItems do
  use Ecto.Migration

  def change do
    create table(:parlinfo_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parlinfo_id, :string, null: false
      add :dataset, :string, null: false
      add :title, :string, null: false
      add :date_tabled, :date
      add :committee_name, :string
      add :chamber, :string
      add :parliament_number, :integer
      add :summary, :text
      add :pdf_url, :string
      add :source_url, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:parlinfo_items, [:parlinfo_id])
    create index(:parlinfo_items, [:dataset])
    create index(:parlinfo_items, [:inserted_at])
  end
end
