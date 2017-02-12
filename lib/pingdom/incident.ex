defmodule Pingdom.Incidents do
  require Logger
  use GenServer

  @server :incidents

  # keeps status of incidents
  #
  # If status change for component:
  #  - check if there's any ongoing incidents 
  #  - if status := ok and incident exists
  #   - update status -> :ok and set fixed
  #  - if status /= ok and incident exists
  #   - update status -> s and set "identified"
  #  - if status /= ok and no incident -> 
  #   - create incident with status -> s and set 'identified"
  def update(component, status, metric \\ nil, server \\ @server)
  def update(component, status, metric, server) when status in [:ok, :performance, :degraded, :failed] do
    GenServer.cast server, {:update, component, mapstatus(status), metric}
  end

  defp mapstatus(:ok), do: 1
  defp mapstatus(:performance), do: 2
  defp mapstatus(:degraded), do: 3
  defp mapstatus(:failed), do: 4

  defp mapincident(:investigating), do: 1
  defp mapincident(:identified), do: 2
  defp mapincident(:watching), do: 3
  defp mapincident(:fixed), do: 4

  def start_link() do
    GenServer.start_link __MODULE__, [], name: @server
  end

  def init(_) do
    {:ok, refresh(%{status: %{}})}
  end

  # make sure that starting with failed status should make new incidents if no
  # such exists
  def handle_cast({:update, component, status, _metric}, %{status: statuses} = state) do
    case IO.inspect statuses[component] do
      # new status
      nil ->
        newstate = refresh state
        {:noreply, %{newstate | status: Map.put(statuses, component, addstate(status, []))}}

      # no changes
      [{_, ^status} | _] = compstate ->
        {:noreply, %{state | status: Map.put(statuses, component, addstate(status, compstate))}}

      # status changed
      [{_, oldstatus} | _] = compstate ->
        Logger.warn "incident comp: #{component}: state := #{oldstatus} -> #{status}"

        updateremote nil, component, status

        {:noreply, %{state | status: Map.put(statuses, component, addstate(status, compstate))}}
    end
  end

  defp addstate(status, state), do: addstate(:erlang.system_time, status, state)
  defp addstate(at, status, state) do
    Enum.slice(Enum.reverse(Enum.sort([{at, status} | state])), 0, 100)
  end

  @gregsecs 62167219200
  defp parsedate(date) do
    [y, m, d, h, i, s] = String.split(date, ~r/[^0-9]/) |> Enum.map(&String.to_integer/1)
    epoch = :calendar.datetime_to_gregorian_seconds({ {y, m, d}, {h, i, s} }) - @gregsecs

    :erlang.convert_time_unit(epoch, :second, :native)
  end

  defp refresh(%{status: statuses} = state) do
    backend = Application.get_env :pingdom, :backend, ""
    token = Application.get_env :pingdom, :cachet_token, ""

    headers = [ {"X-Cachet-Token", token} ]
    case HTTPoison.get "#{backend}/v1/incidents", headers do
      {:ok, %{status_code: 200, body: body}} ->
        %{"data" => body} = Poison.decode! body
        newstatuses = Enum.reduce body, statuses, fn(item, acc) ->
          %{"status" => status, "component_id" => comp, "updated_at" => updated} = item
          updated = parsedate updated

          case addstate updated, status, (acc[comp] || []) do
            # incident status is same
            [{_, ^status} | _] = compstate ->
              Map.put acc, comp, compstate

            # something changes, this means there's newer data locally so we can updated
            [{_, newstatus} | _] = compstate ->
              Logger.warn "refresh-incidents comp: #{comp} -> #{status} (remote) -> #{newstatus} (local)"
              # (async) update remote incident
              updateremote item["id"], comp, newstatus
              Map.put acc, comp, compstate
          end
        end

        %{state | status: newstatuses}
      _ ->
        state
    end
  end

  # create new incident, or if we are fixing stuff find newest incident and set it to fixed
  defp updateremote(nil, component, 1) do
    backend = Application.get_env :pingdom, :backend, ""
    token = Application.get_env :pingdom, :cachet_token, ""
    headers = [ {"X-Cachet-Token", token} ]

    case HTTPoison.get "#{backend}/v1/incidents?component_id=#{component}&visible=0", headers do
      {:ok, %{status_code: 200, body: body}} ->
        %{"data" => incidents} = Poison.decode! body
        case incidents do
          [%{"id" => id, "status" => status} |_] when status !== 4 ->
            updateremote id, component, 1

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end
  defp updateremote(nil, component, status) do
    spawn( fn() ->
      backend = Application.get_env :pingdom, :backend
      token   = Application.get_env :pingdom, :cachet_token
      headers = [
        {"Content-Type", "application/json"},
        {"X-Cachet-Token", token}
      ]

      body = Poison.encode! %{
        "name" => "External Tests Failed",
        "message" => "One or more external tests failed to verify the components functionality",
        "status" => if 1 === status do 4 else 2 end,
        "visible" => 0,
        "component_id" => component,
        "component_status" => status,
      }

      HTTPoison.post! "#{backend}/v1/incidents", body, headers
    end)
  end
  defp updateremote(incident, component, newstatus) do
    spawn( fn() ->
      backend = Application.get_env :pingdom, :backend
      token   = Application.get_env :pingdom, :cachet_token
      headers = [
        {"Content-Type", "application/json"},
        {"X-Cachet-Token", token}
      ]

      body = Poison.encode! %{
        "status" => if 1 === newstatus do 4 else 2 end,
        "component_id" => component,
        "component_status" => newstatus,
      }

      HTTPoison.put! "#{backend}/v1/incidents/#{incident}", body, headers
    end)
  end
end
