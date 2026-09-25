defmodule PortfolixirWeb.LiveSource do
  @moduledoc """
  Reads a LiveView's (or LiveComponent's) own source, so a boundary test can
  enumerate what the page accepts instead of a list somebody has to keep in
  step with it (E25 S4, F16, F17, #868).

    * `events/1` — every event the module's `handle_event/3` clauses name,
      with every string key a clause reads from its payload;
    * `param_keys/1` — every string key read on the way from `mount/3` and
      `handle_params/3`, through the private functions they reach, which is
      where a page reads its URL.

  Both over-approximate on purpose: a key that is not a URL or payload key is
  just one more value a test sends and the page ignores.
  """

  @doc "The module's `{event, keys}` pairs, sorted by event."
  @spec events(module()) :: [{String.t(), [String.t()]}]
  def events(module) do
    module
    |> clauses()
    |> Enum.flat_map(fn
      {{:handle_event, 3}, [event, pattern, _socket], body} when is_binary(event) ->
        [{event, keys_in({pattern, body})}]

      _clause ->
        []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {event, key_lists} -> {event, key_lists |> List.flatten() |> Enum.uniq()} end)
    |> Enum.sort()
  end

  @doc "The string keys read from `mount/3` and `handle_params/3` onwards."
  @spec param_keys(module()) :: [String.t()]
  def param_keys(module) do
    clauses = clauses(module)
    by_name = Enum.group_by(clauses, &elem(&1, 0))

    [{:mount, 3}, {:handle_params, 3}]
    |> reachable(by_name, MapSet.new())
    |> Enum.flat_map(fn fun -> Map.get(by_name, fun, []) end)
    |> Enum.flat_map(fn {_fun, args, body} -> keys_in({args, body}) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp reachable([], _by_name, seen), do: MapSet.to_list(seen)

  defp reachable([fun | rest], by_name, seen) do
    if MapSet.member?(seen, fun) or not Map.has_key?(by_name, fun) do
      reachable(rest, by_name, seen)
    else
      calls =
        by_name
        |> Map.fetch!(fun)
        |> Enum.flat_map(fn {_fun, args, body} -> local_calls({args, body}) end)

      reachable(calls ++ rest, by_name, MapSet.put(seen, fun))
    end
  end

  # A local call counts at its own arity and, as the right side of a pipe,
  # one more — over-approximating is harmless here.
  defp local_calls(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {:&, _, [{:/, _, [{name, _, _}, arity]}]} = node, acc
        when is_atom(name) and is_integer(arity) ->
          {node, [{name, arity} | acc]}

        {name, _meta, args} = node, acc when is_atom(name) and is_list(args) ->
          arity = length(args)
          {node, [{name, arity}, {name, arity + 1} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  defp keys_in(ast) do
    {_ast, keys} =
      Macro.prewalk(ast, [], fn
        {:%{}, _meta, pairs} = node, acc when is_list(pairs) ->
          {node, for({key, _value} when is_binary(key) <- pairs, do: key) ++ acc}

        {{:., _, [Access, :get]}, _, [_map, key]} = node, acc when is_binary(key) ->
          {node, [key | acc]}

        {{:., _, [{:__aliases__, _, [:Map]}, fun]}, _, [_map, key | _]} = node, acc
        when fun in [:get, :fetch, :fetch!, :has_key?] and is_binary(key) ->
          {node, [key | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(keys)
  end

  # `{{name, arity}, args, body}` for every `def`/`defp` clause in the source.
  defp clauses(module) do
    source = module.module_info(:compile)[:source] |> to_string()
    {:ok, ast} = source |> File.read!() |> Code.string_to_quoted()

    {_ast, clauses} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
          case head(head) do
            {:ok, name, args} -> {node, [{{name, length(args)}, args, body} | acc]}
            :error -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(clauses)
  end

  defp head({:when, _meta, [head | _guards]}), do: head(head)
  defp head({name, _meta, args}) when is_atom(name) and is_list(args), do: {:ok, name, args}
  defp head({name, _meta, nil}) when is_atom(name), do: {:ok, name, []}
  defp head(_head), do: :error
end
