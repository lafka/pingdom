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

    {:ok, %State{name: name, test: test, args: args, timer: timer, storage: storage}}
  end

  def handle_info(:test, %{name: name, args: args, test: test} = state) do
    Logger.info "collection #{name} <- #{test}"
    component = Application.get_env(:pingdom, :components, %{})[name]
    case test.test args do
      :ok ->
        Logger.debug "tests: #{name} <- #{test} -> (nil)"
        {:noreply, state}

      {:ok, val} ->
        Logger.info "tests: #{name} <- #{test} -> #{val}"

        if component do
          Pingdom.Incidents.update component, :ok, val
        end

        :ok = apply state.storage, [name, val]
        {:noreply, state}

      {:state, s} ->
        Logger.error "tests: #{name} <- STATE: #{s}"
        if component do
          Pingdom.Incidents.update component, s, nil
        end
        {:noreply, state}

      {:error, err} when err in [:econnrefused, :nxdomain] ->
        Logger.error "tests: #{name} <- ERROR: #{err}"
        if component do
          Pingdom.Incidents.update component, :failed, nil
        end
        {:noreply, state}

      {:error, err} ->
        Logger.error "tests: #{name} <- ERROR: #{err}"

        if component do
          Pingdom.Incidents.update component, :degraded, nil
        end

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
    def test(url) do
      starttime = :erlang.system_time()

      try do
        case HTTPoison.get url do
          {:ok, %{status_code: 200}} ->
            diff = :erlang.system_time() - starttime
            {:ok, :erlang.convert_time_unit(diff, :native, :milli_seconds)}

          {:ok, %{status_code: _}} ->
            {:state, :degraded}

          {:error, _} = err ->
            err
        end
      rescue _e ->
        {:error, :exception}
      end
    end
  end

  defmodule TCP_RTT do
    def test({module, host, port}) when module in [:gen_tcp, :ssl] do
      starttime = :erlang.system_time()
      case module.connect '#{host}', port, [:binary, active: false] do
        {:ok, sock} ->
          case module.recv sock, 0 do
            {:ok, _} ->
              diff = :erlang.system_time() - starttime
              :ok = close module, sock
              {:ok, :erlang.convert_time_unit(diff, :native, :milli_seconds)}

            _ ->
              {:state, :degraded}
          end

        {:error, _reason} = err ->
          err
      end
    end

    defp close(:ssl, sock), do: :ssl.close(sock, 1000)
    defp close(:gen_tcp, sock), do: :gen_tcp.close(sock)
  end
end
