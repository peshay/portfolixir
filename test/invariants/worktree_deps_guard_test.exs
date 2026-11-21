defmodule Portfolixir.Invariants.WorktreeDepsGuardTest do
  # A worktree's `deps` cannot change the main checkout's (Sprint 31 plan M4,
  # the Sprint 30 retrospective's carry-forward 9): scripts/worktree.sh links
  # a worktree's `deps` to the main checkout's when their mix.lock files
  # agree, and one lane's `mix deps.get` for a lock it had changed since
  # fetched through that link into every lane's dependencies. Every Mix task
  # that writes into `deps` therefore first runs
  # `Portfolixir.MixProject.own_deps/1`, which replaces a linked `deps` with a
  # copy of its own (`scripts/worktree.sh own`, pinned by
  # scripts/test_worktree.py) and does nothing where `deps` is a directory.
  use ExUnit.Case, async: true

  @writers [:"deps.get", :"deps.update", :"deps.clean"]

  test "every Mix task that writes into deps first gives a linked deps its own copy" do
    aliases = Mix.Project.config()[:aliases]

    for task <- @writers do
      assert aliases[task] == [&Portfolixir.MixProject.own_deps/1, Atom.to_string(task)],
             "mix #{task} can write through a worktree's deps link: #{inspect(aliases[task])}"
    end
  end
end
