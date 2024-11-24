defmodule MempoolServer.MempoolFetcher do
  use GenServer
  require Logger

  @node_url "http://213.239.193.208:9053"
  @polling_interval 1000
  @token_bank_nft "7d672d1def471720ca5782fd6473e47e796d9ac0c138d9911346f118b2f6d9d9"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_state) do
    schedule_poll()
    {:ok, %{}}
  end

  def handle_info(:poll, state) do
    new_state = fetch_and_broadcast(state)
    schedule_poll()
    {:noreply, new_state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @polling_interval)
  end

  defp fetch_and_broadcast(state) do
    transactions = fetch_all_mempool_transactions()
    broadcast_all_transactions(transactions)
    broadcast_bank_box_chains(transactions)
    state
  end

  defp fetch_all_mempool_transactions(offset \\ 0, transactions \\ []) do
    url = "#{@node_url}/transactions/unconfirmed?limit=10000&offset=#{offset}"
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, data} = Jason.decode(body)
        if length(data) == 10000 do
          fetch_all_mempool_transactions(offset + 10000, transactions ++ data)
        else
          transactions ++ data
        end
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Error fetching mempool transactions: #{inspect(reason)}")
        transactions
    end
  end

  defp broadcast_all_transactions(transactions) do
    MempoolServerWeb.Endpoint.broadcast!("mempool:transactions", "all_transactions", %{transactions: transactions})
  end

  defp broadcast_bank_box_chains(transactions) do
    chains = build_bank_box_chains(transactions)
    MempoolServerWeb.Endpoint.broadcast!("mempool:transactions", "bank_box_chains", %{chains: chains})
  end

  defp build_bank_box_chains(transactions) do
    # Implementation remains unchanged, focusing on bank box chain logic
    # (use the build_bank_box_chains and traverse_bank_box_chain logic from your original code)
  end
end
