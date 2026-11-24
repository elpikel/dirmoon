defmodule Dirmoon.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Dirmoon.Repo

  alias Dirmoon.Accounts.Account
  alias Dirmoon.Accounts.Membership
  alias Dirmoon.Accounts.User
  alias Dirmoon.Competition.SerpAssessment
  alias Dirmoon.Competition.SerpSnapshot
  alias Dirmoon.Niches.Niche
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Phrases.Metrics
  alias Dirmoon.Phrases.Phrase
  alias Dirmoon.Phrases.RunPhrase
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.SearchConsole.Connection

  def unique_user_email, do: sequence(:email, &"user#{&1}@example.com")

  def unique_phrase_text(text), do: sequence(:phrase, &"#{text} #{&1}")

  def user_factory do
    %User{
      email: unique_user_email(),
      confirmed_at: DateTime.utc_now(:second),
      memberships: [%Membership{account: build(:account)}]
    }
  end

  def account_factory do
    %Account{}
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
      language_code: "pl",
      location_code: 2616,
      priority_services: [],
      status: :running
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
      cta_label: "Zapytaj o termin",
      fact_tiles: [
        %Brief.FactTile{label: "Cena", value: "[CENA]"},
        %Brief.FactTile{label: "Telefon", value: "[TELEFON]"},
        %Brief.FactTile{label: "Obszar działania", value: "[OBSZAR]"}
      ],
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

  def search_console_connection_factory do
    %Connection{
      account: build(:account),
      google_email: unique_user_email(),
      encrypted_refresh_token: sequence(:encrypted_refresh_token, &"szyfrogram-testowy-#{&1}")
    }
  end

  def build_run_steps(statuses_by_number \\ %{}, outputs_by_number \\ %{}) do
    Enum.map(1..9, fn number ->
      %RunStep{
        number: number,
        status: Map.get(statuses_by_number, number, :waiting),
        output: Map.get(outputs_by_number, number)
      }
    end)
  end
end
