defmodule OffBroadwayRedis.ProducerTest do
  use ExUnit.Case

  alias Broadway.Message

  defmodule MessageServer do
    def start_link() do
      Agent.start_link(fn -> [] end)
    end

    def push_messages(server, messages) do
      Agent.update(server, fn queue -> queue ++ messages end)
    end

    def take_messages(server, amount) do
      Agent.get_and_update(server, &Enum.split(&1, amount))
    end
  end

  defmodule FakeRedisClient do
    @behaviour OffBroadwayRedis.RedisClient
    @behaviour Broadway.Acknowledger

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def receive_messages(amount, opts) do
      messages = MessageServer.take_messages(opts[:message_server], amount)
      send(opts[:test_pid], {:messages_received, length(messages)})

      for msg <- messages do
        ack_data = %{
          receipt: %{id: "Id_#{msg}", receipt_handle: "ReceiptHandle_#{msg}"},
          test_pid: opts[:test_pid]
        }

        %Message{data: msg, acknowledger: {__MODULE__, :ack_ref, ack_data}}
      end
    end

    @impl true
    def ack(_ack_ref, successful, _failed) do
      [%Message{acknowledger: {_, _, %{test_pid: test_pid}}} | _] = successful
      send(test_pid, {:messages_deleted, length(successful)})
    end
  end

  defmodule Forwarder do
    use Broadway

    def handle_message(_, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data})
      message
    end

    def handle_batch(_, messages, _, _) do
      messages
    end
  end

  test "raise an ArgumentError with proper message when the redis_instance option is nil" do
    assert_raise(
      ArgumentError,
      "invalid options given to OffBroadwayRedis.RedixClient.init/1, expected :redis_instance to be a atom, got: nil",
      fn ->
        OffBroadwayRedis.Producer.init(
          redis_instance: nil,
          list_name: "foo",
          working_list_name: "bar"
        )
      end
    )
  end

  test "raise an ArgumentError with proper message when the redis_instance option is invalid" do
    assert_raise(
      ArgumentError,
      "invalid options given to OffBroadwayRedis.RedixClient.init/1, expected :redis_instance to be a atom, got: \"my_redis_instance\"",
      fn ->
        OffBroadwayRedis.Producer.init(
          redis_instance: "my_redis_instance",
          list_name: "foo",
          working_list_name: "bar"
        )
      end
    )
  end

  test "raise an ArgumentError with proper message when the list_name option is nil" do
    assert_raise(
      ArgumentError,
      "invalid options given to OffBroadwayRedis.RedixClient.init/1, expected :list_name to be a non empty string, got: nil",
      fn ->
        OffBroadwayRedis.Producer.init(
          redis_instance: :my_redis_instance,
          list_name: nil,
          working_list_name: "bar"
        )
      end
    )
  end

  test "raise an ArgumentError with proper message when the list_name option is empty" do
    assert_raise(
      ArgumentError,
      "invalid options given to OffBroadwayRedis.RedixClient.init/1, expected :list_name to be a non empty string, got: \"\"",
      fn ->
        OffBroadwayRedis.Producer.init(
          redis_instance: :my_redis_instance,
          list_name: "",
          working_list_name: "bar"
        )
      end
    )
  end

  test "raise an ArgumentError with proper message when the working_list_name option is nil" do
    assert_raise(
      ArgumentError,
      "invalid options given to OffBroadwayRedis.RedixClient.init/1, expected :working_list_name to be a non empty string, got: nil",
      fn ->
        OffBroadwayRedis.Producer.init(
          redis_instance: :my_redis_instance,
          list_name: "foo",
          working_list_name: nil
        )
      end
    )
  end

  test "raise an ArgumentError with proper message when the working_list_name option is empty" do
    assert_raise(
      ArgumentError,
      "invalid options given to OffBroadwayRedis.RedixClient.init/1, expected :working_list_name to be a non empty string, got: \"\"",
      fn ->
        OffBroadwayRedis.Producer.init(
          redis_instance: :my_redis_instance,
          list_name: "foo",
          working_list_name: ""
        )
      end
    )
  end

  test "receive messages when the queue has less than the demand" do
    {:ok, message_server} = MessageServer.start_link()
    {:ok, pid} = start_broadway(message_server)

    MessageServer.push_messages(message_server, 1..5)

    assert_receive {:messages_received, 5}

    for msg <- 1..5 do
      assert_receive {:message_handled, ^msg}
    end

    stop_broadway(pid)
  end

  test "keep receiving messages when the queue has more than the demand" do
    {:ok, message_server} = MessageServer.start_link()
    MessageServer.push_messages(message_server, 1..20)
    {:ok, pid} = start_broadway(message_server)

    assert_receive {:messages_received, 10}

    for msg <- 1..10 do
      assert_receive {:message_handled, ^msg}
    end

    assert_receive {:messages_received, 5}

    for msg <- 11..15 do
      assert_receive {:message_handled, ^msg}
    end

    assert_receive {:messages_received, 5}

    for msg <- 16..20 do
      assert_receive {:message_handled, ^msg}
    end

    assert_receive {:messages_received, 0}

    stop_broadway(pid)
  end

  test "keep trying to receive new messages when the queue is empty" do
    {:ok, message_server} = MessageServer.start_link()
    {:ok, pid} = start_broadway(message_server)

    MessageServer.push_messages(message_server, [13])
    assert_receive {:messages_received, 1}
    assert_receive {:message_handled, 13}

    assert_receive {:messages_received, 0}
    refute_receive {:message_handled, _}

    MessageServer.push_messages(message_server, [14, 15])
    assert_receive {:messages_received, 2}
    assert_receive {:message_handled, 14}
    assert_receive {:message_handled, 15}

    stop_broadway(pid)
  end

  test "delete acknowledged messages" do
    {:ok, message_server} = MessageServer.start_link()
    {:ok, pid} = start_broadway(message_server)

    MessageServer.push_messages(message_server, 1..20)

    assert_receive {:messages_deleted, 10}
    assert_receive {:messages_deleted, 10}

    stop_broadway(pid)
  end

  defp start_broadway(message_server) do
    Broadway.start_link(Forwarder,
      name: new_unique_name(),
      context: %{test_pid: self()},
      producers: [
        default: [
          module:
            {OffBroadwayRedis.Producer,
             redis_client: FakeRedisClient,
             receive_interval: 0,
             redis_instance: :fake_redis_instance,
             list_name: "some_list",
             working_list_name: "some_list_processing",
             test_pid: self(),
             message_server: message_server},
          stages: 1
        ]
      ],
      processors: [
        default: [stages: 1]
      ],
      batchers: [
        default: [
          batch_size: 10,
          batch_timeout: 50,
          stages: 1
        ]
      ]
    )
  end

  defp new_unique_name() do
    :"Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  defp stop_broadway(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end
end
