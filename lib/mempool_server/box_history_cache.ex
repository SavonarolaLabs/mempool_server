defmodule MempoolServer.BoxHistoryCache do
    use GenServer
    require Logger
    alias MempoolServer.Constants
  
    @table_name :box_history_cache
  
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
  
    def get_all_boxes() do
      :ets.tab2list(@table_name)
    end
  
    def update_history(name) do
      case Constants.boxes_by_token_id() |> Enum.find(&(&1.name == name)) do
        nil ->
          Logger.error("Box with name #{name} not found.")
          :error
  
        %{token_id: token_id} ->
          boxes = fetch_confirmed_box_by_token_id(token_id)
          :ets.insert(@table_name, {name, boxes})
          :ok
      end
    end
  
    def update_all_history() do
      Constants.boxes_by_token_id()
      |> Enum.each(fn %{name: name, token_id: token_id} ->
        boxes = fetch_confirmed_box_by_token_id(token_id)
        :ets.insert(@table_name, {name, boxes})
      end)
      :ok
    end
  
    defp fetch_confirmed_box_by_token_id(token_id) do
      base_url = Constants.node_url()
      url = "#{base_url}/blockchain/box/unspent/byTokenId/#{token_id}?offset=0&limit=1&sortDirection=desc&includeUnconfirmed=false"
  
      case HTTPoison.get(url, [{"accept", "application/json"}]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, data} when is_list(data) -> data
            {:error, _} -> []
          end
  
        {:error, reason} ->
          Logger.error("Failed to fetch boxes for token_id #{token_id}: #{inspect(reason)}")
          []
      end
    end
  end
  