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
  #   stored. The one allowlisted name is the session key that binds a login to
  #   the UI password by a keyed HMAC of it (E25 S1, #886): not the password,
  #   and nothing a cookie reader can test guesses against.
  # - The matcher catches synthetic violations of each kind, so a clean tree
  #   cannot pass vacuously.
  # - An allowlist entry carries a reason and still excuses something real.
  #
  # The limit, stated rather than hidden: B1 reads names, not values. A
  # free-form value — a security's `attributes` map, a `notes` text — can hold
  # anything a caller writes into it, a credential included; what keeps one
  # out is that nothing in the app asks for one, and review, not this test.

  # Name tokens that mean "this holds a credential". A name matches when one of
  # its snake_case / CamelCase tokens is in this list, so `pinned` or `tangent`
  # never match `pin` or `tan`.
  @credential_words ~w(
    password passwords passwd passphrase pwd secret secrets token tokens pin pins
    tan tans otp totp hotp mfa credential credentials login logins logon logons
    username usernames apikey apikeys privkey mnemonic mnemonics passcode passcodes
    pincode pincodes cred creds
  )

  # Two-token phrases whose single words are innocent on their own (a settings
  # `key`, a PP `online_id`) but mean a credential together. The last word
  # also matches in its plural (`api_keys`, the Ecto name of a table of them).
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

  # `{kind, name} => reason`. Nothing stored in Portfolixir is a credential. An
  # entry needs a written reason and must still excuse a real name; the UI
  # password and the API tokens live in the environment and never need one.
  @allowlist %{
    {:settings_key, "ui_password_fingerprint"} =>
      "a signed session-cookie key, not a settings row: it holds a keyed HMAC of the " <>
        "environment's UI password (key derived from SECRET_KEY_BASE) so that changing " <>
        "the password ends every session (E25 S1 F02, #886); it is not the password, " <>
        "cannot be tested against without the server's secret, and opens no bank or broker"
  }

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
      {keys, computed} = lib_settings_keys()

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
                     online_banking_login seed_phrase BrokerCredential totp_secret
                     api_keys access_keys private_keys signing_keys auth_codes passcode
                     pincode broker_creds APIToken OTPSecret) do
        assert credential_name?(name), "#{name} should read as a credential"
      end

      for name <- ~w(key online_id import_hash pinned_at tangent isin settlement_amount
                     classification_key TokenizerLabel credit credits PolicyJSON
                     SessionHTML sort_keys) do
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
      rows = [
        {"bank_logins", "id"},
        {"api_keys", "key_hash"},
        {"accounts", "online_banking_pin"},
        {"accounts", "name"}
      ]

      assert structure_names(rows) == [
               {:table, "bank_logins"},
               {:table, "api_keys"},
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

    test "the raw store's own local calls and piped calls are read too" do
      source = """
      defmodule Portfolixir.Settings do
        @default_view_key "default_view_id"

        def get(key) when is_binary(key), do: {:read, key}
        def put(key, value), do: {:write, key, value}

        def default_view_id, do: get(@default_view_key)
        def set_broker_pin(pin), do: put("broker_pin", pin)
        def remember(name, value), do: put(name, value)
      end

      defmodule Portfolixir.SyntheticCaller do
        def load, do: "bank_password" |> Portfolixir.Settings.get()
      end
      """

      {keys, computed} = settings_keys(source, "synthetic.ex")

      assert "default_view_id" in keys
      assert "broker_pin" in keys
      assert "bank_password" in keys
      assert [computed_call] = computed
      assert computed_call =~ "Settings.put"
    end
  end

  test "every allowlist entry carries a reason and still excuses a real name" do
    {keys, _computed} = lib_settings_keys()

    live =
      (Enum.flat_map(app_schemas(), &schema_names/1) ++
         structure_names(database_rows()) ++
         for(key <- keys, credential_name?(key), do: {:settings_key, key}))
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
      Enum.any?(Enum.chunk_every(tokens, 2, 1, :discard), fn [first, last] ->
        [first, last] in @credential_phrases or
          [first, String.replace_suffix(last, "s", "")] in @credential_phrases
      end)
  end

  # `OnlineBankingPin`, `online_banking_pin` and `online-banking.pin` all read
  # as ["online", "banking", "pin"]; an acronym fused to the next word splits
  # off it (`APIToken` reads as ["api", "token"]), as Elixir spells acronyms.
  defp tokens(name) do
    name
    |> to_string()
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
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

  # `{keys, computed_calls}` over every source file in lib/.
  defp lib_settings_keys do
    "lib/**/*.ex"
    |> Path.wildcard()
    |> Enum.map(&settings_keys(File.read!(&1), &1))
    |> Enum.reduce({[], []}, fn {k, c}, {ks, cs} -> {ks ++ k, cs ++ c} end)
  end

  # `{keys, computed_calls}` of one source file: every `@*_key` string
  # attribute (the settings module's keys, and the session and browser-storage
  # keys elsewhere) and every key handed to the raw `get/put/delete` store —
  # called as `Settings.get/put/delete` from anywhere (pipes expanded first),
  # or locally inside `Portfolixir.Settings` itself, where the store's own
  # helpers call it. A literal key, or a module attribute holding one, is read;
  # any other key is returned in `computed_calls`, because the scan cannot read
  # what it stores.
  defp settings_keys(source, path) do
    ast = source |> Code.string_to_quoted!() |> Macro.prewalk(&unpipe/1)
    attributes = string_attributes(ast)

    attribute_keys =
      for {name, value} <- attributes,
          String.ends_with?(Atom.to_string(name), "_key"),
          do: {:key, value}

    remote =
      collect(ast, fn
        {{:., _, [{:__aliases__, _, segments}, fun]}, _, [key | _]}
        when fun in [:get, :put, :delete] ->
          if List.last(segments) == :Settings,
            do: [store_key(key, attributes, path, fun)],
            else: []

        _other ->
          []
      end)

    local =
      for body <- settings_store_bodies(ast),
          hit <-
            collect(body, fn
              {fun, _, [key | _]} when fun in [:get, :put, :delete] ->
                [store_key(key, attributes, path, fun)]

              _other ->
                []
            end),
          do: hit

    (attribute_keys ++ remote ++ local)
    |> Enum.reduce({[], []}, fn
      {:key, key}, {keys, computed} -> {keys ++ [key], computed}
      {:computed, call}, {keys, computed} -> {keys, computed ++ [call]}
    end)
    |> then(fn {keys, computed} -> {Enum.uniq(keys), computed} end)
  end

  defp store_key(key, _attributes, _path, _fun) when is_binary(key), do: {:key, key}

  defp store_key({:@, _, [{name, _, context}]} = key, attributes, path, fun)
       when is_atom(name) and is_atom(context) do
    case Keyword.fetch(attributes, name) do
      {:ok, value} -> {:key, value}
      :error -> store_key({:computed, key}, attributes, path, fun)
    end
  end

  defp store_key(_computed, _attributes, path, fun),
    do: {:computed, "#{path}: Settings.#{fun}/_ with a computed key"}

  # `[{name, value}]` of every string module attribute, in source order.
  defp string_attributes(ast) do
    collect(ast, fn
      {:@, _, [{name, _, [value]}]} when is_atom(name) and is_binary(value) -> [{name, value}]
      _other -> []
    end)
  end

  # The function bodies of `Portfolixir.Settings`, where the raw store is
  # called locally; function heads are left out, so `def get(key)` itself is
  # not read as a call with a computed key.
  defp settings_store_bodies(ast) do
    collect(ast, fn
      {:defmodule, _, [{:__aliases__, _, [:Portfolixir, :Settings]}, [do: module_body]]} ->
        collect(module_body, fn
          {kind, _, [_head, body]} when kind in [:def, :defp] -> [body]
          _other -> []
        end)

      _other ->
        []
    end)
  end

  defp unpipe({:|>, _, [left, right]} = node) do
    Macro.pipe(left, right, 0)
  rescue
    ArgumentError -> node
  end

  defp unpipe(node), do: node

  defp reject_allowlisted(names), do: Enum.reject(names, &Map.has_key?(@allowlist, &1))

  defp collect(ast, matcher) do
    {_ast, acc} = Macro.prewalk(ast, [], fn node, acc -> {node, acc ++ matcher.(node)} end)
    acc
  end
end
