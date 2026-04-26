defmodule ParliamentSearchAgent.Items.Broadcast do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "broadcasts" do
    field :parlview_id, :string
    field :title, :string
    field :chamber, :string
    field :is_live, :boolean, default: false
    field :start_time, :naive_datetime
    field :duration, :string
    field :source_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(broadcast, attrs) do
    broadcast
    |> cast(normalize_datetimes(attrs), [
      :parlview_id,
      :title,
      :chamber,
      :is_live,
      :start_time,
      :duration,
      :source_url
    ])
    |> validate_required([:title, :source_url])
    |> unique_constraint(:parlview_id)
  end

  defp normalize_datetimes(attrs) do
    Enum.reduce(["start_time"], attrs, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) and byte_size(value) == 10 ->
          Map.put(acc, key, value <> "T00:00:00")

        _ ->
          acc
      end
    end)
  end
end
