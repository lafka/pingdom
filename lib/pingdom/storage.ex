defmodule Pingdom.Storage do
  @moduledoc false

  require Logger
  use GenServer

  @server :storage

  def start_link, do: GenServer.start_link(__MODULE__, [], name: @server)

  def store(metric, value), do: store(metric, value, @server)
  def store(metric, value, server) do
    GenServer.cast server, {:store, metric, value}
  end

  def flush, do: flush(@server)
  def flush(server), do: GenServer.cast(server, :flush)

  def init() do
    {:ok,
      %{
        queue: []
      }}
  end

  def handle_cast({:store, metric, value}, %{queue: queue} = state) do
    now = :erlang.system_time()

    {:noreply, %{state | queue: [{now, metric, value} | queue]}}
  end

  # cachet only supports posting metrics one by one
  def handle_cast(:flush, %{request: nil, queue: queue} = state) do
    {:ok, newqueue} = doflush queue

    # don't run out of memory
    backlog = Application.get_env :pingdom, :backlog, 1000
    {:noreply, %{state | queue: Enum.slice(newqueue, 0, backlog)}}
  end

  defp doflush(queue) do
    doflush(queue, [], Application.get_all_env(:pingdom))
  end
  defp doflush([], rest, _), do: {:ok, rest}
  defp doflush([{timestamp, metric, value} = item | rest], failed, %{metrics: metrics, backend: backend} = config) do
    now = :erlang.system_time(:millisecond)
    diff  = now - :erlang.convert_time_unit(timestamp, :native, :millisecond)

    # old metrics are useless
    if diff > config[:ttl] do
      doflush rest, failed, config
    else
      {_test, point, _args} = metrics[metric]

      headers = [
        {"Content-Type", "application/json"},
        {"X-Cachet-Token", config[:cachet_token]}
      ]
      ms = :erlang.convert_time_unit(timestamp, :native, :millisecond)
      body = "{\"value\":'#{value},\"timestamp\": '#{ms}'}"

      case HTTPoison.post "#{backend}/v1/metrics/#{point}/points", body, headers do
        {:ok, %{status_code: 200}} ->
          doflush rest, failed, config

        {:ok, %{status_code: status}} ->
          Logger.warn "failed to store #{metric}: HTTP #{status}"
          doflush rest, [item | failed], config

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.warn "failed to store #{metric}: #{reason}"
          doflush rest, [item | failed], config
      end
    end
  end


#iex> HTTPoison.post "http://httparrot.herokuapp.com/post", "{\"body\": \"test\"}", [{"Content-Type", "application/json"}]
#		-H 'Content-Type: application/json' \
#		-d '{"value": '$TIME',"timestamp": '$(date --utc +%s)'}' \
#		-H 'X-Cachet-Token: 9Ib9MnjeR8WStYtQs0rU'
end
