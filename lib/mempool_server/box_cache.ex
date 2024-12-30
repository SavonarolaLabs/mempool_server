defmodule MempoolServer.BoxCache do
    @moduledoc """
    Caches box data so we don't spam the node with repeated requests.
    """
  
    use GenServer
  
    ## Public API
  
    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end
  
    @doc "Put box data into the cache."
    def put_box(box_id, box_data) do
      GenServer.call(__MODULE__, {:put_box, box_id, box_data})
    end
  
    @doc "Get box data from the cache. Returns `nil` if not found."
    def get_box(box_id) do
      GenServer.call(__MODULE__, {:get_box, box_id})
    end
  
    @doc """
    Removes from the cache any boxes whose IDs are *not* in `observed_box_ids`.
    This ensures stale/unobserved boxes are evicted.
    """
    def remove_unobserved_boxes(observed_box_ids) do
      GenServer.call(__MODULE__, {:remove_unobserved_boxes, observed_box_ids})
    end
  
    ## GenServer callbacks
  
    @impl true
    def init(state) do
      # `state` is just a Map of boxId => boxData
      {:ok, state}
    end
  
    @impl true
    def handle_call({:put_box, box_id, box_data}, _from, state) do
      new_state = Map.put(state, box_id, box_data)
      {:reply, :ok, new_state}
    end
  
    def handle_call({:get_box, box_id}, _from, state) do
      {:reply, Map.get(state, box_id), state}
    end
  
    def handle_call({:remove_unobserved_boxes, observed_box_ids}, _from, state) do
      # Drop everything not in the `observed_box_ids` list
      new_state = Map.drop(state, Map.keys(state) -- observed_box_ids)
      {:reply, :ok, new_state}
    end
  end
  