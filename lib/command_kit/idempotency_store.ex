defmodule CommandKit.IdempotencyStore do
  @moduledoc """
  ETS-backed store used by `CommandKit.Middleware.Idempotency`.

  The table is created lazily so applications can use the middleware without
  adding a supervisor child. `start_link/1` is available for applications that
  prefer explicit startup.
  """

  use GenServer

  @table __MODULE__
  @default_ttl_ms :timer.hours(24)
  @sweep_interval_ms :timer.minutes(5)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec fetch(term()) :: {:ok, term()} | :miss
  def fetch(key) do
    ensure_table()
    now = now_ms()

    case :ets.lookup(@table, key) do
      [{^key, result, expires_at}] when expires_at > now -> {:ok, result}
      [{^key, _result, _expires_at}] -> :ets.delete(@table, key) && :miss
      [] -> :miss
    end
  end

  @spec put(term(), term(), non_neg_integer()) :: :ok
  def put(key, result, ttl_ms \\ @default_ttl_ms) do
    ensure_table()
    :ets.insert(@table, {key, result, now_ms() + ttl_ms})
    :ok
  end

  @impl true
  def init(_opts) do
    ensure_table()
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(now_ms())
    schedule_sweep()
    {:noreply, state}
  end

  defp sweep(now) do
    ensure_table()
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :set,
            :named_table,
            :public,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError -> @table
        end

      _tid ->
        @table
    end
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
  defp now_ms, do: System.monotonic_time(:millisecond)
end
