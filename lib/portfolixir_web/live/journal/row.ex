defmodule PortfolixirWeb.Journal.Row do
  @moduledoc """
  One audit-journal entry as the Audit journal page reads it (Sprint 23 V3,
  idea U2; board `ux-design-2026-11-02-sprint23/03-journal`, pick Q5 = A).

  The entry is `Portfolixir.Journal.Entry` as `GET /api/v1/journal` answers
  it; this module only puts it into words: the time in UTC, the actor and
  the operation in the operator's words, and the entry as its kind, its id
  and its stored name. A raw code never reaches the screen where a word
  exists; a kind no label knows yet reads as its stored code, because the
  code is the stable name ADR-0017 gives it.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Journal.Entry
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Journal.Change
  alias PortfolixirWeb.TransactionKindLabel

  # Every `resource_type` code a journaled writer files under, in the order
  # the kind select offers them.
  @kinds ~w(transaction security security_quotes security_event security_note
            security_identifier_alias security_category_assignment cash_account
            securities_account cash_account_bucket_assignment depot_bucket_assignment
            position_bucket_override portfolio bucket view classification category
            target target_plan policy_rule policy_rule_version snapshot
            tax_statement_snapshot tax_profile tax_parameters allowance_order setting
            merge_record retired_import_hash)

  @doc "The `resource_type` codes the kind select offers."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "The row the page renders for `entry`."
  @spec build(Entry.t()) :: map()
  def build(%Entry{} = entry) do
    %{
      id: entry.id,
      time: time(entry.inserted_at),
      actor: actor_label(entry.actor_type),
      actor_name: entry.actor_label,
      operation: operation_label(entry.operation),
      resource_type: entry.resource_type,
      resource_id: entry.resource_id,
      entity: entity(entry),
      href: href(entry),
      change: Change.build(entry)
    }
  end

  @doc "The time of an entry, in UTC to the second: `02.11.2026 18:00:23`."
  @spec time(DateTime.t()) :: String.t()
  def time(%DateTime{} = at) do
    utc = DateTime.shift_zone!(at, "Etc/UTC")
    Format.date(DateTime.to_date(utc)) <> " " <> Calendar.strftime(utc, "%H:%M:%S")
  end

  @doc "The actor in the operator's words (G12.1-A: a token writes as the agent)."
  @spec actor_label(atom()) :: String.t()
  def actor_label(:owner_ui), do: gettext("Operator")
  def actor_label(type) when type in [:api_token_rw, :api_token_ro], do: gettext("Agent")
  def actor_label(:import_session), do: gettext("Import")
  def actor_label(:system_job), do: gettext("System")

  @doc "The operation in the operator's words."
  @spec operation_label(atom()) :: String.t()
  def operation_label(:create), do: gettext("Created")
  def operation_label(:update), do: gettext("Changed")
  def operation_label(:delete), do: gettext("Deleted")
  def operation_label(:upsert), do: gettext("Created or replaced")

  @doc "A kind (`resource_type`) in the operator's words; an unknown code as itself."
  @spec kind_label(String.t()) :: String.t()
  def kind_label("transaction"), do: gettext("Transaction")
  def kind_label("security"), do: gettext("Security")
  def kind_label("security_quotes"), do: gettext("Quotes")
  def kind_label("security_event"), do: pgettext("journal kind", "Security event")
  def kind_label("security_note"), do: pgettext("journal kind", "Research note")
  def kind_label("security_identifier_alias"), do: gettext("Former ISIN")

  def kind_label("security_category_assignment"),
    do: pgettext("journal kind", "Category assignment")

  def kind_label("cash_account"), do: gettext("Cash account")
  def kind_label("securities_account"), do: gettext("Depot")

  def kind_label("cash_account_bucket_assignment"),
    do: pgettext("journal kind", "Cash account buckets")

  def kind_label("depot_bucket_assignment"), do: pgettext("journal kind", "Depot buckets")
  def kind_label("position_bucket_override"), do: pgettext("journal kind", "Position buckets")
  def kind_label("portfolio"), do: gettext("Portfolio")
  def kind_label("bucket"), do: gettext("Bucket")
  def kind_label("view"), do: gettext("View")
  def kind_label("classification"), do: gettext("Classification")
  def kind_label("category"), do: gettext("Category")
  def kind_label("target"), do: pgettext("journal kind", "Target weight")
  def kind_label("target_plan"), do: pgettext("journal kind", "Target plan")
  def kind_label("policy_rule"), do: gettext("Rule")
  def kind_label("policy_rule_version"), do: pgettext("journal kind", "Rule version")
  def kind_label("snapshot"), do: pgettext("journal kind", "Snapshot")
  def kind_label("tax_statement_snapshot"), do: pgettext("journal kind", "Recorded statement")
  def kind_label("tax_profile"), do: pgettext("journal kind", "Tax profile")
  def kind_label("tax_parameters"), do: pgettext("journal kind", "Tax parameters")
  def kind_label("allowance_order"), do: pgettext("journal kind", "Allowance order")
  def kind_label("setting"), do: pgettext("journal kind", "Setting")
  def kind_label("merge_record"), do: pgettext("journal kind", "Merge")
  def kind_label("retired_import_hash"), do: pgettext("journal kind", "Retired import row")
  def kind_label(code) when is_binary(code), do: code

  # The entry as its kind, its id and its stored name: "Regel 9 · Barreserve
  # höchstens 30 %". The name is read from the image that holds the record:
  # the after-image, or the before-image of a delete.
  defp entity(%Entry{} = entry) do
    head =
      Enum.join(Enum.reject([kind_label(entry.resource_type), entry.resource_id], &is_nil/1), " ")

    case name(entry.resource_type, image(entry)) do
      nil -> head
      name -> head <> " · " <> name
    end
  end

  defp image(%Entry{operation: :delete, before: before}) when is_map(before), do: before
  defp image(%Entry{after: after_image}) when is_map(after_image), do: after_image
  defp image(%Entry{before: before}) when is_map(before), do: before
  defp image(_entry), do: %{}

  # A booking has no name: its kind and its date say which it is.
  defp name("transaction", %{"type" => type} = image) do
    kind = if type in Transaction.kinds(), do: TransactionKindLabel.label(type), else: type

    case BoundedDate.parse(image["date"]) do
      {:ok, date} -> kind <> " " <> Format.date(date)
      _no_date -> kind
    end
  end

  defp name(_kind, %{"name" => name}) when is_binary(name) and name != "", do: name
  defp name(_kind, _image), do: nil

  # The page an entry is read on, where it has one (board 03: a rule on
  # Risk, an account on Accounts & depots, a statement on Tax). A booking has
  # no page of its own (found while drawing 6), so it links the history. A
  # deleted entry has no page and reads as text.
  defp href(%Entry{operation: :delete}), do: nil

  defp href(%Entry{resource_type: type, resource_id: id} = entry),
    do: page(type, id, image(entry))

  defp page("security", id, _image), do: "/securities/#{id}"
  defp page("security_quotes", id, _image), do: "/securities/#{id}"

  defp page(type, _id, %{"security_id" => security_id})
       when type in ~w(security_event security_note security_identifier_alias
                       security_category_assignment) and is_integer(security_id),
       do: "/securities/#{security_id}"

  defp page(type, _id, _image)
       when type in ~w(cash_account securities_account cash_account_bucket_assignment
                       depot_bucket_assignment position_bucket_override),
       do: "/portfolios"

  defp page("merge_record", id, _image), do: "/portfolios?merge=#{id}#merge-records"
  defp page("transaction", _id, _image), do: "/transactions"
  defp page(type, _id, _image) when type in ~w(bucket view), do: "/buckets"
  defp page("classification", id, _image), do: "/classifications/#{id}"

  defp page("category", _id, %{"classification_id" => classification_id})
       when is_integer(classification_id),
       do: "/classifications/#{classification_id}"

  defp page(type, _id, _image) when type in ~w(target target_plan),
    do: "/portfolio?tab=allocation"

  defp page(type, _id, _image) when type in ~w(policy_rule policy_rule_version), do: "/risk"
  defp page("snapshot", id, _image), do: "/snapshots?snapshot=#{id}"

  defp page(type, _id, _image)
       when type in ~w(tax_statement_snapshot tax_profile tax_parameters allowance_order),
       do: "/tax"

  defp page(_type, _id, _image), do: nil
end
