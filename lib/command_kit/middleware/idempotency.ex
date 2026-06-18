defmodule CommandKit.Middleware.Idempotency do
  @moduledoc """
  Reuses successful command results for repeated dispatches.

  The middleware looks for `:idempotency_key` in metadata by default. It stores
  only cacheable success results (`:ok`, `:unchanged`, and `{:ok, value}`).
  """

  @behaviour CommandKit.Middleware

  @impl true
  def call(pipeline, next, opts) do
    case idempotency_key(pipeline, opts) do
      nil ->
        next.(pipeline)

      key ->
        store = Keyword.get(opts, :store, CommandKit.IdempotencyStore)

        case store.fetch(key) do
          {:ok, result} ->
            CommandKit.Pipeline.halt(pipeline, result)

          :miss ->
            next_pipeline = next.(pipeline)

            if CommandKit.Result.cacheable?(next_pipeline.result) do
              store.put(key, next_pipeline.result, Keyword.get(opts, :ttl_ms, :timer.hours(24)))
            end

            next_pipeline
        end
    end
  end

  defp idempotency_key(pipeline, opts) do
    key_name = Keyword.get(opts, :metadata_key, :idempotency_key)

    case metadata_get(pipeline.metadata, key_name) do
      nil -> nil
      "" -> nil
      token -> {command_fingerprint(pipeline.command), to_string(token)}
    end
  end

  defp command_fingerprint(command) do
    command
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp metadata_get(metadata, key) when is_list(metadata), do: Keyword.get(metadata, key)
  defp metadata_get(metadata, key) when is_map(metadata), do: Map.get(metadata, key)
end
