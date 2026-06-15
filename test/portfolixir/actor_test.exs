defmodule Portfolixir.ActorTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Actor

  test "new/2 builds a known actor with an optional label" do
    assert Actor.new(:owner_ui) == %Actor{type: :owner_ui, label: nil}
    assert Actor.new(:api_token_rw, "tok-1") == %Actor{type: :api_token_rw, label: "tok-1"}
  end

  test "new/2 raises on a type outside the closed taxonomy" do
    assert_raise ArgumentError, ~r/unknown actor type/, fn -> Actor.new(:hacker) end
  end

  test "named constructors cover the taxonomy" do
    assert Actor.owner_ui() == %Actor{type: :owner_ui}
    assert Actor.api_token_rw("rw") == %Actor{type: :api_token_rw, label: "rw"}
    assert Actor.api_token_ro("ro") == %Actor{type: :api_token_ro, label: "ro"}
    assert Actor.api_token_ro() == %Actor{type: :api_token_ro, label: nil}
    assert Actor.import_session("file.csv") == %Actor{type: :import_session, label: "file.csv"}
    assert Actor.system_job("sync") == %Actor{type: :system_job, label: "sync"}
  end

  test "types/0 is the closed taxonomy" do
    assert Actor.types() == ~w(owner_ui api_token_rw api_token_ro import_session system_job)a
  end

  test "to_columns/1 splits type and label into journal column strings" do
    assert Actor.to_columns(Actor.api_token_rw("tok")) == {"api_token_rw", "tok"}
    assert Actor.to_columns(Actor.owner_ui()) == {"owner_ui", nil}
  end
end
