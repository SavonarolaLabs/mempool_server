defmodule MempoolServer.TrackedErgoTree do
    use Ecto.Schema
    import Ecto.Changeset
  
    @derive {Jason.Encoder, only: [:id, :ergo_tree, :known_amount, :inserted_at, :updated_at]}
    schema "tracked_ergo_trees" do
      field :ergo_tree, :string
      field :known_amount, :integer, default: 0
  
      timestamps()
    end
  
    @doc false
    def changeset(tracked_ergo_tree, attrs) do
      tracked_ergo_tree
      |> cast(attrs, [:ergo_tree, :known_amount])
      |> validate_required([:ergo_tree])
      |> unique_constraint(:ergo_tree)
    end
  end
  