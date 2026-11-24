defmodule Dirmoon.Workers.WriteBriefTest do
  use Dirmoon.DataCase, async: true
  use Oban.Testing, repo: Dirmoon.Repo

  import Mox

  alias Dirmoon.Accounts.Scope
  alias Dirmoon.Niches
  alias Dirmoon.Pages.Brief
  alias Dirmoon.Pages.Page
  alias Dirmoon.Research
  alias Dirmoon.Research.ApiRequest
  alias Dirmoon.Research.Run
  alias Dirmoon.Research.RunStep
  alias Dirmoon.Workers.WriteBrief

  test "the chosen niche gets a stored brief with every part of the page and the run awaits a choice again" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    primary = phrase_in_niche(run, niche, "hotel dla psa")
    other = phrase_in_niche(run, niche, "hotel dla psa cena")
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :brief} ->
      {:ok, brief_answer(%{"phrases" => [primary, other], "primary_phrase" => primary}), Decimal.new("0.01")}
    end)

    assert :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert %Page{status: :ready, error: nil, brief: brief} = Repo.get!(Page, page.id)

    assert %Brief{
             title: "Hotel dla psa – spokojny pobyt",
             h1: "Hotel dla psa",
             slug: "hotel-dla-psa",
             breadcrumb: "Strona główna / Hotel dla psa",
             intro: "Pies zostaje pod opieką. Ty jedziesz spokojnie.",
             cta_label: "Zapytaj o termin",
             short_answer: "Tak, przyjmujemy psy na noc.",
             primary_phrase: ^primary
           } = brief

    assert brief.phrases == [primary, other]

    assert Enum.map(brief.fact_tiles, &{&1.label, &1.value}) == [
             {"Cena za dobę", "[CENA]"},
             {"Telefon", "[TELEFON]"},
             {"Obszar", "[OBSZAR]"}
           ]

    assert [%Brief.Section{question: "Czy pies może zostać na noc?"}, _second, _third, _fourth] = brief.sections

    assert %RunStep{status: :done, result: "Brief gotowy: Hotel dla psa"} = step(run, 8)
    assert %Run{status: :awaiting_choice} = Repo.get!(Run, run.id)
  end

  test "the brief, the ledger answer and the step output are stored as plain JSON for phrases with decimal metrics" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    primary = phrase_in_niche(run, niche, "hotel dla psa")
    phrase = Repo.get_by!(Dirmoon.Phrases.Phrase, phrase: primary)
    insert(:metrics, phrase: phrase, location_code: run.location_code, cpc: Decimal.new("0.66"))
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :brief} ->
      {:ok, brief_answer(%{"phrases" => [primary], "primary_phrase" => primary}), Decimal.new("0.01")}
    end)

    assert :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert [%{"h1" => "Hotel dla psa", "primary_phrase" => ^primary, "fact_tiles" => fact_tiles} = stored_brief] =
             stored_json(%{table: "pages", column: "brief", where: "id = $1", value: page.id})

    assert [%{"label" => "Cena za dobę", "value" => "[CENA]"}, _phone, _area] = fact_tiles
    assert stored_brief |> json_leaves() |> Enum.all?(&(is_binary(&1) or is_nil(&1)))

    assert [%{"h1" => "Hotel dla psa", "phrases" => [^primary]}] =
             stored_json(%{table: "api_requests", column: "response", where: "run_id = $1", value: run.id})

    page_id = page.id

    assert [%{"page_id" => ^page_id}] =
             stored_json(%{table: "run_steps", column: "output", where: "run_id = $1 AND number = 8", value: run.id})
  end

  test "the model is asked about the niche's phrases, the customer questions and the business" do
    run = run_awaiting_choice(%{description: "Hotel dla psów pod miastem", city: "Kraków"})
    niche = insert(:niche, run: run, name: "Hotel dla psa")
    phrase = phrase_in_niche(run, niche, "hotel dla psa")
    phrase_in_niche(run, insert(:niche, run: run), "strzyżenie psa")
    {:ok, _page} = Niches.choose(scope_for(run.account), niche.id)
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:request, request})
      {:ok, brief_answer(%{"phrases" => [phrase], "primary_phrase" => phrase}), Decimal.new("0.01")}
    end)

    :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert_receive {:request, %{task: :brief, input: input, prompt: prompt}}

    assert input == %{
             niche_name: "Hotel dla psa",
             phrases: [phrase],
             questions: questions(),
             business_description: "Hotel dla psów pod miastem",
             city: "Kraków"
           }

    assert prompt =~ "[CENA]"
    refute prompt =~ "strzyżenie psa"
  end

  test "for an existing site the prompt names the domain and the owner's review of sensitive answers" do
    run = run_awaiting_choice(%{mode: :existing_site, domain: "kancelaria-testowa.example"})
    niche = insert(:niche, run: run)
    phrase = phrase_in_niche(run, niche, "porada prawna")
    {:ok, _page} = Niches.choose(scope_for(run.account), niche.id)
    test_process = self()

    expect(Dirmoon.LLMMock, :structured, 1, fn request ->
      send(test_process, {:prompt, request.prompt})
      {:ok, brief_answer(%{"phrases" => [phrase], "primary_phrase" => phrase}), Decimal.new("0.01")}
    end)

    :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert_receive {:prompt, prompt}
    assert prompt =~ "kancelaria-testowa.example"
    assert prompt =~ "właściciel firmy"
  end

  test "only phrases of the chosen niche are kept and the primary one is among them" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    kept = phrase_in_niche(run, niche, "hotel dla psa")
    other_niche_phrase = phrase_in_niche(run, insert(:niche, run: run), "strzyżenie psa")
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      {:ok,
       brief_answer(%{
         "phrases" => ["  " <> String.upcase(kept) <> " ", other_niche_phrase, "wymyślona fraza modelu"],
         "primary_phrase" => "wymyślona fraza modelu"
       }), Decimal.new("0.01")}
    end)

    :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert %Brief{phrases: [^kept], primary_phrase: ^kept} = Repo.get!(Page, page.id).brief
  end

  test "invented contact data in the model's answer is replaced by placeholders before the brief is stored" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase = phrase_in_niche(run, niche, "hotel dla psa")
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      {:ok,
       brief_answer(%{
         "phrases" => [phrase],
         "primary_phrase" => phrase,
         "fact_tiles" => [
           %{"label" => "Cena za dobę", "value" => "80 zł"},
           %{"label" => "Telefon", "value" => "[TELEFON]"},
           %{"label" => "Obszar", "value" => "[OBSZAR]"}
         ],
         "sections" => [
           %{"question" => "Jak zarezerwować?", "answer" => "Zadzwoń pod numer 600 100 200 i zapytaj o termin."}
         ],
         "phone" => "600 100 200",
         "email" => "kontakt@example.com",
         "address" => "ul. Testowa 1"
       }), Decimal.new("0.01")}
    end)

    :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert %Brief{fact_tiles: [price | _other_facts], sections: [section], phone: nil, email: nil, address: nil} =
             Repo.get!(Page, page.id).brief

    assert price.value == "[CENA]"
    assert section.answer == "Zadzwoń pod numer [TELEFON] i zapytaj o termin."
  end

  test "an invalid brief is not recorded and the retry asks the model again" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase = phrase_in_niche(run, niche, "hotel dla psa")
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 2, fn _request ->
      {:ok, brief_answer(%{"phrases" => [phrase], "fact_tiles" => [%{"label" => "Cena", "value" => "[CENA]"}]}),
       Decimal.new("0.01")}
    end)

    assert {:error, "Model zwrócił niepoprawny brief"} = perform_job(WriteBrief, %{run_id: run.id}, attempt: 1)

    assert ApiRequest
           |> from(as: :api_request)
           |> where([api_request: api_request], api_request.run_id == ^run.id)
           |> Repo.all() == []

    assert {:error, "Model zwrócił niepoprawny brief"} = perform_job(WriteBrief, %{run_id: run.id}, attempt: 2)
    assert %Page{status: :writing, brief: nil} = Repo.get!(Page, page.id)
  end

  test "a model answer that is not an object is an invalid brief and is not recorded" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, "hotel dla psa")
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, ["nie obiekt"], Decimal.new("0.01")} end)

    assert {:error, "Model zwrócił niepoprawny brief"} = perform_job(WriteBrief, %{run_id: run.id}, attempt: 1)

    assert Repo.all_by(ApiRequest, run_id: run.id) == []
    assert %Page{status: :writing, brief: nil} = Repo.get!(Page, page.id)
  end

  test "a recorded brief that no longer passes validation fails the attempt without asking the model again" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase = phrase_in_niche(run, niche, "hotel dla psa")
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request ->
      {:ok, brief_answer(%{"phrases" => [phrase], "primary_phrase" => phrase}), Decimal.new("0.01")}
    end)

    :ok = perform_job(WriteBrief, %{run_id: run.id})
    record_invalid_brief_and_write_again(run, page)

    assert {:error, "Model zwrócił niepoprawny brief"} = perform_job(WriteBrief, %{run_id: run.id}, attempt: 1)

    assert %Page{status: :writing, brief: nil} = Repo.get!(Page, page.id)
  end

  test "when step 8 finally fails the page fails with the reason and picking the niche again writes it anew" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase_in_niche(run, niche, "hotel dla psa")
    scope = scope_for(run.account)
    {:ok, page} = Niches.choose(scope, niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:ok, %{"h1" => "Bez sekcji"}, Decimal.new("0.01")} end)

    assert {:cancel, "Model zwrócił niepoprawny brief"} = perform_job(WriteBrief, %{run_id: run.id}, attempt: 3)

    assert %Page{status: :failed, error: "Model zwrócił niepoprawny brief"} = Repo.get!(Page, page.id)
    assert %RunStep{status: :failed} = step(run, 8)
    assert %Run{status: :failed} = Repo.get!(Run, run.id)

    assert {:ok, %Page{id: page_id, status: :writing, error: nil}} = Niches.choose(scope, niche.id)
    assert page_id == page.id
    assert %Run{status: :running} = Repo.get!(Run, run.id)
    assert %RunStep{status: :queued} = step(run, 8)
  end

  test "without an LLM provider step 8 fails with a readable reason and the page fails" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    {:ok, page} = Niches.choose(scope_for(run.account), niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :llm_not_configured} end)

    assert {:cancel, :llm_not_configured} = perform_job(WriteBrief, %{run_id: run.id})

    assert %RunStep{status: :failed, error: "Nie wybrano dostawcy LLM"} = step(run, 8)
    assert %Page{status: :failed, error: "Nie wybrano dostawcy LLM"} = Repo.get!(Page, page.id)
  end

  test "a brief stopped before its job started is written once the run is resumed" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    phrase = phrase_in_niche(run, niche, "hotel dla psa")
    scope = scope_for(run.account)
    {:ok, page} = Niches.choose(scope, niche.id)

    {:ok, _run} = Research.stop_run(scope, run.id)
    refute_enqueued(worker: WriteBrief)

    {:ok, _run} = Research.resume_run(scope, run.id)
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})

    expect(Dirmoon.LLMMock, :structured, 1, fn %{task: :brief} ->
      {:ok, brief_answer(%{"phrases" => [phrase], "primary_phrase" => phrase}), Decimal.new("0.01")}
    end)

    assert %{success: 1} = Oban.drain_queue(queue: :pipeline)

    assert %Page{status: :ready} = Repo.get!(Page, page.id)
    assert %Run{status: :awaiting_choice} = Repo.get!(Run, run.id)
  end

  test "resuming a run whose step 8 finally failed retries nothing and picking the niche again restarts it" do
    run = run_awaiting_choice()
    niche = insert(:niche, run: run)
    scope = scope_for(run.account)
    {:ok, page} = Niches.choose(scope, niche.id)

    expect(Dirmoon.LLMMock, :structured, 1, fn _request -> {:error, :llm_not_configured} end)

    assert %{cancelled: 1} = Oban.drain_queue(queue: :pipeline)
    assert %Page{status: :failed} = Repo.get!(Page, page.id)

    assert {:ok, %Run{status: :awaiting_choice}} = Research.resume_run(scope, run.id)

    assert all_enqueued() == []
    assert %Page{status: :failed} = Repo.get!(Page, page.id)
    assert {:ok, %Page{status: :writing}} = Niches.choose(scope, niche.id)
    assert_enqueued(worker: WriteBrief, args: %{run_id: run.id})
  end

  test "step 8 is skipped when no page of the run is being written" do
    run = insert(:run, status: :running, steps: build_run_steps(Map.new(1..7, &{&1, :done})))
    insert(:page, run: run, status: :ready)

    assert :ok = perform_job(WriteBrief, %{run_id: run.id})

    assert %RunStep{status: :skipped, result: "Brak strony do napisania"} = step(run, 8)
  end

  defp scope_for(account), do: Scope.for_user(build(:user), account)

  defp record_invalid_brief_and_write_again(run, page) do
    ApiRequest
    |> from(as: :api_request)
    |> where([api_request: api_request], api_request.run_id == ^run.id)
    |> Repo.update_all(set: [response: %{"h1" => "Brief bez sekcji"}])

    Page |> Repo.get!(page.id) |> Ecto.Changeset.change(status: :writing, brief: nil) |> Repo.update!()
    Run |> Repo.get!(run.id) |> Ecto.Changeset.change(status: :running) |> Repo.update!()
    run |> step(8) |> Ecto.Changeset.change(status: :queued) |> Repo.update!()
  end

  defp run_awaiting_choice(attrs \\ %{}) do
    insert(
      :run,
      Map.merge(
        %{
          status: :awaiting_choice,
          steps: build_run_steps(Map.new(1..7, &{&1, :done}), %{1 => %{"seeds" => [], "questions" => questions()}})
        },
        attrs
      )
    )
  end

  defp questions, do: ["Czy pies może zostać na noc?", "Ile kosztuje doba?"]

  defp phrase_in_niche(run, niche, text) do
    phrase = insert(:phrase, phrase: unique_phrase_text(text))
    insert(:run_phrase, run: run, phrase: phrase, niche: niche)
    phrase.phrase
  end

  defp brief_answer(overrides) do
    Map.merge(
      %{
        "title" => "Hotel dla psa – spokojny pobyt",
        "h1" => "Hotel dla psa",
        "slug" => "hotel-dla-psa",
        "breadcrumb" => "Strona główna / Hotel dla psa",
        "intro" => "Pies zostaje pod opieką. Ty jedziesz spokojnie.",
        "cta_label" => "Zapytaj o termin",
        "fact_tiles" => [
          %{"label" => "Cena za dobę", "value" => "[CENA]"},
          %{"label" => "Telefon", "value" => "[TELEFON]"},
          %{"label" => "Obszar", "value" => "[OBSZAR]"}
        ],
        "sections" => [
          %{"question" => "Czy pies może zostać na noc?", "answer" => "Tak. Pies śpi w ciepłym boksie."},
          %{"question" => "Ile kosztuje doba?", "answer" => "Cenę poda właściciel: [CENA]."},
          %{"question" => "Czy pies wychodzi na spacer?", "answer" => "Tak, trzy razy dziennie."},
          %{"question" => "Co zabrać dla psa?", "answer" => "Karmę i ulubioną zabawkę."}
        ],
        "short_answer" => "Tak, przyjmujemy psy na noc.",
        "phrases" => [],
        "primary_phrase" => nil
      },
      overrides
    )
  end

  defp json_leaves(map) when is_map(map), do: map |> Map.values() |> Enum.flat_map(&json_leaves/1)
  defp json_leaves(list) when is_list(list), do: Enum.flat_map(list, &json_leaves/1)
  defp json_leaves(leaf), do: [leaf]

  defp step(run, number), do: Repo.get_by!(RunStep, run_id: run.id, number: number)
end
