defmodule MempoolServer.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      add :tx_id, :string, null: false
      add :ergo_tree, :string, null: false
      add :data, :text, null: false
      add :height, :integer, null: false
      timestamps()
    end

    create unique_index(:transactions, [:tx_id])
    create index(:transactions, [:ergo_tree])
    create index(:transactions, [:height])
  end
end
