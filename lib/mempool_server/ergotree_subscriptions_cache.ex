defmodule MempoolServer.ErgoTreeSubscriptionsCache do
  use GenServer

  # API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def subscribe(ergo_tree, pid \\ self()) do
    GenServer.call(__MODULE__, {:subscribe, ergo_tree, pid})
  end

  def unsubscribe(ergo_tree, pid \\ self()) do
    GenServer.call(__MODULE__, {:unsubscribe, ergo_tree, pid})
  end

  def get_subscribers(ergo_tree) do
    GenServer.call(__MODULE__, {:get_subscribers, ergo_tree})
  end

  def get_all_subscriptions do
    GenServer.call(__MODULE__, :get_all_subscriptions)
  end

  # GenServer Callbacks

  def init(_) do
    {:ok, %{}}
  end

  def handle_call({:subscribe, ergo_tree, pid}, _from, state) do
    subscribers = Map.get(state, ergo_tree, MapSet.new()) |> MapSet.put(pid)
    {:reply, :ok, Map.put(state, ergo_tree, subscribers)}
  end

  def handle_call({:unsubscribe, ergo_tree, pid}, _from, state) do
    subscribers = Map.get(state, ergo_tree, MapSet.new()) |> MapSet.delete(pid)

    new_state =
      if MapSet.size(subscribers) == 0 do
        Map.delete(state, ergo_tree)
      else
        Map.put(state, ergo_tree, subscribers)
      end

    {:reply, :ok, new_state}
  end

  def handle_call({:get_subscribers, ergo_tree}, _from, state) do
    {:reply, Map.get(state, ergo_tree, MapSet.new()), state}
  end

  def handle_call(:get_all_subscriptions, _from, state) do
    {:reply, state, state}
  end
end
