# OffBroadway.Redis

[![Build Status](https://travis-ci.org/amokan/off_broadway_redis.svg?branch=master)](https://travis-ci.org/amokan/off_broadway_redis)
[![Hex.pm](https://img.shields.io/hexpm/v/off_broadway_redis.svg)](https://hex.pm/packages/off_broadway_redis)

An _opinionated_ Redis connector for [Broadway](https://github.com/plataformatec/broadway) to process work from a Redis list structure.

Documentation can be found at [https://hexdocs.pm/off_broadway_redis](https://hexdocs.pm/off_broadway_redis).

This project provides:

* `OffBroadway.Redis.Producer` - A GenStage producer that continuously pops items from a Redis list and acknowledges them after being successfully processed.
* `OffBroadway.Redis.RedisClient` - A generic behaviour to implement Redis clients.
* `OffBroadway.Redis.RedixClient` - Default Redis client used by `OffBroadway.Redis.Producer`.

## What is opinionated about this library?

Because Redis lists do not support the concept of acknowledgements, this project utilizes the [RPOPLPUSH](https://redis.io/commands/rpoplpush) command available in Redis to atomically pop an item from the list while moving the item to a 'working' or 'processing' list for a later pseudo-acknowledgement using the `LREM` command.

This idea follows the blueprint of the _Reliable Queue_ pattern outlined in the Redis documentation found [here](https://redis.io/commands/rpoplpush#pattern-reliable-queue).

Because `RPOPLPUSH` is used, the other assumption is that the head of your list will be on the right side, so you will likely want to push work into your list using `LPUSH` (for FIFO processing). If you want to prioritize an item to be processed next, you could push that to the right (head) by using a `RPUSH`.

## Redis Client

The default Redis client uses the [Redix](https://github.com/whatyouhide/redix) library. See that project for other features.

I have not attempted to use any other Redis libraries in the community at this point. I expect there may need to be changes made to this producer to accomodate others.

## Caveats

* You are responsible for maintaining your own named connection to Redis outside the scope of this library. See the [Real-World Usage](https://hexdocs.pm/redix/real-world-usage.html) docs for Redix for setting up a named instance/connection.
* At this point, no testing has been done with a pooling strategy around Redis. I am using a single connection dedicated for my broadway pipeline in a small system. Ideally I would like to improve this to the point where just the Redis host, port, and credentials are provided to this provider for handling it's own connections/pooling.
* You are responsible for monitoring your working/processing list in Redis. If something goes wrong and an acknowledgement (`LREM`) is not handled - you will want some logic or process in place to move an item from the working list back to the main list.
* The Redis `LREM` command is _O(N)_ - so the performance on this operation during acknowledgement will be based on the length of the list. I have been using this pattern for a number of years without problem, but be aware and do research on your own use-case to ensure this is not going to be a problem for you.

----

## Installation

Add `:off_broadway_redis` to the list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_redis, "~> 0.4.2"}
  ]
end
```

## Usage

Configure Broadway with one or more producers using `OffBroadway.Redis.Producer`:

```elixir
Broadway.start_link(MyBroadway,
  name: MyBroadway,
  producers: [
    default: [
      module: {
        OffBroadway.Redis.Producer,
        redis_instance: :some_redis_instance,
        list_name: "some_list",
        working_list_name: "some_list_processing"
      }
    ]
  ]
)
```

----

## Other Info

This library was created using the [Broadway Custom Producers documentation](https://hexdocs.pm/broadway/custom-producers.html) for reference. I would encourage you to view that as well as the [Broadway Architecture documentation](https://hexdocs.pm/broadway/architecture.html) for more information.

----

## License

MIT License

See the [license file](LICENSE.txt) for details.
