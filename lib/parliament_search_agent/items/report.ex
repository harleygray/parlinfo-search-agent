defmodule ParliamentSearchAgent.Items.Report do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @parlinfo_display_base "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p"

  schema "reports" do
    field :parlinfo_id, :string
    field :parlinfo_ids, {:array, :string}, default: []
    field :title, :string
    field :date_tabled, :naive_datetime
    field :date_referred, :naive_datetime
    field :committee_name, :string
    field :inquiry_name, :string
    field :report_type, :string
    field :pdf_url, :string
    field :source_url, :string
    field :parlinfo_permalink, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(report, attrs) do
    report
    |> cast(normalize_dates(attrs), [
      :parlinfo_id,
      :parlinfo_ids,
      :title,
      :date_tabled,
      :date_referred,
      :committee_name,
      :inquiry_name,
      :report_type,
      :pdf_url,
      :source_url
    ])
    |> parse_title()
    |> validate_required([:parlinfo_id, :title, :source_url])
    |> unique_constraint(:parlinfo_id)
    |> put_parlinfo_permalink()
  end

  defp parse_title(changeset) do
    case get_change(changeset, :title) do
      nil ->
        changeset

      raw ->
        parsed =
          raw
          |> String.split(" : ")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&(&1 != ""))
          |> List.last()
          |> String.trim_trailing(":")
          |> String.trim()

        if parsed != "", do: put_change(changeset, :title, parsed), else: changeset
    end
  end

  defp put_parlinfo_permalink(changeset) do
    case get_field(changeset, :parlinfo_id) do
      nil ->
        changeset

      id ->
        encoded = URI.encode(id <> "/0000", &URI.char_unreserved?/1)

        put_change(
          changeset,
          :parlinfo_permalink,
          "#{@parlinfo_display_base};query=Id%3A%22#{encoded}%22"
        )
    end
  end

  # Ecto's NaiveDateTime.cast requires a full datetime string; promote bare dates.
  defp normalize_dates(attrs) do
    Enum.reduce(["date_tabled", "date_referred"], attrs, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) and byte_size(value) == 10 ->
          Map.put(acc, key, value <> "T00:00:00")

        _ ->
          acc
      end
    end)
  end
end
