defmodule MempoolServerWeb.MempoolChannel do
    use Phoenix.Channel
  
    def join("mempool:transactions", _message, socket) do
      {:ok, socket}
    end
  
    def handle_in(_event, _params, socket) do
      {:noreply, socket}
    end
  end
  