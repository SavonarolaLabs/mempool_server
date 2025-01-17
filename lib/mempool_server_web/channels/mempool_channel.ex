defmodule MempoolServerWeb.MempoolChannel do
  use Phoenix.Channel

  alias MempoolServer.TransactionsCache
  alias MempoolServer.TxHistoryCache
  alias MempoolServer.BoxHistoryCache
  alias MempoolServer.Constants
  alias MempoolServer.ErgoTreeSubscriptionsCache

  # -------------------------------------------
  #  Join "mempool:oracle_boxes"
  # -------------------------------------------
  @impl true
  def join("mempool:oracle_boxes", _message, socket) do
    all_boxes = BoxHistoryCache.get_all_boxes()

    confirmed_payload =
      all_boxes
      |> Enum.reduce(%{}, fn {name, boxes}, acc ->
        Map.put(acc, "confirmed_#{name}", boxes)
      end)

    unconfirmed_payload =
      Constants.boxes_by_token_id()
      |> Enum.reduce(%{}, fn %{name: name, token_id: token_id}, acc ->
        transactions = TransactionsCache.get_all_transactions()

        unconfirmed_boxes =
          transactions
          |> Enum.flat_map(fn tx -> tx["outputs"] || [] end)
          |> Enum.filter(fn output ->
            Enum.any?(output["assets"] || [], fn asset ->
              asset["tokenId"] == token_id
            end)
          end)

        Map.put(acc, "unconfirmed_#{name}", unconfirmed_boxes)
      end)

    reply_payload = Map.merge(confirmed_payload, unconfirmed_payload)
    {:ok, reply_payload, socket}
  end

  # -------------------------------------------
  #  Join "mempool:transactions"
  # -------------------------------------------
  @impl true
  def join("mempool:transactions", _message, socket) do
    all_transactions = TransactionsCache.get_all_transactions()

    reply_payload = %{
      unconfirmed_transactions: all_transactions,
      confirmed_transactions: []
    }

    {:ok, reply_payload, socket}
  end

  # -------------------------------------------
  #  Join filtered transaction channels
  # -------------------------------------------
  @impl true
  def join("mempool:" <> name, _message, socket) do
    case Enum.find(Constants.filtered_transactions(), fn ft -> ft.name == name end) do
      nil ->
        {:error, %{reason: "Invalid channel name"}}

      %{ergo_trees: ergo_trees} ->
        unconfirmed_transactions = TransactionsCache.get_transactions_by_ergo_trees(ergo_trees)
        history = TxHistoryCache.get_recent(name)

        reply_payload = %{
          unconfirmed_transactions: unconfirmed_transactions,
          confirmed_transactions: [],
          history: history
        }

        {:ok, reply_payload, socket}
    end
  end

  # -------------------------------------------
  #  Join "ergotree:" <ergotree>
  # -------------------------------------------
  @impl true
  def join("ergotree:" <> ergo_tree, _message, socket) do
    ErgoTreeSubscriptionsCache.subscribe(ergo_tree)

    ergo_trees = [ergo_tree]
    unconfirmed_transactions =
      TransactionsCache.get_transactions_by_ergo_trees(ergo_trees)

    reply_payload = %{unconfirmed_transactions: unconfirmed_transactions, confirmed_transactions: []}

    {:ok, reply_payload, assign(socket, :ergo_tree, ergo_tree)}
  end

    # -------------------------------------------
  #  Handle inbound "submit_tx" event
  # -------------------------------------------
  @impl true
  def handle_in("submit_tx", %{"transaction" => transaction}, socket) do
    # Perform the transaction check via HTTP
    case check_transaction(transaction) do
      {:ok, _response} ->
        # If the check is successful, submit the transaction
        case submit_transaction(transaction) do
          {:ok, submit_response} ->
            # Broadcast the transaction and reply with success
            #broadcast!(socket, "sigmausd_transactions", payload)
            {:reply, {:ok, %{status: "success", detail: "Transaction submitted", response: submit_response}}, socket}
  
          {:error, submit_error} ->
            # Handle transaction submission error
            {:reply, {:error, %{status: "error", detail: "Transaction submission failed", error: submit_error}}, socket}
        end
  
      {:error, check_error} ->
        # Handle transaction check failure
        {:reply, {:error, %{status: "error", detail: "Transaction check failed", error: check_error}}, socket}
    end
  end

  # -------------------------------------------
  #  Handle inbound events (not used here)
  # -------------------------------------------
  def handle_in(_event, _params, socket) do
    {:noreply, socket}
  end

  defp check_transaction(transaction) do
    url = "#{Constants.node_url()}/transactions/check"
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
    body = Jason.encode!(transaction)
  
    case HTTPoison.post(url, body, headers, []) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, parsed_response} -> {:ok, parsed_response}
          _ -> {:error, "Invalid JSON response from transaction check"}
        end
  
      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        {:error, "Transaction check failed with status #{status_code}: #{response_body}"}
  
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request error: #{inspect(reason)}"}
    end
  end
  
  defp submit_transaction(transaction) do
    url = "#{Constants.node_url()}/transactions"
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
    body = Jason.encode!(transaction)
  
    case HTTPoison.post(url, body, headers, []) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, parsed_response} -> {:ok, parsed_response}
          _ -> {:error, "Invalid JSON response from transaction submission"}
        end
  
      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        {:error, "Transaction submission failed with status #{status_code}: #{response_body}"}
  
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP request error: #{inspect(reason)}"}
    end
  end

  # -------------------------------------------
  #  Handle channel termination (unsubscribe)
  # -------------------------------------------
  @impl true
  def terminate(_reason, socket) do
    if ergo_tree = socket.assigns[:ergo_tree] do
      ErgoTreeSubscriptionsCache.unsubscribe(ergo_tree)
    end

    :ok
  end
end
