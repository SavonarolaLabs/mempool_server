defmodule MempoolServer.NodeCache do
    use GenServer
  
    @table_name :node_info_cache
  
    def start_link(_opts) do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end
  
    def init(state) do
      :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
      {:ok, state}
    end
  
    def put_node_info(info) do
      :ets.insert(@table_name, {:node_info, info})
    end
  
    def get_node_info do
      case :ets.lookup(@table_name, :node_info) do
        [{:node_info, data}] -> data
        _ -> %{}
      end
    end
  end
  