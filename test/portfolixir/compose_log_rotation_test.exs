defmodule Portfolixir.ComposeLogRotationTest do
  use ExUnit.Case, async: true

  # User story (security review 2026-10-12, H70):
  # As the operator who runs the documented Compose deployment,
  # I want every container's log rotated,
  # so that a client that makes the application log a lot cannot fill the
  # disk the database lives on.
  #
  # Acceptance criteria:
  # - Every service of docker-compose.yml and docker-compose.dev.yml logs
  #   through Docker's `local` driver, at most five files of 10 MB each.
  # - The deployment guide (EN, DE) says how the logs are rotated in Compose
  #   and that a run outside Compose rotates its own.
  test "every service of both Compose files rotates its container log" do
    for path <- ["docker-compose.yml", "docker-compose.dev.yml"] do
      services = services(File.read!(path))

      assert Enum.sort(Map.keys(services)) == ["app", "db", "mcp"], path

      unrotated =
        for {name, block} <- services,
            not (block =~ ~r/^ {4}logging:\s*$/m and
                   (block =~ ~r/^ {6,}max-size:/m or block =~ ~r/^ {6}driver:\s*"?local"?\s*$/m)),
            do: name

      assert unrotated == [],
             "#{path} services without a rotating logging driver: " <>
               inspect(Enum.sort(unrotated))

      for {name, block} <- services do
        assert block =~
                 ~r/^    logging:\n      driver: local\n      options:\n        max-size: "10m"\n        max-file: "5"$/m,
               "#{path}: #{name}"
      end
    end
  end

  test "the deployment guide names log rotation in Compose and outside it" do
    for {path, phrases} <- [
          {"docs/home-deployment.md", ["`local` log driver", "outside Compose"]},
          {"docs/de/home-deployment.md", ["`local`-Log-Treiber", "außerhalb von Compose"]}
        ] do
      guide = path |> File.read!() |> String.replace(~r/\s+/, " ")

      for phrase <- phrases do
        assert guide =~ phrase, "#{path}: #{phrase}"
      end
    end
  end

  # The service blocks under `services:`, keyed by service name, read the way
  # test/portfolixir/ci_test.exs reads the Compose files: by indentation.
  defp services(compose) do
    [_, body] = Regex.run(~r/^services:\n(.*?)(?=^[^\s#]|\z)/ms, compose)

    body
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, fn line, {current, acc} ->
      case Regex.run(~r/^  ([a-z][\w-]*):\s*$/, line) do
        [_, name] -> {name, Map.put(acc, name, "")}
        nil when current == nil -> {current, acc}
        nil -> {current, Map.update!(acc, current, &(&1 <> line <> "\n"))}
      end
    end)
    |> elem(1)
  end
end
