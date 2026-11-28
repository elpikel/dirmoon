defmodule DirmoonWeb.ResultsLiveCapsOfOneTest do
  use DirmoonWeb.ConnCase, async: false
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Billing

  test "choosing a topic once a research's only brief is used says it in the singular", %{conn: conn} do
    cap_of_one(:briefs_per_research)
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:page, run: run, status: :ready)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#choose-niche") |> render_click()

    assert has_element?(view, "#flash-error", "This research's 1 brief is used, so I can't write another")
  end

  test "asking for prices once a research's only price check is used says it in the singular", %{conn: conn} do
    cap_of_one(:price_checks_per_research)
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    run = scored_run(scope)
    insert(:price_check, run: run, status: :done)
    niche = insert(:niche, run: run, score: Decimal.new("6.0"))
    phrase = insert(:phrase)
    insert(:run_phrase, run: run, phrase: phrase, niche: niche)
    insert(:serp_assessment, run: run, phrase: phrase, labels: [%{"position" => 1, "page_type" => "direct_competitor"}])

    {:ok, view, _html} = live(conn, ~p"/app/runs/#{run}/results?niche=#{niche.id}")
    view |> element("#check-prices") |> render_click()

    assert has_element?(
             view,
             "#flash-error",
             "This research's 1 competitor price check is used, so I can't check another topic"
           )
  end

  defp cap_of_one(cap) do
    configured = Application.fetch_env!(:dirmoon, Billing)
    Application.put_env(:dirmoon, Billing, Keyword.put(configured, cap, 1))
    on_exit(fn -> Application.put_env(:dirmoon, Billing, configured) end)
  end

  defp scored_run(%{account: account}) do
    steps = build_run_steps(Map.new(1..7, &{&1, :done}))
    insert(:run, account: account, status: :awaiting_choice, steps: steps)
  end
end
