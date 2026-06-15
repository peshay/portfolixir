defmodule Portfolixir.Actor do
  @moduledoc """
  Who performed a financial write (ADR-0016, FR-28).

  An `Actor` is the first positional argument of every public context write
  function. The `type` is a closed taxonomy; extending it is an amendment to
  ADR-0016, not an ad-hoc addition. `label` is optional free-form attribution
  (e.g. the API-token identity or the import session id) recorded alongside the
  type in the audit journal.

  Smuggling the actor through the process dictionary is forbidden — it is always
  passed explicitly.
  """

  @type type :: :owner_ui | :api_token_rw | :api_token_ro | :import_session | :system_job

  @type t :: %__MODULE__{type: type(), label: String.t() | nil}

  @types ~w(owner_ui api_token_rw api_token_ro import_session system_job)a

  @enforce_keys [:type]
  defstruct [:type, :label]

  @doc "The closed actor-type taxonomy."
  @spec types() :: [type()]
  def types, do: @types

  @doc """
  Builds an actor of a known type with an optional label.

  Raises `ArgumentError` for a type outside the taxonomy so a typo fails loudly
  rather than producing an unattributable journal entry.
  """
  @spec new(type(), String.t() | nil) :: t()
  def new(type, label \\ nil)

  def new(type, label) when type in @types and (is_binary(label) or is_nil(label)) do
    %__MODULE__{type: type, label: label}
  end

  def new(type, _label) do
    raise ArgumentError,
          "unknown actor type #{inspect(type)}; allowed: #{inspect(@types)}"
  end

  @doc "The interactive owner acting through the LiveView UI."
  @spec owner_ui() :: t()
  def owner_ui, do: %__MODULE__{type: :owner_ui}

  @doc "A read-write API/MCP token; `label` identifies the token if known."
  @spec api_token_rw(String.t() | nil) :: t()
  def api_token_rw(label \\ nil), do: %__MODULE__{type: :api_token_rw, label: label}

  @doc "A read-only API/MCP token; `label` identifies the token if known."
  @spec api_token_ro(String.t() | nil) :: t()
  def api_token_ro(label \\ nil), do: %__MODULE__{type: :api_token_ro, label: label}

  @doc "A bulk import session; `label` identifies the source file/run."
  @spec import_session(String.t() | nil) :: t()
  def import_session(label \\ nil), do: %__MODULE__{type: :import_session, label: label}

  @doc "A background system job (sync schedulers etc.)."
  @spec system_job(String.t() | nil) :: t()
  def system_job(label \\ nil), do: %__MODULE__{type: :system_job, label: label}

  @doc """
  Splits an actor into the `{actor_type, actor_label}` strings stored in the
  journal. `actor_type` is the atom rendered as a string code.
  """
  @spec to_columns(t()) :: {String.t(), String.t() | nil}
  def to_columns(%__MODULE__{type: type, label: label}), do: {Atom.to_string(type), label}
end
