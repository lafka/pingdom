defmodule PingdomTest do
  require Logger
  use ExUnit.Case

  defmodule Handler do
    def test({reply, ref}) do
      send reply, {ref, :done}
      :ok
    end
    def test({_reply, _ref, return}) do
      {:ok, return}
    end
  end

  test "tests interval" do
    {_, ref} = args = {self(), make_ref()}

    {:ok, _pid} = Pingdom.Tests.start_link "test", __MODULE__.Handler, 100, args
    assert_receive {^ref, :done}, 500
  end

  test "storage" do
    {parent, _ref, reply} = args = {self(), make_ref(), make_ref()}

    storage = fn(k, v) ->
      send parent, {:storage, k, v, :done}
      :ok
    end

    test = {storage, __MODULE__.Handler}
    {:ok, _pid} = Pingdom.Tests.start_link "test", test, 100, args
    assert_receive {:storage, "test", ^reply, :done}, 150
  end
end
