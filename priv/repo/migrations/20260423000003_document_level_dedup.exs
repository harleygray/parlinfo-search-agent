defmodule ParliamentSearchAgent.Repo.Migrations.DocumentLevelDedup do
  use Ecto.Migration

  def change do
    # --- reports ---
    alter table(:reports) do
      add :parlinfo_ids, {:array, :string}, null: false, default: []
    end

    # Collect all section-level IDs into the /0000 root row for each document
    execute("""
    UPDATE reports r
    SET parlinfo_ids = (
      SELECT array_agg(r2.parlinfo_id ORDER BY r2.parlinfo_id)
      FROM reports r2
      WHERE regexp_replace(r2.parlinfo_id, '/[^/]+$', '') =
            regexp_replace(r.parlinfo_id, '/[^/]+$', '')
    )
    WHERE r.parlinfo_id LIKE '%/0000'
    """)

    # Remove all non-root section rows
    execute("DELETE FROM reports WHERE parlinfo_id NOT LIKE '%/0000'")

    # Strip the /0000 suffix so parlinfo_id stores the doc-level ID
    execute("UPDATE reports SET parlinfo_id = regexp_replace(parlinfo_id, '/0000$', '')")

    alter table(:reports) do
      remove :summary
    end

    # --- committee_hearings ---
    alter table(:committee_hearings) do
      add :parlinfo_ids, {:array, :string}, null: false, default: []
    end

    execute("""
    UPDATE committee_hearings r
    SET parlinfo_ids = (
      SELECT array_agg(r2.parlinfo_id ORDER BY r2.parlinfo_id)
      FROM committee_hearings r2
      WHERE regexp_replace(r2.parlinfo_id, '/[^/]+$', '') =
            regexp_replace(r.parlinfo_id, '/[^/]+$', '')
    )
    WHERE r.parlinfo_id LIKE '%/0000'
    """)

    execute("DELETE FROM committee_hearings WHERE parlinfo_id NOT LIKE '%/0000'")

    execute(
      "UPDATE committee_hearings SET parlinfo_id = regexp_replace(parlinfo_id, '/0000$', '')"
    )

    alter table(:committee_hearings) do
      remove :summary
    end
  end

  def down do
    raise "This migration collapses section rows — it cannot be reversed automatically."
  end
end
