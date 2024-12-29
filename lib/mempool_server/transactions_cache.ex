defmodule MempoolServer.TransactionsCache do
    @moduledoc """
    An in-memory key-value store for tracking the creation_timestamp of each transaction.
    """
  
    use GenServer
  
    @name __MODULE__
  
    ## ------------------------------------------------------------------
    ## Public API
    ## ------------------------------------------------------------------
  
    def start_link(_opts \\ []) do
      GenServer.start_link(__MODULE__, %{}, name: @name)
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
    Remove from the cache any tx_ids not in `active_tx_ids`.
    """
    def remove_unobserved_transactions(active_tx_ids) do
      GenServer.cast(@name, {:remove_unobserved, active_tx_ids})
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
      {:reply, Map.get(state, tx_id), state}
    end
  
    @impl true
    def handle_call({:put_timestamp, tx_id, timestamp}, _from, state) do
      new_state = Map.put(state, tx_id, timestamp)
      {:reply, :ok, new_state}
    end
  
    @impl true
    def handle_cast({:remove_unobserved, active_tx_ids}, state) do
      # Drop everything from 'state' that is NOT in the list of active tx_ids
      new_state = Map.drop(state, Map.keys(state) -- active_tx_ids)
      {:noreply, new_state}
    end
  end
  