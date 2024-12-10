defmodule MempoolServerWeb.TrackedErgoTreeController do
  use MempoolServerWeb, :controller
  import Ecto.Query

  alias MempoolServer.{Repo, TrackedErgoTree, Transaction}

  def index(conn, _params) do
    tracked_ergo_trees = Repo.all(TrackedErgoTree)

    data = Enum.map(tracked_ergo_trees, fn tracked ->
      synced_amount = get_synced_amount(tracked.ergo_tree)

      %{
        id: tracked.id,
        ergo_tree: tracked.ergo_tree,
        known_amount: tracked.known_amount,
        synced_amount: synced_amount,
        inserted_at: tracked.inserted_at,
        updated_at: tracked.updated_at
      }
    end)

    json(conn, data)
  end

  def create(conn, %{"ergo_tree" => ergo_tree, "known_amount" => known_amount}) do
    attrs = %{
      "ergo_tree" => ergo_tree,
      "known_amount" => known_amount
    }

    case TrackedErgoTree.changeset(%TrackedErgoTree{}, attrs) |> Repo.insert() do
      {:ok, tracked_ergo_tree} ->
        json(conn, tracked_ergo_tree)

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{errors: changeset.errors})
    end
  end

  def update(conn, %{"id" => id, "known_amount" => known_amount}) do
    case Repo.get(TrackedErgoTree, id) do
      nil ->
        send_resp(conn, :not_found, "Not found")

      tracked_ergo_tree ->
        attrs = %{"known_amount" => known_amount}

        case TrackedErgoTree.changeset(tracked_ergo_tree, attrs) |> Repo.update() do
          {:ok, updated_tracked_ergo_tree} ->
            json(conn, updated_tracked_ergo_tree)

          {:error, changeset} ->
            conn
            |> put_status(:bad_request)
            |> json(%{errors: changeset.errors})
        end
    end
  end

  defp get_synced_amount(ergo_tree) do
    Transaction
    |> where([t], t.ergo_tree == ^ergo_tree)
    |> select([t], count(t.id))
    |> Repo.one()
  end
end
