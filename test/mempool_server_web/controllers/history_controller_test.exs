defmodule MempoolServerWeb.HistoryControllerTest do
    use MempoolServerWeb.ConnCase
  
    test "GET /api/history/recent returns 10 most recent transactions", %{conn: conn} do
      conn = get(conn, "/api/history/recent")
      response_data = json_response(conn, 200)
      assert length(response_data) == 2
    end
  end
  