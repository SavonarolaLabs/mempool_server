defmodule MempoolServer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Process.flag(:trap_exit, true)

    children = [
      MempoolServerWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:mempool_server, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MempoolServer.PubSub},
      MempoolServer.NodeCache,
      MempoolServer.ErgoTreeSubscriptionsCache,
      MempoolServer.BoxCache,
      MempoolServer.TxHistoryCache,
      {MempoolServer.TransactionsCache, []},
      MempoolServer.BoxHistoryCache,
      MempoolServer.MempoolFetcher,
      MempoolServerWeb.Endpoint
    ]

    opts = [strategy: :one_for_all, name: MempoolServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MempoolServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
