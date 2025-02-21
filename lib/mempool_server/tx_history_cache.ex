defmodule MempoolServer.TxHistoryCache do
  @moduledoc """
  Cache that stores the last 10 most recent transactions by address.
  """

  use GenServer
  require Logger

  alias MempoolServer.Constants

  @table_name :tx_history_cache
  @timeout_opts [hackney: [recv_timeout: 60_000, connect_timeout: 60_000]]

  # ----------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------

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

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  @doc """
  Update the TxHistory for the given transaction name.
  Supports multiple filtered transaction types from Constants.
  """
  def update_history(name) do
    case Enum.find(Constants.filtered_transactions(), fn ft -> ft.name == name end) do
      nil ->
        :ok

      %{addresses: addresses} ->
        addresses
        |> Enum.reduce([], fn address, acc ->
          case fetch_transactions_by_address(address) do
            {:ok, new_txs} -> acc ++ new_txs
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

  @doc """
  Retrieve the recently cached transactions for a given transaction name.
  """
  def get_recent(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, txs}] -> txs
      [] -> []
    end
  end

  # ----------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------

  defp store_transactions(name, new_txs) when is_binary(name) and is_list(new_txs) do
    existing = get_recent(name)
    updated = (new_txs ++ existing) |> Enum.take(30)
    :ets.insert(@table_name, {name, updated})
    :ok
  end

  defp fetch_transactions_by_address(address) do
    url = "#{Constants.node_url()}/blockchain/transaction/byAddress?offset=0&limit=10"
    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
    body = Jason.encode!(address)

    case HTTPoison.post(url, body, headers, @timeout_opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"items" => items}} when is_list(items) ->
            {:ok, items}

          {:ok, other} ->
            Logger.error("[TxHistoryCache] Unexpected JSON structure: #{inspect(other)}")
            :error

          error ->
            Logger.error("[TxHistoryCache] Could not decode body: #{inspect(error)}")
            :error
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        Logger.error("[TxHistoryCache] HTTP #{status_code} => #{response_body}")
        :error

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("[TxHistoryCache] Request failed => #{inspect(reason)}")
        :error
    end
  end
end
