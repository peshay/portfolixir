defmodule Portfolixir.News.DigestConsumer do
  @moduledoc """
  A named reader of the digest and its confirmed position (ADR-0056 §9;
  Sprint 28, N3). See `Portfolixir.News.DigestCursor`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.News.Label

  @type t :: %__MODULE__{}

  schema "news_digest_consumers" do
    field(:name, :string)
    field(:position, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  A new consumer: its `name`, an identifier of a label's shape (1 to 64
  letters, digits or `. _ : / @ + -`, starting with a letter or a digit),
  and its starting `position`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(consumer, attrs) do
    consumer
    |> cast(attrs, [:name, :position])
    |> validate_required([:name, :position])
    |> Text.validate(:name, max: 64)
    |> validate_change(:name, fn :name, name ->
      if Label.identifier?(name), do: [], else: [name: "is not an identifier"]
    end)
    |> unique_constraint(:name)
    |> check_constraint(:name, name: :news_digest_consumers_name_check, message: "is invalid")
  end
end
