defmodule PortfolixirWeb.PortfolioAccounts.NameConflict do
  @moduledoc """
  A cash account's or a depot's name another account of its kind already
  answers to (ADR-0050 §4), refused at the field in the operator's language:
  the rename dialog's words (DESIGN.md G1-A, board 14 ⑤), which the account
  create dialog shares since #921 (Sprint 18 pick H8.3).

  The domain's message (`Portfolixir.Lifecycle.AccountNames`) names the
  holder by its internal number and stays English for the API and MCP; a
  form reads the conflict itself (`AccountNames.conflict/4`) and states it
  here, naming the holder by its name, impersonally (EXPERIENCE.md, Voice
  and Tone: no "Sie").
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Lifecycle.AccountNames

  @doc """
  The refusal of `name` for an account of `kind` (`"cash"` or `"depot"`,
  stored as `schema`) in `portfolio_id`, other than `except_id` (`nil` for
  a new account): `nil` when the name is free.
  """
  @spec message(String.t(), module(), integer() | nil, String.t(), integer() | nil) ::
          String.t() | nil
  def message(kind, schema, portfolio_id, name, except_id)
      when kind in ["cash", "depot"] and is_binary(name) do
    case AccountNames.conflict(schema, portfolio_id, name, except_id) do
      nil -> nil
      {:former, holder} -> former(name, holder.name)
      {:live, _holder} -> live(kind, name)
    end
  end

  defp former(name, holder) do
    gettext(
      "“%{name}” is a former name of “%{holder}”: an import under this name books there. Choose another name or remove it from “%{holder}”.",
      name: name,
      holder: holder
    )
  end

  defp live("cash", name),
    do:
      gettext(
        "“%{name}” is already the name of another cash account. Choose another name, or merge or rename that account.",
        name: name
      )

  defp live("depot", name),
    do:
      gettext(
        "“%{name}” is already the name of another depot. Choose another name, or merge or rename that depot.",
        name: name
      )
end
