defmodule Portfolixir.Imports.ImportSource do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Imports.{ImportRun, RawImportItem}

  schema "import_sources" do
    field(:name, :string)
    field(:type, :string)
    field(:status, :string, default: "active")
    field(:config, :map, default: %{})

    has_many(:import_runs, ImportRun)
    has_many(:raw_import_items, RawImportItem)

    timestamps()
  end

  @doc false
  def changeset(import_source, attrs) do
    import_source
    |> cast(attrs, [:name, :type, :status, :config])
    |> validate_required([:name, :type])
  end
end
