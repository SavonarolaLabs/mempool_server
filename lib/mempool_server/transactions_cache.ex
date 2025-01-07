defmodule MempoolServer.TransactionsCache do
  @moduledoc """
  An in-memory key-value store for tracking:
    - The creation_timestamp of each transaction.
    - The entire (enriched) transaction data for quick retrieval and broadcasting.
  """

  use GenServer

  @name __MODULE__

  ## ------------------------------------------------------------------
  ## Public API
  ## ------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %{timestamps: %{}, transactions: %{}}, name: @name)
  end

  @doc """
  Get the timestamp for a given tx_id. Returns `nil` if not present.
  """
  def get_timestamp(tx_id) do
    GenServer.call(@name, {:get_timestamp, tx_id})
  end

  @doc """
  Store the timestamp for a given tx_id. Overwrites any existing value.
  """
  def put_timestamp(tx_id, timestamp) do
    GenServer.call(@name, {:put_timestamp, tx_id, timestamp})
  end

  @doc """
  Remove from the cache (timestamps + transaction data) any tx_ids not in `active_tx_ids`.
  """
  def remove_unobserved_transactions(active_tx_ids) do
    GenServer.cast(@name, {:remove_unobserved, active_tx_ids})
  end

  @doc """
  Put (or update) all transactions in the cache. 
  This will store them in the `transactions` map keyed by tx_id.
  """
  def put_all_transactions(transactions) do
    GenServer.call(@name, {:put_all_transactions, transactions})
  end

  @doc """
  Returns the entire list of current mempool transactions.
  """
  def get_all_transactions() do
    GenServer.call(@name, :get_all_transactions)
  end

  @doc """
  Returns transactions matching the given ergo_trees.
  """
  def get_transactions_by_ergo_trees(ergo_trees) do
    GenServer.call(@name, {:get_transactions_by_ergo_trees, ergo_trees})
  end

  ## ------------------------------------------------------------------
  ## GenServer callbacks
  ## ------------------------------------------------------------------

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:get_timestamp, tx_id}, _from, state) do
    {:reply, Map.get(state.timestamps, tx_id), state}
  end

  @impl true
  def handle_call({:put_timestamp, tx_id, timestamp}, _from, state) do
    new_timestamps = Map.put(state.timestamps, tx_id, timestamp)
    new_state = %{state | timestamps: new_timestamps}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_all_transactions, _from, state) do
    all_txs = Map.values(state.transactions)
    {:reply, all_txs, state}
  end

  @impl true
  def handle_call({:get_transactions_by_ergo_trees, ergo_trees}, _from, state) do
    filtered_txs =
      state.transactions
      |> Map.values()
      |> Enum.filter(fn tx -> transaction_has_output?(tx, ergo_trees) end)

    {:reply, filtered_txs, state}
  end

  @impl true
  def handle_call({:put_all_transactions, transactions}, _from, state) do
    updated_transactions =
      Enum.reduce(transactions, state.transactions, fn tx, acc ->
        Map.put(acc, tx["id"], tx)
      end)

    new_state = %{state | transactions: updated_transactions}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:remove_unobserved, active_tx_ids}, state) do
    new_timestamps =
      Map.drop(state.timestamps, Map.keys(state.timestamps) -- active_tx_ids)

    new_transactions =
      Map.drop(state.transactions, Map.keys(state.transactions) -- active_tx_ids)

    new_state = %{timestamps: new_timestamps, transactions: new_transactions}
    {:noreply, new_state}
  end

  ## ------------------------------------------------------------------
  ## Helpers
  ## ------------------------------------------------------------------

  defp transaction_has_output?(transaction, ergo_trees) do
    outputs = transaction["outputs"] || []
    Enum.any?(outputs, fn output -> output["ergoTree"] in ergo_trees end)
  end
end
