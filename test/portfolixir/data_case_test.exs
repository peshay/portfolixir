defmodule Portfolixir.DataCaseTest do
  use Portfolixir.DataCase, async: true

  defmodule Shape do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field(:kind, Ecto.Enum, values: [:security, :cash_account])
      field(:name, :string)
    end
  end

  # User story (#916):
  # As a maintainer writing a schema test,
  # I want `errors_on/1` to render every changeset error as its message,
  # so that an `Ecto.Enum` field's error reads like any other field's and no
  # test has to match `changeset.errors` by hand.
  #
  # Acceptance criteria:
  # - An `Ecto.Enum` cast error, whose opts carry its parameterized type,
  #   renders as "is invalid".
  # - A placeholder the message names is still filled from the opts; one it
  #   does not name is never rendered, whatever its value.
  test "errors_on/1 renders an Ecto.Enum cast error as its message" do
    changeset = cast(%Shape{}, %{kind: "portfolio"}, [:kind])

    assert {_message, opts} = changeset.errors[:kind]
    assert match?({:parameterized, _}, opts[:type])
    assert errors_on(changeset) == %{kind: ["is invalid"]}
  end

  test "errors_on/1 fills the placeholders a message names, and only those" do
    changeset =
      %Shape{}
      |> cast(%{name: "ab"}, [:name])
      |> validate_length(:name, min: 3)
      |> add_error(:kind, "is not %{wanted}", wanted: "a cash account", type: {:not, :stringable})

    assert errors_on(changeset) == %{
             name: ["should be at least 3 character(s)"],
             kind: ["is not a cash account"]
           }
  end
end
