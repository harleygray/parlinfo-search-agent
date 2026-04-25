defmodule ParlInfoSearchAgent.Items do
  import Ecto.Query
  alias ParlInfoSearchAgent.Repo
  alias ParlInfoSearchAgent.Items.{Report, Broadcast, HearingTranscript}

  # ---------------------------------------------------------------------------
  # Listing / querying
  # ---------------------------------------------------------------------------

  def list_items(params \\ %{}) do
    page =
      case Integer.parse(to_string(params["page"] || "1")) do
        {n, _} -> max(n, 1)
        :error -> 1
      end

    per_page =
      case Integer.parse(to_string(params["per_page"] || "20")) do
        {n, _} -> min(max(n, 1), 100)
        :error -> 20
      end

    offset = (page - 1) * per_page

    dataset = params["dataset"]
    from_date = params["from"]
    to_date = params["to"]

    {items, total} =
      case dataset do
        "reports" ->
          q =
            Report
            |> filter_from(from_date)
            |> filter_to(to_date)
            |> order_by([i], [desc_nulls_last: i.date_tabled, desc: i.inserted_at])

          {Repo.all(q |> limit(^per_page) |> offset(^offset)), Repo.aggregate(q, :count, :id)}

        "broadcasts" ->
          q =
            Broadcast
            |> filter_broadcast_from(from_date)
            |> filter_broadcast_to(to_date)
            |> order_by([i], [desc_nulls_last: i.start_time, desc: i.inserted_at])

          {Repo.all(q |> limit(^per_page) |> offset(^offset)), Repo.aggregate(q, :count, :id)}

        "hearing_transcripts" ->
          q =
            HearingTranscript
            |> filter_from(from_date)
            |> filter_to(to_date)
            |> order_by([i], [desc_nulls_last: i.date_tabled, desc: i.inserted_at])

          {Repo.all(q |> limit(^per_page) |> offset(^offset)), Repo.aggregate(q, :count, :id)}

        _ ->
          all = merge_all(from_date, to_date)
          total = length(all)
          page_items = all |> Enum.drop(offset) |> Enum.take(per_page)
          {page_items, total}
      end

    %{items: items, total: total, page: page, per_page: per_page}
  end

  def get_item!(id) do
    Repo.get(Report, id) ||
      Repo.get(Broadcast, id) ||
      Repo.get(HearingTranscript, id) ||
      raise Ecto.NoResultsError, queryable: Report
  end

  def get_latest(limit \\ 20, dataset \\ nil) do
    limit = min(limit, 100)

    case dataset do
      "reports" ->
        Repo.all(from r in Report, order_by: [desc: r.date_tabled], limit: ^limit)

      "broadcasts" ->
        Repo.all(from b in Broadcast, order_by: [desc_nulls_last: b.start_time], limit: ^limit)

      "hearing_transcripts" ->
        Repo.all(from h in HearingTranscript, order_by: [desc: h.date_tabled], limit: ^limit)

      _ ->
        merge_all(nil, nil) |> Enum.take(limit)
    end
  end

  def get_by_parlinfo_id(schema, parlinfo_id) do
    Repo.get_by(schema, parlinfo_id: parlinfo_id)
  end

  def get_broadcast_by_parlview_id(parlview_id) do
    Repo.get_by(Broadcast, parlview_id: parlview_id)
  end

  # ---------------------------------------------------------------------------
  # Upserts
  # ---------------------------------------------------------------------------

  def upsert_report(attrs) do
    do_upsert_sectioned(Report, attrs)
  end

  def upsert_broadcast(attrs) do
    parlview_id = attrs["parlview_id"] || attrs[:parlview_id]

    existing = parlview_id && Repo.get_by(Broadcast, parlview_id: parlview_id)

    if existing do
      {:ok, :existing}
    else
      struct(Broadcast)
      |> Broadcast.changeset(stringify_keys(attrs))
      |> Repo.insert()
      |> case do
        {:ok, record} ->
          Phoenix.PubSub.broadcast(ParlInfoSearchAgent.PubSub, "items:new", {:new_item, record})
          {:ok, :new, record}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def upsert_hearing_transcript(attrs) do
    do_upsert_sectioned(HearingTranscript, attrs)
  end

  # ---------------------------------------------------------------------------
  # Updates (for enriching with detail-page data)
  # ---------------------------------------------------------------------------

  def update_report(report, attrs) do
    report
    |> Report.changeset(stringify_keys(attrs))
    |> Repo.update()
    |> tap_broadcast_update()
  end

  def update_broadcast(broadcast, attrs) do
    broadcast
    |> Broadcast.changeset(stringify_keys(attrs))
    |> Repo.update()
    |> tap_broadcast_update()
  end

  def update_hearing_transcript(transcript, attrs) do
    transcript
    |> HearingTranscript.changeset(stringify_keys(attrs))
    |> Repo.update()
    |> tap_broadcast_update()
  end

  defp tap_broadcast_update({:ok, record} = result) do
    Phoenix.PubSub.broadcast(ParlInfoSearchAgent.PubSub, "items:updated", {:updated_item, record})
    result
  end

  defp tap_broadcast_update(error), do: error

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Used by upsert_report and upsert_hearing. Collapses ParlInfo's per-section entries
  # into one row per document. The incoming parlinfo_id is the section-level ID
  # (e.g. "committees/reportsen/RB000727/0013"). We strip the last path segment to get
  # the doc-level ID and store the section ID in the parlinfo_ids array.
  defp do_upsert_sectioned(schema, attrs) do
    section_id = attrs["parlinfo_id"] || attrs[:parlinfo_id]

    if is_nil(section_id) do
      struct(schema)
      |> schema.changeset(stringify_keys(attrs))
      |> Repo.insert()
      |> case do
        {:ok, record} ->
          Phoenix.PubSub.broadcast(ParlInfoSearchAgent.PubSub, "items:new", {:new_item, record})
          {:ok, :new, record}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      do_upsert_sectioned_with_id(schema, attrs, section_id)
    end
  end

  defp do_upsert_sectioned_with_id(schema, attrs, section_id) do
    did = doc_id(section_id)

    case Repo.get_by(schema, parlinfo_id: did) do
      nil ->
        struct(schema)
        |> schema.changeset(
          attrs
          |> stringify_keys()
          |> Map.merge(%{"parlinfo_id" => did, "parlinfo_ids" => [section_id]})
        )
        |> Repo.insert()
        |> case do
          {:ok, record} ->
            Phoenix.PubSub.broadcast(ParlInfoSearchAgent.PubSub, "items:new", {:new_item, record})
            {:ok, :new, record}

          {:error, changeset} ->
            {:error, changeset}
        end

      existing ->
        unless section_id in existing.parlinfo_ids do
          existing
          |> schema.changeset(%{"parlinfo_ids" => [section_id | existing.parlinfo_ids]})
          |> Repo.update()
        end

        {:ok, :existing}
    end
  end

  defp doc_id(section_parlinfo_id) do
    case String.split(section_parlinfo_id, "/") do
      [_single] -> section_parlinfo_id
      parts -> parts |> Enum.drop(-1) |> Enum.join("/")
    end
  end

  defp merge_all(from_date, to_date) do
    reports = Repo.all(Report |> filter_from(from_date) |> filter_to(to_date))

    broadcasts =
      Repo.all(Broadcast |> filter_broadcast_from(from_date) |> filter_broadcast_to(to_date))

    transcripts = Repo.all(HearingTranscript |> filter_from(from_date) |> filter_to(to_date))

    (reports ++ broadcasts ++ transcripts)
    |> Enum.sort_by(&item_sort_date/1, :desc)
  end

  defp item_sort_date(%Report{date_tabled: nil}), do: ""
  defp item_sort_date(%Report{date_tabled: d}), do: Date.to_iso8601(d)
  defp item_sort_date(%HearingTranscript{date_tabled: nil}), do: ""
  defp item_sort_date(%HearingTranscript{date_tabled: d}), do: Date.to_iso8601(d)
  defp item_sort_date(%Broadcast{start_time: nil}), do: ""
  defp item_sort_date(%Broadcast{start_time: dt}), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp filter_from(query, nil), do: query
  defp filter_from(query, ""), do: query

  defp filter_from(query, from_date) do
    case Date.from_iso8601(from_date) do
      {:ok, date} -> where(query, [i], fragment("?::date", i.date_tabled) >= ^date)
      _ -> query
    end
  end

  defp filter_to(query, nil), do: query
  defp filter_to(query, ""), do: query

  defp filter_to(query, to_date) do
    case Date.from_iso8601(to_date) do
      {:ok, date} -> where(query, [i], fragment("?::date", i.date_tabled) <= ^date)
      _ -> query
    end
  end

  defp filter_broadcast_from(query, nil), do: query
  defp filter_broadcast_from(query, ""), do: query

  defp filter_broadcast_from(query, from_date) do
    case Date.from_iso8601(from_date) do
      {:ok, date} -> where(query, [i], fragment("?::date", i.start_time) >= ^date)
      _ -> query
    end
  end

  defp filter_broadcast_to(query, nil), do: query
  defp filter_broadcast_to(query, ""), do: query

  defp filter_broadcast_to(query, to_date) do
    case Date.from_iso8601(to_date) do
      {:ok, date} -> where(query, [i], fragment("?::date", i.start_time) <= ^date)
      _ -> query
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
