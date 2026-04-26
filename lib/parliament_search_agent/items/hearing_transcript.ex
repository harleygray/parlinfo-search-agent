defmodule ParliamentSearchAgent.Items.HearingTranscript do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @parlinfo_display_base "https://parlinfo.aph.gov.au/parlInfo/search/display/display.w3p"

  schema "hearing_transcripts" do
    field :parlinfo_id, :string
    field :parlinfo_ids, {:array, :string}, default: []
    field :title, :string
    field :date_tabled, :date
    field :committee_name, :string
    field :chamber, :string
    field :parliament_number, :integer
    field :pdf_url, :string
    field :source_url, :string
    field :parlinfo_permalink, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(transcript, attrs) do
    transcript
    |> cast(attrs, [
      :parlinfo_id,
      :parlinfo_ids,
      :title,
      :date_tabled,
      :committee_name,
      :chamber,
      :parliament_number,
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
end
