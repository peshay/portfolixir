defmodule PortfolixirWeb.NamedRecordRefusal do
  @moduledoc """
  The operator's sentence for a refusal that names another record (#965).

  The domain names that record by its kind and id in the sentence the API and
  the MCP companion answer ("is already the current ISIN of security #12"),
  and carries its stored name only as data (`security_name`, `holder_name`,
  `former_name`), so a name that reads like an instruction never sits inside
  the app's own words for an agent (F75's rule, E25 S7). The ISIN-change and
  alias writes (`Portfolixir.Catalog.IdentifierAliases`) and the account
  name guard (`Portfolixir.Lifecycle.AccountNames`) refuse this way.

  The operator's screens keep the sentence they showed before, the stored
  name in it: `screen/1` swaps such a message for that sentence, for the
  page's own renderer to fill from the same bindings. Any other message
  passes through unchanged.
  """

  @nouns ["cash account", "securities account"]

  @sentences Map.merge(
               %{
                 "is still the current ISIN of security #%{security_id}" =>
                   ~s|is still the current ISIN of "%{security_name}" (security #%{security_id})|,
                 "is already the current ISIN of security #%{security_id}" =>
                   ~s|is already the current ISIN of "%{security_name}" (security #%{security_id})|,
                 "is recorded as a former ISIN of security #%{security_id}" =>
                   ~s|is recorded as a former ISIN of "%{security_name}" (security #%{security_id})|,
                 ("is recorded as a former ISIN of security #%{security_id}; delete that alias " <>
                    "or record an ISIN change instead") =>
                   ~s|is recorded as a former ISIN of "%{security_name}" (security #%{security_id}); | <>
                     "delete that alias or record an ISIN change instead"
               },
               Map.new(
                 for noun <- @nouns,
                     {message, sentence} <- [
                       {"is a former name of #{noun} #%{holder_id}: an import naming it books " <>
                          "there. Remove it from that account's former names first",
                        ~s|is a former name of #{noun} #%{holder_id} ("%{holder_name}"): an import | <>
                          "naming it books there. Remove it from that account's former names first"},
                       {"include the name of #{noun} #%{holder_id} in this portfolio",
                        ~s|include "%{former_name}", the name of #{noun} #%{holder_id} in this | <>
                          "portfolio"},
                       {"include a former name of #{noun} #%{holder_id} in this portfolio",
                        ~s|include "%{former_name}", a former name of #{noun} #%{holder_id} in | <>
                          "this portfolio"}
                     ],
                     do: {message, sentence}
               )
             )

  @doc """
  The screen's message for a changeset error: the sentence the screen showed
  for a refusal that names another record, its bindings unchanged, or the
  error as it is.
  """
  @spec screen({String.t(), keyword()}) :: {String.t(), keyword()}
  def screen({message, opts}) when is_binary(message) and is_list(opts),
    do: {Map.get(@sentences, message, message), opts}
end
