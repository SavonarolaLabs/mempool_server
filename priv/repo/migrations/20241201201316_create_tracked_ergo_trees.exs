defmodule MempoolServer.Repo.Migrations.CreateTrackedErgoTrees do
  use Ecto.Migration

  def change do
    create table(:tracked_ergo_trees) do
      add :ergo_tree, :text, null: false
      add :known_amount, :bigint, null: false, default: 0

      timestamps()
    end

    create unique_index(:tracked_ergo_trees, [:ergo_tree])
  end
end
