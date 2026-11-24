defmodule DirmoonWeb.NewResearchLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Workers.GenerateSeeds

  test "a signed-in user sees the hero, the prompt box, the examples, the estimated cost and how it works", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#new-research h1", "czy ktoś tego szuka.")
    assert has_element?(view, "#research-form #research-description")
    assert has_element?(view, "#research-form label[for=research-description]", "Twój biznes albo pomysł")
    assert has_element?(view, "#research-mode option[value=new_idea]", "Nowy pomysł")
    assert has_element?(view, "#research-mode option[value=existing_site]", "Istniejąca strona")
    assert has_element?(view, "#research-country option[value=PL]", "Polska · polski")
    assert has_element?(view, "#research-city[placeholder='Miasto (opcjonalnie)']")
    assert has_element?(view, "#show-domain", "+ Domena")
    assert has_element?(view, "#show-services", "+ Usługi")
    assert has_element?(view, "#start-research[type=submit]", "Uruchom research")
    assert has_element?(view, "#example-prompt-1")
    assert has_element?(view, "#example-prompt-2")
    assert has_element?(view, "#example-prompt-3")
    assert has_element?(view, "#estimated-cost", "Szacowany koszt API: ok. $")
    assert has_element?(view, "#how-it-works[data-surface=dark]", "jak to działa")
  end

  test "every input on the form has a label", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#show-domain") |> render_click()
    view |> element("#show-services") |> render_click()

    for id <- ~w(research-description research-mode research-country research-city research-domain research-service-1) do
      assert has_element?(view, "label[for=#{id}]")
    end
  end

  test "the estimated cost for a run without a city is shown in dollars with a decimal comma", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#estimated-cost", "Szacowany koszt API: ok. $0,24")
  end

  test "adding a city updates the estimated cost", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"city" => "Gdańsk"}})

    assert has_element?(view, "#estimated-cost", "Szacowany koszt API: ok. $0,33")
  end

  test "clicking an example prompt fills the textarea with it", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#example-prompt-2") |> render_click()

    assert has_element?(view, "#research-description", "Serwis rowerów z dojazdem")
  end

  test "clicking an example prompt keeps the other field values", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_change(%{"run" => %{"description" => "", "mode" => "existing_site", "city" => "Gdańsk"}})

    view |> element("#example-prompt-1") |> render_click()

    assert has_element?(view, "#research-description", "Palarnia kawy z wysyłką")
    assert has_element?(view, "#research-mode option[value=existing_site][selected]")
    assert has_element?(view, "#research-city[value='Gdańsk']")
  end

  test "choosing an existing site shows the domain field as required", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    refute has_element?(view, "#research-domain")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(view, "#research-domain[required]")
  end

  test "+ Domena shows an optional domain field for a new idea", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#show-domain") |> render_click()

    assert has_element?(view, "#research-domain")
    refute has_element?(view, "#research-domain[required]")
    refute has_element?(view, "#show-domain")
  end

  test "+ Usługi shows one field per Priority Service", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#show-services") |> render_click()

    for number <- 1..Run.max_priority_services() do
      assert has_element?(view, "#research-service-#{number}[name='run[priority_services][]']")
    end

    refute has_element?(view, "#research-service-#{Run.max_priority_services() + 1}")
  end

  test "an existing site without Search Console offers to connect it", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(
             view,
             "#search-console-note a#connect-search-console[href='/app/search-console/connect?return_to=%2Fapp%2Fresearch%2Fnew']",
             "Połącz Search Console"
           )
  end

  test "an existing site with Search Console connected says so with the Google email", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    connection = insert(:search_console_connection, account: scope.account)
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(view, "#search-console-connected", "Search Console połączone (#{connection.google_email})")
    refute has_element?(view, "#connect-search-console")
  end

  test "a valid submit starts a run in the user's Account and goes to its run screen", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    result =
      view
      |> element("#research-form")
      |> render_submit(%{
        "run" => %{
          "description" => "Wypożyczalnia kajaków nad jeziorem, spływy z przewodnikiem",
          "mode" => "new_idea",
          "country_code" => "PL",
          "city" => "Olsztyn",
          "priority_services" => ["spływy kajakowe", ""]
        }
      })

    assert {:error, {:live_redirect, %{to: "/app/runs/" <> run_id = run_path}}} = result

    run = Repo.get!(Run, run_id)
    assert run_path == ~p"/app/runs/#{run}"
    assert run.account_id == scope.account.id
    assert run.description == "Wypożyczalnia kajaków nad jeziorem, spływy z przewodnikiem"
    assert run.city == "Olsztyn"
    assert run.priority_services == ["spływy kajakowe"]
    assert_enqueued(worker: GenerateSeeds, args: %{run_id: run.id})
  end

  test "a blank description shows its error and starts no run", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{"run" => %{"description" => "  ", "mode" => "new_idea", "country_code" => "PL"}})

    assert has_element?(view, "#research-description-field", "nie może być puste")
    assert Research.list_runs(scope) == []
    refute_enqueued(worker: GenerateSeeds)
  end

  test "an existing site without a domain shows the domain error and starts no run", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{
      "run" => %{
        "description" => "Kancelaria notarialna w centrum miasta",
        "mode" => "existing_site",
        "country_code" => "PL",
        "domain" => ""
      }
    })

    assert has_element?(view, "#research-domain-field", "nie może być puste")
    assert Research.list_runs(scope) == []
  end

  test "six Priority Services show the services error and start no run", %{conn: conn} do
    %{conn: conn, scope: scope} = register_and_log_in_user(%{conn: conn})
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{
      "run" => %{
        "description" => "Studio fryzjerskie dla dzieci i dorosłych",
        "mode" => "new_idea",
        "country_code" => "PL",
        "priority_services" => ["strzyżenie", "koloryzacja", "upięcia", "keratyna", "baleyage", "trwała"]
      }
    })

    assert has_element?(view, "#research-services-field", "powinno mieć najwyżej 5")
    assert Research.list_runs(scope) == []
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/app/research/new")

    assert path == ~p"/users/log-in"
  end

  test "/app sends a signed-in user to the new research screen", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    conn = get(conn, ~p"/app")

    assert redirected_to(conn) == ~p"/app/research/new"
  end
end
