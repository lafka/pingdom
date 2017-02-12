defmodule Pingdom.Tests do
  require Logger
  use GenServer

  defmodule State do
    defstruct name: nil, test: nil, args: nil, timer: nil, storage: &Pingdom.Storage.store/2
  end

  def start_link(name, {storage, test}, interval, args) do
    GenServer.start_link __MODULE__, [name, {storage, test}, interval, args], name: :"#{name}"
  end

  def start_link(name, test, interval, args), do:
    start_link(name, {&Pingdom.Storage.store/2, test}, interval, args)

  def init([name, {storage, test}, interval, args]) do
    {:ok, timer} = :timer.send_interval interval, self(), :test

    Logger.warn "start"
    {:ok, %State{name: name, test: test, args: args, timer: timer, storage: storage}}
  end

  def handle_info(:test, %{name: name, args: args, test: test} = state) do
    case test.test args do
      :ok ->
        {:noreply, state}

      {:ok, val} ->
        :ok = apply state.storage, [name, val]
        {:noreply, state}
    end
  end

  def terminate(_reason, %{timer: timer}) do
    {:ok, :cancel} = :timer.cancel timer
    :ok
  end

  defmodule Random do
    def test(n) do
      {:ok, :rand.uniform(n)}
    end
  end

  defmodule HTTP_Ping do
    def test(_arg) do
      {:ok, 0}
    end
  end

  defmodule TCP_RTT do
    def test({module, _arg}) when module in [:gen_tcp, :ssl] do
      {:ok, 0}
    end
  end
end
