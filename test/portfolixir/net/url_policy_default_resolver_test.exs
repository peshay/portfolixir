defmodule Portfolixir.Net.UrlPolicyDefaultResolverTest do
  # Issue #762: the resolver used when neither the caller nor the application
  # config injects one. `localhost` comes from the hosts file, so this touches
  # no DNS; it is the one name whose answer is known on every machine.
  use ExUnit.Case, async: false

  alias Portfolixir.Net.UrlPolicy

  setup do
    previous = Application.get_env(:portfolixir, UrlPolicy)
    Application.delete_env(:portfolixir, UrlPolicy)
    on_exit(fn -> Application.put_env(:portfolixir, UrlPolicy, previous) end)
    :ok
  end

  # User story:
  # As an operator running an instance with no resolver configured,
  # I want the policy to resolve names itself, both address families,
  # so that "https://localhost/" is refused as loopback rather than fetched.
  test "the default resolver answers from the hosts file and the policy refuses loopback" do
    assert {:ok, [_ | _] = addresses} = UrlPolicy.resolve_host("localhost")
    refute Enum.any?(addresses, &UrlPolicy.public_address?/1)

    assert {:error, {:url_not_allowed, :private_address}} =
             UrlPolicy.check("https://localhost/x.png")
  end
end
