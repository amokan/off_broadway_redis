defmodule OffBroadwayRedis.RedisClient do
  @moduledoc """
  A generic behaviour to implement Redis Clients for `OffBroadwayRedis.Producer`.

  This module defines callbacks to normalize options and receive items
  from a Redis list.

  Modules that implement this behaviour should be passed
  as the `:redis_client` option from `OffBroadwayRedis.Producer`.
  """

  alias Broadway.Message

  @type messages :: [Message.t()]

  @callback init(opts :: any) :: {:ok, normalized_opts :: any} | {:error, message :: binary}
  @callback receive_messages(demand :: pos_integer, opts :: any) :: messages
end
