defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  alias MempoolServer.TransactionsCache
  alias MempoolServer.Constants


  @polling_interval 10_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_poll()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    fetch_and_broadcast()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end

  defp fetch_and_broadcast do
    transactions = fetch_all_mempool_transactions()
    new_tx_ids = Enum.map(transactions, & &1["id"])
    TransactionsCache.remove_unobserved_transactions(new_tx_ids)

    enriched_transactions =
      Enum.map(transactions, fn tx ->
        tx_id = tx["id"]

        # If not in the cache, store "now" as its creation time
        creation_ts =
          case TransactionsCache.get_timestamp(tx_id) do
            nil ->
              now_ms = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
              TransactionsCache.put_timestamp(tx_id, now_ms)
              now_ms

            existing_ts ->
              existing_ts
          end

        Map.put(tx, "creationTimestamp", creation_ts)
      end)

    # 5. Broadcast to channels
    broadcast_all_transactions(enriched_transactions)
    broadcast_sigmausd_transactions(enriched_transactions)
  end

  defp fetch_all_mempool_transactions(offset \\ 0, transactions \\ []) do
    url = "#{Constants.node_url()}/transactions/unconfirmed?limit=10000&offset=#{offset}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, data} = Jason.decode(body)

        # If we got exactly 10,000, there's possibly more. Keep paginating.
        if length(data) == 10_000 do
          fetch_all_mempool_transactions(offset + 10_000, transactions ++ data)
        else
          transactions ++ data
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching mempool transactions: #{inspect(reason)}")
        transactions
    end
  end

  defp broadcast_all_transactions(transactions) do
    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:transactions",
      "all_transactions",
      %{transactions: transactions}
    )
  end

  defp broadcast_sigmausd_transactions(transactions) do
    sigmausd_transactions = Enum.filter(transactions, &transaction_has_sigmausd_output?/1)

    MempoolServerWeb.Endpoint.broadcast!(
      "mempool:sigmausd_transactions",
      "sigmausd_transactions",
      %{transactions: sigmausd_transactions}
    )
  end

  defp transaction_has_sigmausd_output?(transaction) do
    outputs = transaction["outputs"] || []

    Enum.any?(outputs, fn output ->
      output["ergoTree"] == Constants.sigmausd_ergo_tree()
    end)
  end
end
