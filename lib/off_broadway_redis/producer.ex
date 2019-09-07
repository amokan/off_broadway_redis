defmodule OffBroadwayRedis.Producer do
  @moduledoc """
  A GenStage producer that continuously receives messages from a Redis list.

  This implementation follows the [Reliable Queue](https://redis.io/commands/rpoplpush#pattern-reliable-queue) pattern
  outlined in the Redis documentation.

  ## Options

    * `:redis_instance` - Required. An atom representing the redis instance/connection.
    * `:list_name` - Required. The name of the redis list containing items you want to process.
    * `:working_list_name` - Required. The name of the redis 'working' or 'processing' list.
    * `:max_number_of_items` - Optional. The maximum number of items to be fetched per pipelined request.
      This value generally should be between `1` and `20`. Default is `10`.

  ## Additional Options

    * `:redis_client` - Optional. A module that implements the `OffBroadwayRedis.RedisClient`
      behaviour. This module is responsible for fetching and acknowledging the
      messages. Pay attention that all options passed to the producer will be forwarded
      to the client. It's up to the client to normalize the options it needs. Default
      is `RedixClient`.
    * `:receive_interval` - Optional. The duration (in milliseconds) for which the producer waits
      before making a request for more items. Default is `5000`.

  """

  use GenStage

  @default_receive_interval 5_000

  @impl true
  def init(opts) do
    client = opts[:redis_client] || OffBroadwayRedis.RedixClient
    receive_interval = opts[:receive_interval] || @default_receive_interval

    case client.init(opts) do
      {:error, message} ->
        raise ArgumentError, "invalid options given to #{inspect(client)}.init/1, " <> message

      {:ok, opts} ->
        {:producer,
         %{
           demand: 0,
           receive_timer: nil,
           receive_interval: receive_interval,
           redis_client: {client, opts}
         }}
    end
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    handle_receive_messages(%{state | demand: demand + incoming_demand})
  end

  @impl true
  def handle_info(:receive_messages, state) do
    handle_receive_messages(%{state | receive_timer: nil})
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, [], state}
  end

  def handle_receive_messages(%{receive_timer: nil, demand: demand} = state) when demand > 0 do
    messages = receive_messages_from_redis(state, demand)
    new_demand = demand - length(messages)

    receive_timer =
      case {messages, new_demand} do
        {[], _} -> schedule_receive_messages(state.receive_interval)
        {_, 0} -> nil
        _ -> schedule_receive_messages(0)
      end

    {:noreply, messages, %{state | demand: new_demand, receive_timer: receive_timer}}
  end

  def handle_receive_messages(state) do
    {:noreply, [], state}
  end

  defp receive_messages_from_redis(state, total_demand) do
    %{redis_client: {client, opts}} = state
    client.receive_messages(total_demand, opts)
  end

  defp schedule_receive_messages(interval) do
    Process.send_after(self(), :receive_messages, interval)
  end
end
