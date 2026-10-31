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
  page's own renderer to translate through the `errors` domain and fill from
  the same bindings (German since #1191). Any other message passes through
  unchanged.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  # The screen's sentences go through the `errors` domain with the page's
  # other refusals, so they read German on the German screen (#1191, Sprint
  # 21 board 08); the agent's sentences, the keys, stay untranslated. Written
  # out, one per noun, for the extractor to see each msgid.
  @sentences %{
    "is still the current ISIN of security #%{security_id}" =>
      dgettext_noop(
        "errors",
        ~s|is still the current ISIN of "%{security_name}" (security #%{security_id})|
      ),
    "is already the current ISIN of security #%{security_id}" =>
      dgettext_noop(
        "errors",
        ~s|is already the current ISIN of "%{security_name}" (security #%{security_id})|
      ),
    "is recorded as a former ISIN of security #%{security_id}" =>
      dgettext_noop(
        "errors",
        ~s|is recorded as a former ISIN of "%{security_name}" (security #%{security_id})|
      ),
    ("is recorded as a former ISIN of security #%{security_id}; delete that alias " <>
       "or record an ISIN change instead") =>
      dgettext_noop(
        "errors",
        ~s|is recorded as a former ISIN of "%{security_name}" (security #%{security_id}); delete that alias or record an ISIN change instead|
      ),
    ("is a former name of cash account #%{holder_id}: an import naming it books " <>
       "there. Remove it from that account's former names first") =>
      dgettext_noop(
        "errors",
        ~s|is a former name of cash account #%{holder_id} ("%{holder_name}"): an import naming it books there. Remove it from that account's former names first|
      ),
    ("is a former name of securities account #%{holder_id}: an import naming it books " <>
       "there. Remove it from that account's former names first") =>
      dgettext_noop(
        "errors",
        ~s|is a former name of securities account #%{holder_id} ("%{holder_name}"): an import naming it books there. Remove it from that account's former names first|
      ),
    "include the name of cash account #%{holder_id} in this portfolio" =>
      dgettext_noop(
        "errors",
        ~s|include "%{former_name}", the name of cash account #%{holder_id} in this portfolio|
      ),
    "include a former name of cash account #%{holder_id} in this portfolio" =>
      dgettext_noop(
        "errors",
        ~s|include "%{former_name}", a former name of cash account #%{holder_id} in this portfolio|
      ),
    "include the name of securities account #%{holder_id} in this portfolio" =>
      dgettext_noop(
        "errors",
        ~s|include "%{former_name}", the name of securities account #%{holder_id} in this portfolio|
      ),
    "include a former name of securities account #%{holder_id} in this portfolio" =>
      dgettext_noop(
        "errors",
        ~s|include "%{former_name}", a former name of securities account #%{holder_id} in this portfolio|
      )
  }

  @doc """
  The screen's message for a changeset error: the sentence the screen showed
  for a refusal that names another record, its bindings unchanged, or the
  error as it is.
  """
  @spec screen({String.t(), keyword()}) :: {String.t(), keyword()}
  def screen({message, opts}) when is_binary(message) and is_list(opts),
    do: {Map.get(@sentences, message, message), opts}
end
