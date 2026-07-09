defmodule CommandKit.Middleware.Idempotency do
  @moduledoc """
  Reuses successful command results for repeated dispatches.

  The middleware looks for `:idempotency_key` in the command's metadata by
  default (set it with `CommandKit.Command.put_metadata/3`). It stores only
  cacheable success results (`:ok`, `:unchanged`, and `{:ok, value}`).

  The command fingerprint is derived from the command module and its
  declared params only — never from `command_id` or metadata — so a retried
  command built fresh from the same params fingerprints identically.
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

    case metadata_get(CommandKit.Pipeline.metadata(pipeline), key_name) do
      nil -> nil
      "" -> nil
      token -> {command_fingerprint(pipeline.command), to_string(token)}
    end
  end

  defp command_fingerprint(command) do
    command_module = command.__struct__

    fingerprint_data =
      if function_exported?(command_module, :__command_kit_params__, 0) do
        params =
          Enum.map(command_module.__command_kit_params__(), fn field ->
            {field.name, Map.get(command, field.name)}
          end)

        {command_module, params}
      else
        {command_module, command |> Map.from_struct() |> Map.drop([:command_id, :metadata])}
      end

    fingerprint_data
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp metadata_get(%CommandKit.Metadata{} = metadata, key) do
    CommandKit.Metadata.get(metadata, key)
  end

  defp metadata_get(_metadata, _key), do: nil
end
