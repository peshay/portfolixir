defmodule Portfolixir.Invariants.ScopeB1NoStoredCredentialsTest do
  use Portfolixir.DataCase, async: true

  # NFR-9 backstop B1 (Sprint 16 Lane N, #885). The gates it backs, as
  # registered in scope_b7_gate_registry_test.exs:
  #   gate:nongoal.order_placing_connection
  #   gate:gated.phase3_readonly_sync
  #
  # User story:
  # As the operator whose instance holds no bank or broker access at all,
  # I want a meta-test that fails the moment any stored structure could hold a
  # credential — a schema field, a virtual field, a table, a column or a
  # settings key —
  # so that neither the order-placing broker connection (a permanent non-goal)
  # nor Phase 3's read-only sync (gated behind its ADR and built-in auth) can
  # arrive through a migration that quietly adds a PIN column.
  #
  # Acceptance criteria:
  # - No Ecto schema field, virtual field or redacted field names a credential.
  # - No table or column of the application's database schema names one.
  # - No settings key names one — nor any other `@*_key` storage constant in
  #   lib/ (session and browser-storage keys are stored too) — and every key
  #   handed to the raw settings store is a literal the scan can read (a
  #   computed key could store any name).
  # - The UI password and the API tokens are environment configuration, never
  #   stored, so nothing is allowlisted for them.
  # - The matcher catches synthetic violations of each kind, so a clean tree
  #   cannot pass vacuously.
  # - An allowlist entry carries a reason and still excuses something real.

  # Name tokens that mean "this holds a credential". A name matches when one of
  # its snake_case / CamelCase tokens is in this list, so `pinned` or `tangent`
  # never match `pin` or `tan`.
  @credential_words ~w(
    password passwords passwd passphrase pwd secret secrets token tokens pin pins
    tan tans otp totp hotp mfa credential credentials login logins logon logons
    username usernames apikey apikeys privkey mnemonic mnemonics
  )

  # Two-token phrases whose single words are innocent on their own (a settings
  # `key`, a PP `online_id`) but mean a credential together.
  @credential_phrases [
    ~w(api key),
    ~w(access key),
    ~w(private key),
    ~w(secret key),
    ~w(signing key),
    ~w(session key),
    ~w(client secret),
    ~w(seed phrase),
    ~w(recovery phrase),
    ~w(recovery code),
    ~w(recovery codes),
    ~w(auth code),
    ~w(online banking)
  ]

  # `{kind, name} => reason`. Empty by design: nothing stored in Portfolixir is
  # a credential. An entry needs a written reason and must still excuse a real
  # name; the UI password and the API tokens live in the environment and never
  # need one.
  @allowlist %{}

  describe "the stored structure" do
    test "no Ecto schema field, virtual field or redacted field names a credential" do
      schemas = app_schemas()

      assert length(schemas) > 10, "the schema scan found too few schemas to be meaningful"

      offenders = schemas |> Enum.flat_map(&schema_names/1) |> reject_allowlisted()

      assert offenders == [],
             "Credential-bearing schema fields (NFR-9 B1; Phase 3 is gated behind " <>
               "its ADR and built-in auth):\n" <> Enum.map_join(offenders, "\n", &inspect/1)
    end

    test "no table or column of the database schema names a credential" do
      rows = database_rows()

      assert Enum.any?(rows, &match?({"transactions", _}, &1)),
             "the structure scan did not see the transactions table"

      offenders = rows |> structure_names() |> reject_allowlisted()

      assert offenders == [],
             "Credential-bearing tables or columns (NFR-9 B1):\n" <>
               Enum.map_join(offenders, "\n", &inspect/1)
    end

    test "every settings key is a literal and none names a credential" do
      {keys, computed} =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.map(&settings_keys(File.read!(&1), &1))
        |> Enum.reduce({[], []}, fn {k, c}, {ks, cs} -> {ks ++ k, cs ++ c} end)

      assert keys != [], "the settings scan found no keys; the extraction is broken"

      assert computed == [],
             "Settings keys must be literals the scan can read (NFR-9 B1):\n" <>
               Enum.join(computed, "\n")

      offenders =
        keys
        |> Enum.filter(&credential_name?/1)
        |> Enum.map(&{:settings_key, &1})
        |> reject_allowlisted()

      assert offenders == [],
             "Credential-bearing settings keys (NFR-9 B1): #{inspect(offenders)}"
    end
  end

  describe "the matcher (self-test: a clean tree cannot pass vacuously)" do
    test "credential names match, innocent neighbours do not" do
      for name <- ~w(password_hash api_token broker_pin tan_list client_secret api_key
                     online_banking_login seed_phrase BrokerCredential totp_secret) do
        assert credential_name?(name), "#{name} should read as a credential"
      end

      for name <- ~w(key online_id import_hash pinned_at tangent isin settlement_amount
                     classification_key TokenizerLabel) do
        refute credential_name?(name), "#{name} should not read as a credential"
      end
    end

    test "a synthetic schema with credential fields is caught" do
      offenders = schema_names(__MODULE__.SyntheticVault)

      assert {:field, "vault_entries", "broker_pin"} in offenders
      assert {:virtual_field, "vault_entries", "api_token"} in offenders
      assert {:redacted_field, "vault_entries", "note"} in offenders
      refute Enum.any?(offenders, &match?({:field, _, "label"}, &1))
    end

    test "synthetic credential tables and columns are caught" do
      rows = [{"bank_logins", "id"}, {"accounts", "online_banking_pin"}, {"accounts", "name"}]

      assert structure_names(rows) == [
               {:table, "bank_logins"},
               {:column, "accounts", "online_banking_pin"}
             ]
    end

    test "synthetic credential settings keys and computed keys are caught" do
      source = """
      defmodule Portfolixir.SyntheticPrefs do
        alias Portfolixir.Settings

        @token_key "broker_api_token"
        @view_key "default_view_id"

        def save(pin), do: Settings.put("bank_password", pin)
        def load(name), do: Settings.get(name)
      end
      """

      {keys, computed} = settings_keys(source, "synthetic.ex")

      assert "broker_api_token" in keys
      assert "bank_password" in keys
      assert "default_view_id" in keys
      assert Enum.filter(keys, &credential_name?/1) == ["broker_api_token", "bank_password"]
      assert [computed_call] = computed
      assert computed_call =~ "Settings.get"
    end
  end

  test "every allowlist entry carries a reason and still excuses a real name" do
    live =
      (Enum.flat_map(app_schemas(), &schema_names/1) ++ structure_names(database_rows()))
      |> MapSet.new()

    for {entry, reason} <- @allowlist do
      assert is_binary(reason) and String.length(reason) > 20,
             "allowlist entry #{inspect(entry)} needs a written reason"

      assert entry in live, "stale allowlist entry #{inspect(entry)}: remove it"
    end
  end

  # The reflection surface of an Ecto schema, spelled out by hand: a real
  # `use Ecto.Schema` with `redact: true` derives an Inspect implementation,
  # which the consolidated test build rejects with a warning.
  defmodule SyntheticVault do
    @moduledoc false
    def __schema__(:source), do: "vault_entries"
    def __schema__(:fields), do: [:id, :label, :broker_pin, :note]
    def __schema__(:virtual_fields), do: [:api_token]
    def __schema__(:redact_fields), do: [:note]
  end

  # --- matcher -------------------------------------------------------------

  defp credential_name?(name) do
    tokens = tokens(name)

    Enum.any?(tokens, &(&1 in @credential_words)) or
      Enum.any?(Enum.chunk_every(tokens, 2, 1, :discard), &(&1 in @credential_phrases))
  end

  # `OnlineBankingPin`, `online_banking_pin` and `online-banking.pin` all read
  # as ["online", "banking", "pin"].
  defp tokens(name) do
    name
    |> to_string()
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
  end

  # --- sources -------------------------------------------------------------

  defp app_schemas do
    {:ok, modules} = :application.get_key(:portfolixir, :modules)

    Enum.filter(modules, fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1)
    end)
  end

  # Every stored or virtual name of one schema, plus every field Ecto is told
  # to redact — `redact: true` is Ecto's own marker for a secret, so any use of
  # it is reported whatever the field is called.
  defp schema_names(schema) do
    source = schema.__schema__(:source) || inspect(schema)
    redacted = schema.__schema__(:redact_fields)

    fields =
      for field <- schema.__schema__(:fields),
          credential_name?(Atom.to_string(field)),
          do: {:field, source, Atom.to_string(field)}

    virtual =
      for field <- schema.__schema__(:virtual_fields),
          credential_name?(Atom.to_string(field)),
          do: {:virtual_field, source, Atom.to_string(field)}

    redact = for field <- redacted, do: {:redacted_field, source, Atom.to_string(field)}

    Enum.uniq(fields ++ virtual ++ redact)
  end

  defp database_rows do
    %{rows: rows} =
      Repo.query!("""
      SELECT table_name, column_name
      FROM information_schema.columns
      WHERE table_schema = current_schema()
      ORDER BY table_name, column_name
      """)

    Enum.map(rows, fn [table, column] -> {table, column} end)
  end

  defp structure_names(rows) do
    tables =
      rows
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.filter(&credential_name?/1)
      |> Enum.map(&{:table, &1})

    columns = for {table, column} <- rows, credential_name?(column), do: {:column, table, column}

    tables ++ columns
  end

  # `{keys, computed_calls}` of one source file: every `@*_key` string
  # attribute (the settings module's keys, and the session and browser-storage
  # keys elsewhere) and every literal key handed to the raw
  # `Settings.get/put/delete` store; a call whose key is not a literal is
  # returned in `computed_calls`, because the scan cannot read what it stores.
  defp settings_keys(source, path) do
    ast = Code.string_to_quoted!(source)

    collect(ast, fn
      {:@, _, [{name, _, [value]}]} when is_binary(value) ->
        if String.ends_with?(Atom.to_string(name), "_key"), do: [{:key, value}], else: []

      {{:., _, [{:__aliases__, _, segments}, fun]}, _, [key | _]}
      when fun in [:get, :put, :delete] ->
        cond do
          List.last(segments) != :Settings -> []
          is_binary(key) -> [{:key, key}]
          true -> [{:computed, "#{path}: Settings.#{fun}/_ with a computed key"}]
        end

      _other ->
        []
    end)
    |> Enum.reduce({[], []}, fn
      {:key, key}, {keys, computed} -> {keys ++ [key], computed}
      {:computed, call}, {keys, computed} -> {keys, computed ++ [call]}
    end)
    |> then(fn {keys, computed} -> {Enum.uniq(keys), computed} end)
  end

  defp reject_allowlisted(names), do: Enum.reject(names, &Map.has_key?(@allowlist, &1))

  defp collect(ast, matcher) do
    {_ast, acc} = Macro.prewalk(ast, [], fn node, acc -> {node, acc ++ matcher.(node)} end)
    acc
  end
end
