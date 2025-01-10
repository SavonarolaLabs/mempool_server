defmodule MempoolServerWeb.UserSocket do
  use Phoenix.Socket

  channel "mempool:*", MempoolServerWeb.MempoolChannel
  channel "ergotree:*", MempoolServerWeb.MempoolChannel

  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  def id(_socket), do: nil
end
