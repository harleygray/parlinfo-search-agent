defmodule ParliamentSearchAgent.Repo.Migrations.SeparateParlinfoTables do
  use Ecto.Migration

  def change do
    drop table(:parlinfo_items)

    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parlinfo_id, :string, null: false
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

    create unique_index(:reports, [:parlinfo_id])
    create index(:reports, [:inserted_at])

    create table(:broadcasts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parlinfo_id, :string, null: false
      add :title, :string, null: false
      add :date_tabled, :date
      add :chamber, :string
      add :source_url, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:broadcasts, [:parlinfo_id])
    create index(:broadcasts, [:inserted_at])

    create table(:committee_hearings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :parlinfo_id, :string, null: false
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

    create unique_index(:committee_hearings, [:parlinfo_id])
    create index(:committee_hearings, [:inserted_at])
  end
end
