defmodule DirmoonWeb.NewResearchLiveTest do
  use DirmoonWeb.ConnCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Phoenix.LiveViewTest

  alias Dirmoon.Repo
  alias Dirmoon.Research
  alias Dirmoon.Research.Run
  alias Dirmoon.Workers.GenerateSeeds

  test "a signed-in user sees the form with its chips, examples and estimated cost, and the Account's recent runs",
       %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    market = store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#app-main #new-research h1#new-research-heading", "Describe the business.")
    assert has_element?(view, "#research-form #research-description")
    assert has_element?(view, "#research-form label[for=research-description]", "Your business or idea")
    assert has_element?(view, "#research-mode option[value=new_idea]", "New idea")
    assert has_element?(view, "#research-mode option[value=existing_site]", "Existing site")
    assert has_element?(view, "#research-country option[value='#{market.country.country_code}']", market.country.name)
    assert has_element?(view, "#research-language option[value='#{market.language.language_code}']", market.language.name)
    assert has_element?(view, "#research-city[placeholder='City (optional)']")
    assert has_element?(view, "#show-domain", "+ Domain")
    assert has_element?(view, "#show-services", "+ Services")
    assert has_element?(view, "#start-research[type=submit][data-variant=lime]", "Start research")
    assert has_element?(view, "#example-prompt-1")
    assert has_element?(view, "#example-prompt-2")
    assert has_element?(view, "#example-prompt-3")
    assert has_element?(view, "#estimated-cost", "Estimated API cost: about $")
    assert has_element?(view, "#recent-runs-column #recent-runs")
    assert has_element?(view, "#app-context", "/ new research")
  end

  test "the country and language choices list the stored countries and languages by name", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    zambia = insert(:market_country, name: "Zambia")
    albania = insert(:market_country, name: "Albania")
    swahili = insert(:market_language, name: "Swahili")
    arabic = insert(:market_language, name: "Arabic")

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    document = view |> render() |> LazyHTML.from_fragment()

    assert document |> LazyHTML.query("#research-country option") |> LazyHTML.attribute("value") ==
             [albania.country_code, zambia.country_code]

    assert document |> LazyHTML.query("#research-language option") |> LazyHTML.attribute("value") ==
             [arabic.language_code, swahili.language_code]

    assert has_element?(view, "label[for=research-country]", "Country")
    assert has_element?(view, "label[for=research-language]", "Language")
  end

  test "a first run starts in the United States, in English", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    insert(:market_country, country_code: "US", location_code: 2840, name: "United States")
    insert(:market_country, name: "Albania")
    insert(:market_language, language_code: "en", name: "English")
    insert(:market_language, name: "Arabic")

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#research-country option[value=US][selected]", "United States")
    assert has_element?(view, "#research-language option[value=en][selected]", "English")
  end

  test "the market of the Account's latest run is chosen to start with", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    older = %{country: insert(:market_country), language: insert(:market_language)}
    latest = %{country: insert(:market_country), language: insert(:market_language)}

    insert(:run,
      account: scope.account,
      country_code: older.country.country_code,
      language_code: older.language.language_code,
      inserted_at: ~U[2026-11-01 10:00:00Z]
    )

    insert(:run,
      account: scope.account,
      country_code: latest.country.country_code,
      language_code: latest.language.language_code,
      inserted_at: ~U[2026-11-02 10:00:00Z]
    )

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#research-country option[value='#{latest.country.country_code}'][selected]")
    assert has_element?(view, "#research-language option[value='#{latest.language.language_code}'][selected]")
  end

  test "with no stored countries and DataForSEO not configured, I say so and can't start a run", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    Mox.stub(Dirmoon.DataForSEOMock, :countries, fn -> {:error, :data_for_seo_not_configured} end)

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#markets-unavailable", "the Google search data provider (DataForSEO) isn't configured")
    refute has_element?(view, "#research-country")
    refute has_element?(view, "#research-language")
    assert has_element?(view, "#start-research[disabled]")
  end

  test "with no stored languages and DataForSEO unreachable, I say I couldn't load them", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    insert(:market_country)
    Mox.stub(Dirmoon.DataForSEOMock, :languages, fn -> {:error, "DataForSEO: HTTP 502"} end)

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#markets-unavailable", "I couldn't load the countries and languages")
    refute has_element?(view, "#research-language")
    assert has_element?(view, "#start-research[disabled]")
  end

  test "a country or language that isn't in the stored lists shows its error and starts no run", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{
      "run" => %{
        "description" => "Szkoła pływania dla dorosłych",
        "mode" => "new_idea",
        "country_code" => "T-unknown",
        "language_code" => "x-unknown"
      }
    })

    assert has_element?(view, "#research-form", "is not available")
    assert Research.list_runs(scope) == []
    refute_enqueued(worker: GenerateSeeds)
  end

  test "the prompt box is a gray card with no lime edge, and the lime start button is its one accent", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#research-form #research-prompt-box.bg-app-raised.border-app-line-strong")
    refute has_element?(view, "#research-prompt-box.shadow-prompt")
    refute has_element?(view, "#research-prompt-box.bg-white")
    assert has_element?(view, "#research-description.text-on-app.bg-transparent")
    assert has_element?(view, "#research-mode.bg-app-selected")
    assert has_element?(view, "#show-domain.border-dashed.border-app-line-strong")
    assert has_element?(view, "#start-research.bg-accent")
  end

  test "the optional domain field sits on the app's grays", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new")
    view |> element("#show-domain") |> render_click()

    assert has_element?(view, "#research-domain.bg-app-field.text-on-app")
  end

  test "the screen has no marketing: no hero, no pitch and no how it works", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, html} = live(conn, ~p"/app/research/new")

    refute has_element?(view, "#how-it-works")
    refute has_element?(view, "#landing-hero")
    refute has_element?(view, "[data-layout=landing]")
    refute has_element?(view, "h1", "Validate your business idea")
    refute html =~ "Before you build it"
  end

  test "the nav marks Nowy research as the current page", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#app-nav #nav-new-research[aria-current=page]", "New research")
    refute has_element?(view, "#app-nav #nav-runs[aria-current]")
    refute has_element?(view, "#app-nav #nav-pages[aria-current]")
  end

  test "the recent runs are the Account's five newest, newest first, with status and date", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    runs =
      for day <- 1..6 do
        insert(:run,
          account: scope.account,
          description: "Research numer #{day}. Opis testowy.",
          status: :stopped,
          inserted_at: DateTime.new!(Date.new!(2026, 11, day), ~T[10:00:00], "Etc/UTC")
        )
      end

    foreign_run = insert(:run, inserted_at: ~U[2026-11-30 10:00:00Z])
    [oldest | listed_oldest_first] = runs

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    listed_ids =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#recent-runs > li[data-status]")
      |> LazyHTML.attribute("id")

    assert listed_ids == listed_oldest_first |> Enum.reverse() |> Enum.map(&"recent-run-#{&1.id}")
    refute has_element?(view, "#recent-run-#{oldest.id}")
    refute has_element?(view, "#recent-run-#{foreign_run.id}")

    newest = List.last(runs)
    assert has_element?(view, "#recent-run-#{newest.id}", "Research numer 6")
    assert has_element?(view, "#recent-run-#{newest.id}-status", "Stopped")
    assert has_element?(view, "#recent-run-#{newest.id}", "6 Nov 2026")
    assert has_element?(view, "#all-runs-link[href='/app/runs']", "All results")
  end

  test "a recent run links to its screen, or to its results once they are ready", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    scored_steps = Map.new(1..7, &{&1, :done})
    running = insert(:run, account: scope.account, status: :running, steps: build_run_steps(%{1 => :running}))
    scored = insert(:run, account: scope.account, status: :awaiting_choice, steps: build_run_steps(scored_steps))
    failed = insert(:run, account: scope.account, status: :failed, steps: build_run_steps(%{1 => :failed}))
    stopped = insert(:run, account: scope.account, status: :stopped, steps: build_run_steps(scored_steps))

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#recent-run-#{running.id} a[href='/app/runs/#{running.id}']")
    assert has_element?(view, "#recent-run-#{running.id}-status", "In progress")
    assert has_element?(view, "#recent-run-#{scored.id} a[href='/app/runs/#{scored.id}/results']")
    assert has_element?(view, "#recent-run-#{scored.id}-status", "Awaiting choice")
    assert has_element?(view, "#recent-run-#{failed.id} a[href='/app/runs/#{failed.id}']")
    assert has_element?(view, "#recent-run-#{failed.id}-status", "Failed")
    assert has_element?(view, "#recent-run-#{stopped.id} a[href='/app/runs/#{stopped.id}/results']")
    assert has_element?(view, "#recent-run-#{stopped.id}-status", "Stopped")
  end

  test "with no runs yet the recent runs invite a first description", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    insert(:run)

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(
             view,
             "#recent-runs #recent-runs-empty",
             "No research yet. Start with the description on the left."
           )

    refute has_element?(view, "#recent-runs > li[data-status]")
  end

  test "the status row speaks of a new idea by default", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(
             view,
             "#app-status #new-research-status-line",
             "Describe the business and I'll find what people really type into Google and how many times a month they type it."
           )
  end

  test "the status row for an existing site without Search Console says current positions are skipped",
       %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(
             view,
             "#new-research-status-line",
             "Describe the business and give its domain. Without Search Console I'll skip where the site already shows up on Google."
           )
  end

  test "the status row for an existing site with Search Console promises current positions", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    insert(:search_console_connection, account: scope.account)

    {:ok, view, _html} = live(conn, ~p"/app/research/new?mode=existing_site")

    assert has_element?(
             view,
             "#new-research-status-line",
             "Describe the business and give its domain. I'll also check which searches the site already shows up for."
           )
  end

  test "every input on the form has a label", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#show-domain") |> render_click()
    view |> element("#show-services") |> render_click()

    for id <-
          ~w(research-description research-mode research-country research-language research-city research-domain research-service-1) do
      assert has_element?(view, "label[for=#{id}]")
    end
  end

  test "the estimated cost for a run without a city is shown in dollars with a decimal comma", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    assert has_element?(view, "#estimated-cost", "Estimated API cost: about $0.24")
  end

  test "adding a city updates the estimated cost", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"city" => "Gdańsk"}})

    assert has_element?(view, "#estimated-cost", "Estimated API cost: about $0.33")
  end

  test "clicking an example prompt fills the textarea with it", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#example-prompt-2") |> render_click()

    assert has_element?(view, "#research-description", "Bike repair that comes to the customer")
  end

  test "clicking an example prompt keeps the other field values", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_change(%{"run" => %{"description" => "", "mode" => "existing_site", "city" => "Gdańsk"}})

    view |> element("#example-prompt-1") |> render_click()

    assert has_element?(view, "#research-description", "A coffee roastery that ships")
    assert has_element?(view, "#research-mode option[value=existing_site][selected]")
    assert has_element?(view, "#research-city[value='Gdańsk']")
  end

  test "a crafted example number that names no example leaves the description as it is", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")
    view |> element("#research-form") |> render_change(%{"run" => %{"description" => "Mój własny opis"}})

    for number <- ["0", "99", "dwa", "1.5"] do
      render_hook(view, "use_example", %{"number" => number})
    end

    assert has_element?(view, "#research-description", "Mój własny opis")
  end

  test "crafted Priority Services that are not a list show no service fields", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"priority_services" => "jedna usługa"}})

    refute has_element?(view, "#research-service-1")
    assert has_element?(view, "#show-services")
  end

  test "choosing an existing site shows the domain field as required", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    refute has_element?(view, "#research-domain")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(view, "#research-domain[required]")
  end

  test "+ Domain shows an optional domain field for a new idea", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#show-domain") |> render_click()

    assert has_element?(view, "#research-domain")
    refute has_element?(view, "#research-domain[required]")
    refute has_element?(view, "#show-domain")
  end

  test "+ Usługi shows one field per Priority Service", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#show-services") |> render_click()

    for number <- 1..Run.max_priority_services() do
      assert has_element?(view, "#research-service-#{number}[name='run[priority_services][]']")
    end

    refute has_element?(view, "#research-service-#{Run.max_priority_services() + 1}")
  end

  test "an existing site without Search Console offers to connect it and come back in the same mode", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(
             view,
             "#search-console-note a#connect-search-console[href='/app/search-console/connect?return_to=%2Fapp%2Fresearch%2Fnew%3Fmode%3Dexisting_site']",
             "Connect Search Console"
           )
  end

  test "coming back from connecting Search Console shows the existing site mode with the domain and the connection",
       %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    connection = insert(:search_console_connection, account: scope.account)

    {:ok, view, _html} = live(conn, ~p"/app/research/new?mode=existing_site")

    assert has_element?(view, "#research-mode option[value=existing_site][selected]")
    assert has_element?(view, "#research-domain")
    assert has_element?(view, "#search-console-connected", "Search Console connected (#{connection.google_email})")
  end

  test "an unknown mode in the address falls back to a new idea", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    {:ok, view, _html} = live(conn, ~p"/app/research/new?mode=agency")

    assert has_element?(view, "#research-mode option[value=new_idea][selected]")
    refute has_element?(view, "#search-console-note")
  end

  test "an existing site with Search Console connected says so with the Google email", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()
    connection = insert(:search_console_connection, account: scope.account)
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view |> element("#research-form") |> render_change(%{"run" => %{"mode" => "existing_site"}})

    assert has_element?(view, "#search-console-connected", "Search Console connected (#{connection.google_email})")
    refute has_element?(view, "#connect-search-console")
  end

  test "a valid submit starts a run in the user's Account and goes to its run screen", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    market = store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    result =
      view
      |> element("#research-form")
      |> render_submit(%{
        "run" => %{
          "description" => "Wypożyczalnia kajaków nad jeziorem, spływy z przewodnikiem",
          "mode" => "new_idea",
          "country_code" => market.country.country_code,
          "language_code" => market.language.language_code,
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
    assert run.country_code == market.country.country_code
    assert run.country_name == market.country.name
    assert run.language_code == market.language.language_code
    assert run.language_name == market.language.name
    assert_enqueued(worker: GenerateSeeds, args: %{run_id: run.id})
  end

  test "a blank description shows its error and starts no run", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    market = store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{
      "run" => %{"description" => "  ", "mode" => "new_idea", "country_code" => market.country.country_code}
    })

    assert has_element?(view, "#research-description-field", "can't be blank")
    assert Research.list_runs(scope) == []
    refute_enqueued(worker: GenerateSeeds)
  end

  test "an existing site without a domain shows the domain error and starts no run", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    market = store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{
      "run" => %{
        "description" => "Kancelaria notarialna w centrum miasta",
        "mode" => "existing_site",
        "country_code" => market.country.country_code,
        "language_code" => market.language.language_code,
        "domain" => ""
      }
    })

    assert has_element?(view, "#research-domain-field", "can't be blank")
    assert Research.list_runs(scope) == []
  end

  test "six Priority Services show the services error and start no run", %{conn: conn} do
    %{conn: conn, scope: scope} = sign_up_and_log_in_user(%{conn: conn})
    market = store_market_lists()
    {:ok, view, _html} = live(conn, ~p"/app/research/new")

    view
    |> element("#research-form")
    |> render_submit(%{
      "run" => %{
        "description" => "Studio fryzjerskie dla dzieci i dorosłych",
        "mode" => "new_idea",
        "country_code" => market.country.country_code,
        "language_code" => market.language.language_code,
        "priority_services" => ["strzyżenie", "koloryzacja", "upięcia", "keratyna", "baleyage", "trwała"]
      }
    })

    assert has_element?(view, "#research-services-field", "should have at most 5")
    assert Research.list_runs(scope) == []
  end

  test "a signed-out visitor is sent to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/app/research/new")

    assert path == ~p"/users/log-in"
  end

  test "/app sends a signed-in user to the new research screen", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})
    store_market_lists()

    conn = get(conn, ~p"/app")

    assert redirected_to(conn) == ~p"/app/research/new"
  end

  defp store_market_lists do
    %{country: insert(:market_country), language: insert(:market_language)}
  end
end
