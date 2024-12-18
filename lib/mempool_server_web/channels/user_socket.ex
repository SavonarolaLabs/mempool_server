defmodule MempoolServerWeb.UserSocket do
    use Phoenix.Socket
  
    channel "mempool:*", MempoolServerWeb.MempoolChannel
  
    # No authentication required for this example
    def connect(_params, socket, _connect_info) do
      {:ok, socket}
    end
  
    def id(_socket), do: nil
  end
  