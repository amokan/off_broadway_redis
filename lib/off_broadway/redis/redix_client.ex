defmodule OffBroadway.Redis.RedixClient do
  @moduledoc """
  Default Redis client used by `OffBroadway.Redis.Producer` to communicate with Redis.

  This client implements the `OffBroadway.Redis.RedisClient` behaviour which
  defines callbacks for receiving and acknowledging items popped from a list.
  """

  alias Broadway.{Message, Acknowledger}
  require Logger

  @behaviour OffBroadway.Redis.RedisClient
  @behaviour Acknowledger

  @default_pipeline_timeout 10_000
  @default_max_number_of_messages 10
  @max_num_messages_allowed 20

  @impl true
  def init(opts) do
    with {:ok, redis_instance} <- validate(opts, :redis_instance),
         {:ok, list_name} <- validate(opts, :list_name),
         {:ok, working_list_name} <- validate(opts, :working_list_name),
         {:ok, receive_messages_opts} <- validate_receive_messages_opts(opts),
         {:ok, config} <- validate(opts, :config, []) do
      ack_ref =
        Broadway.TermStorage.put(%{
          redis_instance: redis_instance,
          list_name: list_name,
          working_list_name: working_list_name,
          config: config
        })

      {:ok,
       %{
         redis_instance: redis_instance,
         list_name: list_name,
         working_list_name: working_list_name,
         receive_messages_opts: receive_messages_opts,
         config: config,
         ack_ref: ack_ref
       }}
    end
  end

  @impl true
  def receive_messages(demand, opts) do
    receive_messages_opts = put_max_number_of_items(opts.receive_messages_opts, demand)

    opts.redis_instance
    |> pop_messages(
      opts.list_name,
      opts.working_list_name,
      receive_messages_opts[:max_number_of_items]
    )
    |> wrap_received_messages(opts.ack_ref)
  end

  @impl true
  def ack(ack_ref, successful, _failed) do
    successful
    |> Enum.chunk_every(@max_num_messages_allowed)
    |> Enum.each(fn messages -> delete_messages(messages, ack_ref) end)
  end

  defp delete_messages(messages, ack_ref) do
    receipts = Enum.map(messages, &extract_message_receipt/1)
    opts = Broadway.TermStorage.get!(ack_ref)

    delete_message_batch(opts.redis_instance, opts.working_list_name, receipts)
  end

  defp wrap_received_messages([], _ack_ref), do: []

  defp wrap_received_messages(messages, ack_ref) when is_list(messages) do
    Enum.map(messages, fn message ->
      ack_data = %{receipt: %{id: message}}
      %Message{data: message, acknowledger: {__MODULE__, ack_ref, ack_data}}
    end)
  end

  defp put_max_number_of_items(receive_messages_opts, demand) do
    max_number_of_items = min(demand, receive_messages_opts[:max_number_of_items])
    Keyword.put(receive_messages_opts, :max_number_of_items, max_number_of_items)
  end

  defp extract_message_receipt(message) do
    {_, _, %{receipt: receipt}} = message.acknowledger
    receipt
  end

  defp validate(opts, key, default \\ nil) when is_list(opts) do
    validate_option(key, opts[key] || default)
  end

  defp validate_option(:config, value) when not is_list(value),
    do: validation_error(:config, "a keyword list", value)

  defp validate_option(:list_name, value) when not is_binary(value) or value == "",
    do: validation_error(:list_name, "a non empty string", value)

  defp validate_option(:working_list_name, value) when not is_binary(value) or value == "",
    do: validation_error(:working_list_name, "a non empty string", value)

  defp validate_option(:redis_instance, nil),
    do: validation_error(:redis_instance, "a atom", nil)

  defp validate_option(:redis_instance, value) when not is_atom(value),
    do: validation_error(:redis_instance, "a atom", value)

  defp validate_option(:max_number_of_items, value) when value not in 1..20,
    do: validation_error(:max_number_of_items, "a integer between 1 and 20", value)

  defp validate_option(_, value), do: {:ok, value}

  defp validation_error(option, expected, value) do
    {:error, "expected #{inspect(option)} to be #{expected}, got: #{inspect(value)}"}
  end

  defp validate_receive_messages_opts(opts) do
    with {:ok, max_number_of_items} <-
           validate(opts, :max_number_of_items, @default_max_number_of_messages) do
      {:ok, [max_number_of_items: max_number_of_items]}
    end
  end

  # atomically batch rpoplpush items from the source list to the working list using a pipelined command
  defp pop_messages(redis_instance, source_list, dest_list, number_to_receive)
       when number_to_receive > 1 do
    pipeline_commands = for _ <- 1..number_to_receive, do: ["RPOPLPUSH", source_list, dest_list]

    case Redix.pipeline(redis_instance, pipeline_commands, timeout: @default_pipeline_timeout) do
      {:ok, []} ->
        []

      {:ok, items} ->
        items |> Enum.filter(&(&1 != nil))

      {:error, reason} ->
        Logger.warn("Error popping items from Redis list '#{source_list}'. " <> inspect(reason))
        []
    end
  end

  defp pop_messages(_, _, _, _), do: []

  # atomically batch remove items from the working list using a pipelined command
  defp delete_message_batch(redis_instance, working_list, receipts) do
    pipeline_commands = Enum.map(receipts, fn %{id: id} -> ["LREM", working_list, -1, id] end)

    case Redix.pipeline(redis_instance, pipeline_commands, timeout: @default_pipeline_timeout) do
      {:error, reason} ->
        Logger.warn(
          "Error acknowledging items in Redis working list '#{working_list}'. " <> inspect(reason)
        )

        {:error, reason}

      result ->
        result
    end
  end
end
