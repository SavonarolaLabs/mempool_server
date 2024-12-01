Mix.Task.run("app.start")

{:ok, _} = Application.ensure_all_started(:hackney)

alias MempoolServer.Repo
alias MempoolServer.Constants

defmodule FetchTransactionsScript do
  @node_url "http://213.239.193.208:9053"

  def fetch_transactions(address, limit \\ 2) do
    url = "#{@node_url}/blockchain/transaction/byAddress?offset=0&limit=#{limit}"
    headers = [{"Content-Type", "text/plain"}]
    body = address

    IO.inspect(body, label: "Request Body")

    options = [recv_timeout: 30_000]

    case HTTPoison.post(url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        IO.puts("API Response: #{response_body}")
        case Jason.decode(response_body) do
          {:ok, %{"items" => items}} -> {:ok, items}
          {:ok, data} ->
            IO.puts("Unexpected JSON structure: #{inspect(data)}")
            {:error, :unexpected_json_structure}
          error ->
            IO.puts("JSON Decode Error: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: response_body}} ->
        IO.puts("API Error: #{status_code} - #{response_body}")
        {:error, %{status_code: status_code, body: response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        IO.puts("HTTP Request Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def save_transactions do
    address = Constants.sigma_bank_address()

    case fetch_transactions(address) do
      {:ok, transactions} when is_list(transactions) ->
        if transactions == [] do
          IO.puts("No transactions found for #{address}.")
        else
          Enum.each(transactions, fn tx ->
            tx_id = tx["id"]
            height = tx["inclusionHeight"]

            # Extract 'ergoTree' from the first output, if available
            ergo_tree =
              tx["outputs"]
              |> Enum.find_value(fn output ->
                if output["ergoTree"], do: output["ergoTree"], else: nil
              end)

            Repo.insert!(%MempoolServer.Transaction{
              tx_id: tx_id,
              ergo_tree: ergo_tree,
              data: Jason.encode!(tx),
              height: height
            })
          end)

          IO.puts("Saved #{length(transactions)} transactions for #{address}.")
        end

      {:error, reason} ->
        IO.puts("Error fetching transactions: #{inspect(reason)}")
    end
  end
end

FetchTransactionsScript.save_transactions()
