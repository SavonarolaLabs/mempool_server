defmodule MempoolServer.Transaction do
    use Ecto.Schema
  
    schema "transactions" do
      field :tx_id, :string
      field :ergo_tree, :string
      field :data, :string
      field :height, :integer
  
      timestamps()
    end
  end
  