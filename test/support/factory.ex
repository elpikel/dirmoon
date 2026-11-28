defmodule Dirmoon.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.User
  alias Dirmoon.Billing.Allowance
  alias Dirmoon.Billing.Subscription
  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Competition.SerpSnapshot
  alias Dirmoon.Markets.Country
  alias Dirmoon.Markets.Language
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Phrases.Metrics
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.PriceChecks.CompetitorPage
  alias Dirmoon.PriceChecks.PriceCheck
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Research.Steps
  alias Dirmoon.SearchConsole.Connection
  alias Dirmoon.SiteScans.ScannedPage
  alias Dirmoon.SiteScans.SiteScan

  def unique_user_email, do: sequence(:email, &"user#{&1}@example.com")

  def unique_phrase_text(text), do: sequence(:phrase, &"#{text} #{&1}")

  def unique_stripe_customer_id, do: sequence(:stripe_customer_id, &"cus_test_#{&1}")

  def unique_stripe_reference, do: sequence(:stripe_reference, &"cs_test_#{&1}")

  def unique_stripe_subscription_id, do: sequence(:stripe_subscription_id, &"sub_test_#{&1}")

  def unique_stripe_invoice_id, do: sequence(:stripe_invoice_id, &"in_test_#{&1}")

  def unique_stripe_event_id, do: sequence(:stripe_event_id, &"evt_test_#{&1}")

  def user_factory do
    %User{
      email: unique_user_email(),
      confirmed_at: DateTime.utc_now(:second),
      memberships: [%Membership{account: build(:account)}]
    }
  end

  def account_factory do
    %Account{unpaid_access: true}
  end

  def allowance_factory do
    %Allowance{
      account: build(:account, unpaid_access: false),
      source: :single_research,
      researches: 1,
      valid_from: DateTime.shift(DateTime.utc_now(:second), day: -1),
      valid_until: nil,
      stripe_reference: unique_stripe_reference()
    }
  end

  def subscription_factory do
    now = DateTime.utc_now(:second)

    %Subscription{
      account: build(:account, unpaid_access: false),
      stripe_subscription_id: unique_stripe_subscription_id(),
      status: "active",
      current_period_start: DateTime.shift(now, day: -1),
      current_period_end: DateTime.shift(now, day: 29),
      ends_at: nil,
      stripe_updated_at: DateTime.shift(now, day: -1)
    }
  end

  def membership_factory do
    %Membership{
      account: build(:account),
      user: build(:user, memberships: [])
    }
  end

  def run_factory do
    %Run{
      account: build(:account),
      description: sequence(:run_description, &"Opis działalności testowej #{&1}"),
      mode: :new_idea,
      country_code: "PL",
      country_name: "Poland",
      language_code: "pl",
      language_name: "Polish",
      location_code: 2616,
      priority_services: [],
      status: :running
    }
  end

  def market_country_factory do
    %Country{
      country_code: sequence(:market_country_code, &"T#{&1}"),
      location_code: sequence(:market_location_code, &(3_000_000 + &1)),
      name: sequence(:market_country_name, &"Test country #{&1}"),
      fetched_at: DateTime.utc_now(:second)
    }
  end

  def market_language_factory do
    %Language{
      language_code: sequence(:market_language_code, &"x-test-#{&1}"),
      name: sequence(:market_language_name, &"Test language #{&1}"),
      fetched_at: DateTime.utc_now(:second)
    }
  end

  def api_request_factory do
    %ApiRequest{
      run: build(:run),
      service: "data_for_seo",
      operation: "search_volume",
      request_hash: sequence(:request_hash, &"request-hash-#{&1}"),
      request: %{"keywords" => ["fraza testowa"]},
      response: %{"items" => []},
      cost: Decimal.new("0.05")
    }
  end

  def phrase_factory do
    %Phrase{
      phrase: unique_phrase_text("fraza testowa"),
      language_code: "pl"
    }
  end

  def metrics_factory do
    %Metrics{
      phrase: build(:phrase),
      location_code: 2616,
      search_volume: sequence(:search_volume, &(&1 + 10)),
      cpc: Decimal.new("0.50"),
      currency: "USD",
      trend: [],
      fetched_at: DateTime.utc_now(:second),
      raw: %{}
    }
  end

  def run_phrase_factory do
    %RunPhrase{
      run: build(:run),
      phrase: build(:phrase),
      status: :kept
    }
  end

  def niche_factory do
    %Niche{
      run: build(:run),
      name: sequence(:niche_name, &"Nisza testowa #{&1}"),
      intent: "transakcyjna",
      reading: "Ludzie szukają usługi testowej. Odpowiadają im katalogi.",
      status: :proposed,
      position: sequence(:niche_position, & &1)
    }
  end

  def page_factory do
    %Page{
      run: build(:run),
      account: fn page -> page.run.account end,
      niche: fn page -> build(:niche, run: page.run) end,
      status: :ready,
      brief: build(:brief)
    }
  end

  def brief_factory do
    %Brief{
      title: "Tytuł strony testowej",
      h1: sequence(:brief_h1, &"Nagłówek testowy #{&1}"),
      slug: sequence(:brief_slug, &"strona-testowa-#{&1}"),
      intro: "Wstęp testowy. Drugie zdanie wstępu.",
      sections: [%Brief.Section{question: "Pytanie testowe?", answer: "Odpowiedź testowa."}],
      short_answer: "Krótka odpowiedź testowa.",
      phrases: [],
      primary_phrase: nil
    }
  end

  def serp_snapshot_factory do
    %SerpSnapshot{
      phrase: build(:phrase),
      location_code: 2616,
      language_code: "pl",
      fetched_at: DateTime.utc_now(:second),
      results:
        Enum.map(1..10, fn position ->
          %{
            "position" => position,
            "url" => "https://wynik-#{position}.example/strona",
            "domain" => "wynik-#{position}.example",
            "title" => "Wynik testowy #{position}"
          }
        end),
      raw: %{}
    }
  end

  def serp_assessment_factory do
    %SerpAssessment{
      run: build(:run),
      phrase: build(:phrase),
      serp_snapshot: fn assessment -> build(:serp_snapshot, phrase: assessment.phrase) end,
      labels: Enum.map(1..10, &%{"position" => &1, "page_type" => "blog"}),
      verdict: :weak,
      reused_snapshot: false
    }
  end

  def price_check_factory do
    %PriceCheck{
      run: build(:run),
      niche: fn price_check -> build(:niche, run: price_check.run) end,
      status: :checking
    }
  end

  def competitor_page_factory do
    %CompetitorPage{
      price_check: build(:price_check),
      google_position: sequence(:google_position, &(rem(&1, 10) + 1)),
      domain: sequence(:competitor_domain, &"konkurent-#{&1}.example"),
      url: fn page -> "https://#{page.domain}/cennik" end,
      outcome: :waiting,
      offers: []
    }
  end

  def site_scan_factory do
    %SiteScan{
      run: build(:run, mode: :existing_site, domain: sequence(:site_domain, &"strona-testowa-#{&1}.example")),
      status: :scanning,
      facts: %{}
    }
  end

  def scanned_page_factory do
    %ScannedPage{
      site_scan: build(:site_scan),
      url: sequence(:scanned_page_url, &"https://strona-testowa.example/podstrona-#{&1}"),
      http_status: 200,
      facts: %{},
      position: sequence(:scanned_page_position, & &1)
    }
  end

  def search_console_connection_factory do
    %Connection{
      account: build(:account),
      google_email: unique_user_email(),
      encrypted_refresh_token: sequence(:encrypted_refresh_token, &"szyfrogram-testowy-#{&1}")
    }
  end

  def build_run_steps(statuses_by_number \\ %{}, outputs_by_number \\ %{}) do
    Enum.map(Steps.numbers(), fn number ->
      %RunStep{
        number: number,
        status: Map.get(statuses_by_number, number, :waiting),
        output: Map.get(outputs_by_number, number)
      }
    end)
  end
end
