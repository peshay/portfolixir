defmodule PortfolixirWeb.Api.V1.NewsIdentityParam do
  @moduledoc """
  A security's news identity on `PATCH /api/v1/securities/:id` and, since
  the closing act (SEC4), on `POST /api/v1/securities` (ADR-0056 §2, §9, B1;
  Sprint 27, N8): `news_identity` {`cik`, `aliases`} and `news_watch`.

  The API spells the identity as one block; the security stores it as
  `news_cik` and `news_aliases` (`Portfolixir.Catalog.Security`). `parse/1`
  turns the block into those attributes, a key not sent keeping its stored
  value, and `errors/1` turns the changeset's errors on them back into the
  block's names, so a refusal names what the request sent.

  The block is closed: a key of `news_identity` other than `cik` and
  `aliases`, a key of an alias other than `token`, `context` and `case`, and
  the stored names `news_cik` and `news_aliases` sent directly answer 422
  naming them; a `news_identity` that is not an object answers 422 on it.
  """

  alias PortfolixirWeb.Api.V1.ClosedBody

  @identity_fields ~w(cik aliases)
  @alias_fields ~w(token context case)

  @doc """
  The security attributes with `news_identity` turned into `news_cik` and
  `news_aliases`: `{:ok, attrs}`, or `{:error, errors}` naming what is
  refused.
  """
  @spec parse(map()) :: {:ok, map()} | {:error, map()}
  def parse(attrs) when is_map(attrs) do
    with :ok <- refuse_stored_names(attrs) do
      case Map.pop(attrs, "news_identity", :absent) do
        {:absent, attrs} -> {:ok, attrs}
        {%{} = identity, attrs} when not is_struct(identity) -> identity(identity, attrs)
        {_not_an_object, _attrs} -> {:error, %{"news_identity" => ["must be an object"]}}
      end
    end
  end

  def parse(attrs), do: {:ok, attrs}

  defp refuse_stored_names(attrs) do
    case Map.take(attrs, ["news_cik", "news_aliases"]) do
      empty when empty == %{} ->
        :ok

      sent ->
        {:error,
         Map.new(sent, fn {key, _value} ->
           {key, ["is unknown: write it as news_identity.#{String.replace(key, "news_", "")}"]}
         end)}
    end
  end

  defp identity(identity, attrs) do
    unknown = ClosedBody.unknown(identity, @identity_fields, "news_identity")
    aliases = alias_errors(identity["aliases"])

    errors =
      if aliases == nil, do: unknown, else: Map.put(unknown, "aliases", aliases)

    if errors == %{} do
      {:ok,
       attrs
       |> put_present(identity, "cik", "news_cik")
       |> put_present(identity, "aliases", "news_aliases")}
    else
      {:error, %{"news_identity" => errors}}
    end
  end

  # One map per alias, as a changeset renders an embed's errors; nil when no
  # alias carries an unknown key (a malformed list is the changeset's).
  defp alias_errors(aliases) when is_list(aliases) do
    errors =
      Enum.map(aliases, fn
        %{} = entry when not is_struct(entry) ->
          ClosedBody.unknown(entry, @alias_fields, "an alias")

        _other ->
          %{}
      end)

    if Enum.all?(errors, &(&1 == %{})), do: nil, else: errors
  end

  defp alias_errors(_aliases), do: nil

  defp put_present(attrs, identity, key, stored) do
    case Map.fetch(identity, key) do
      {:ok, value} -> Map.put(attrs, stored, value)
      :error -> attrs
    end
  end

  @doc """
  A security changeset's errors (as `PortfolixirWeb.Api.V1.JSON.errors/1`
  renders them) with `news_cik` and `news_aliases` under `news_identity` as
  `cik` and `aliases`.
  """
  @spec errors(map()) :: map()
  def errors(errors) when is_map(errors) do
    {cik, errors} = Map.pop(errors, :news_cik)
    {aliases, errors} = Map.pop(errors, :news_aliases)

    identity =
      [cik: cik, aliases: aliases]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    if identity == %{}, do: errors, else: Map.put(errors, :news_identity, identity)
  end
end
