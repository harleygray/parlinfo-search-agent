defmodule ParlInfoSearchAgent.Repo.Migrations.UpdateReportsFields do
  use Ecto.Migration

  def up do
    alter table(:reports) do
      remove :parliament_number
      add :date_referred, :naive_datetime
      add :inquiry_name, :string
    end

    execute "ALTER TABLE reports ALTER COLUMN date_tabled TYPE timestamp USING date_tabled::timestamp"
  end

  def down do
    execute "ALTER TABLE reports ALTER COLUMN date_tabled TYPE date USING date_tabled::date"

    alter table(:reports) do
      remove :date_referred
      remove :inquiry_name
      add :parliament_number, :integer
    end
  end
end
