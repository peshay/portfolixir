defmodule Portfolixir.SourceAliases do
  @moduledoc """
  The modules an Elixir source names, read from its syntax tree with every
  short name resolved through the file's own alias directives.

  The invariants that scan `lib/` for a module no code there may name
  (`derived_never_a_write_source_test.exs`, `web_repo_boundary_test.exs`) ask
  here, so that the way a file writes an alias does not decide what a scan
  finds (N-82). `references/1` reads:

    * a module by its full name, as a call's target or as a value handed on,
      with or without the `Elixir.` prefix, and as a quoted atom
      (`:"Elixir.A.B"`);
    * `alias A.B` and `alias A.B, as: C`;
    * `alias A.{B, C.D}`, each entry under the braces' base;
    * `require A.B, as: C`;
    * an alias built on an earlier one (`alias A.B` and then `alias B.C`).

  A directive counts from the line it stands on to the end of the file,
  whatever module or function it is written in: wider than the compiler's
  lexical scope, never narrower, so a name two modules of one file alias
  differently is read as both. A comment or a string is no syntax and names
  nothing. A module whose name is built at run time (`Module.concat/1`, a
  string turned into an atom) is beyond a reading of the source.
  """

  @type path :: [atom()]

  @doc "Every module path `source` names, in source order, without repeats."
  @spec references(String.t()) :: [path()]
  def references(source) do
    {_ast, {_names, found}} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk({%{}, []}, &read/2)

    found |> Enum.reverse() |> Enum.uniq()
  end

  # One node: a directive adds its names and counts as a reference to what
  # it aliases; any other alias or module atom is a reference by itself.
  defp read(node, {names, found} = acc) do
    case directive(node) do
      {:ok, entries} ->
        resolved = for {name, path} <- entries, full <- expand(path, names), do: {name, full}

        names =
          Enum.reduce(resolved, names, fn {name, full}, names ->
            Map.update(names, name, [full], &Enum.uniq([full | &1]))
          end)

        # The directive is replaced by a leaf, so its own parts -- a brace
        # form's base, an `as:` name -- are not read as references again.
        {:directive, {names, Enum.reverse(Enum.map(resolved, &elem(&1, 1)), found)}}

      :error ->
        case path(node) do
          nil -> {node, acc}
          path -> {node, {names, Enum.reverse(expand(path, names), found)}}
        end
    end
  end

  # `alias A.B`, `alias A.B, as: C`, `require A.B, as: C`: the name the
  # directive gives, and the path it stands for.
  defp directive({kind, _meta, [{:__aliases__, _, path} | opts]})
       when kind in [:alias, :require] do
    name =
      case opts do
        [[{_, _} | _] = keywords] -> as(Keyword.get(keywords, :as))
        _none -> nil
      end

    cond do
      not Enum.all?(path, &is_atom/1) -> :error
      name -> {:ok, [{name, path}]}
      kind == :alias -> {:ok, [{List.last(path), path}]}
      # A `require` without `as:` gives no name: its path is read as any
      # other alias node is.
      true -> :error
    end
  end

  # `alias A.{B, C.D}`: one name for every entry, under the base.
  defp directive({:alias, _meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, entries} | _opts]}) do
    if Enum.all?(base, &is_atom/1) do
      {:ok, for({:__aliases__, _, rest} <- entries, do: {List.last(rest), base ++ rest})}
    else
      :error
    end
  end

  defp directive(_node), do: :error

  defp as({:__aliases__, _, [name]}) when is_atom(name), do: name
  defp as(_other), do: nil

  # The path a node names by itself: an alias of plain segments, or a module
  # written as a quoted atom.
  defp path({:__aliases__, _meta, path}), do: if(Enum.all?(path, &is_atom/1), do: path)

  defp path(atom) when is_atom(atom) do
    with "Elixir." <> _ <- Atom.to_string(atom),
         {:ok, {:__aliases__, _, path}} <- Code.string_to_quoted(inspect(atom)) do
      path
    else
      _not_a_module -> nil
    end
  end

  defp path(_node), do: nil

  # What `path` stands for: its first segment replaced by every path an
  # earlier directive gave that name. `Elixir.A.B` is `A.B` whatever is
  # aliased.
  defp expand([:"Elixir" | [_ | _] = rest], _names), do: [rest]

  defp expand([first | rest] = path, names) do
    case Map.fetch(names, first) do
      {:ok, fulls} -> Enum.map(fulls, &(&1 ++ rest))
      :error -> [path]
    end
  end
end
