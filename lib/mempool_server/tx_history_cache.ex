defmodule MempoolServer.TxHistoryCache do
  use GenServer
  require Logger

  alias MempoolServer.Constants

  @table_name :tx_history_cache
  @timeout_opts [hackney: [recv_timeout: 60_000, connect_timeout: 60_000]]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      {:read_concurrency, true}
    ])

    {:ok, state}
  end

  @doc """
  Updates the TxHistory for the given transaction name.

  - If one of the fetches fails, it logs a warning and proceeds with any
    successful fetches from the other addresses. No crash occurs.
  """
  def update_history(name) do
    case Enum.find(Constants.filtered_transactions(), &(&1.name == name)) do
      nil ->
        :ok

      %{addresses: addresses} ->
        addresses
        |> Enum.reduce([], fn address, acc ->
          case fetch_transactions_by_address(address) do
            {:ok, new_txs} ->
              acc ++ new_txs

            :error ->
              Logger.warning("[TxHistoryCache] Skipping failed fetch for address: #{address}")
              acc
          end
        end)
        |> case do
          [] ->
            Logger.warning("[TxHistoryCache] No transactions to update for #{name}.")
            :ok

          all_txs ->
            store_transactions(name, all_txs)
            :ok
        end
    end
  end

  def get_recent(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, txs}] -> txs
      [] -> []
    end
  end

  @doc """
  Clears any existing records for `name` and stores a new, de-duplicated list
  of transactions. No 30-item limit is enforced.
  """
  defp store_transactions(name, new_txs) do
    :ets.delete(@table_name, name)
    deduped = Enum.uniq_by(new_txs, & &1["id"])
    :ets.insert(@table_name, {name, deduped})
    :ok
  end

  defp fetch_transactions_by_address(address) do
    url = "#{Constants.node_url()}/blockchain/transaction/byAddress?offset=0&limit=10"
    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    case HTTPoison.post(url, Jason.encode!(address), headers, @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"items" => items}} when is_list(items) ->
            {:ok, items}

          {:ok, other} ->
            Logger.error("[TxHistoryCache] Unexpected JSON structure: #{inspect(other)}")
            :error

          error ->
            Logger.error("[TxHistoryCache] Could not decode body: #{inspect(error)}")
            :error
        end

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        Logger.error("[TxHistoryCache] HTTP #{code} => #{body}")
        :error

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[TxHistoryCache] Request failed => #{inspect(reason)}")
        :error
    end
  end
end
