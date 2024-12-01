defmodule MempoolServer.Transaction do
  use Ecto.Schema

  @derive {Jason.Encoder, only: [:id, :tx_id, :ergo_tree, :data, :height, :inserted_at, :updated_at]}
  schema "transactions" do
    field :tx_id, :string
    field :ergo_tree, :string
    field :data, :string
    field :height, :integer

    timestamps()
  end
end
