defmodule Dirmoon.GlossaryTest do
  use ExUnit.Case, async: true

  # Every word CONTEXT.md lists under _Avoid_ must stay out of the names the
  # code gives its concepts under lib/ (`.ex` and `.heex`): module names,
  # function names, schema fields, embeds, associations, component attrs and
  # slots, atom literals used as values (statuses, reasons, task names),
  # template ids and assigns (and module attributes). A name is split into its
  # snake_case, kebab-case and CamelCase fragments, and a fragment matches an
  # avoided word in any simple inflection ("registration" also catches
  # "register_user").
  #
  # It also checks CONTEXT.md itself: no term's definition uses one of that
  # term's own avoided words.
  #
  # It does NOT check free text: UI copy, flash messages, error and result
  # lines, prompts, docs and comments, and string values in general (only
  # template ids are read from strings). Polish copy is outside its reach
  # entirely, and a definition using another term's avoided word is left to
  # review.

  @glossary_path "CONTEXT.md"
  @source_glob "lib/**/*.{ex,heex}"

  # Names that keep an avoided word because CONTEXT.md allows it in table,
  # column and external-API names.
  @allowed_names %{
    # Columns of the handover's tables (`keywords`, `clusters`), and a list of
    # such column values.
    "keyword_id" => "column run_keywords.keyword_id (and the other tables' keyword_id)",
    "keyword_ids" => "a list of keyword_id column values",
    "cluster_id" => "column run_keywords.cluster_id / pages.cluster_id",
    # DataForSEO's own names for a Phrase's monthly searches and their endpoint.
    "search_volume" => "DataForSEO's field, stored as keyword_metrics.search_volume",
    "search_volumes" => "DataForSEO's search_volume endpoint, called by Step 3",
    "search_volumes_request" => "the request type of DataForSEO's search_volume endpoint",
    # DataForSEO's request body keys for phrase ideas, search volumes and the
    # SERP top 10.
    "keywords" => "DataForSEO's request key for the phrases sent",
    "keyword" => "DataForSEO's request key for the SERP's phrase",
    # The provider column of a Phrase's Trend (`keyword_metrics.monthly_searches`).
    "monthly_searches" => "column keyword_metrics.monthly_searches",
    # DataForSEO's status 40102 "No Search Results" and its "organic" result
    # type ("organic" shares its first six letters with "organization").
    "no_search_results_status" => "DataForSEO's 40102 \"No Search Results\" status",
    "organic_type" => "DataForSEO's \"organic\" result type",
    # The Phoenix generator's config key for the DNSCluster library.
    "dns_cluster_query" => "config :dirmoon, :dns_cluster_query, read for DNSCluster",
    # The verb of Step 4, "Filter and Group".
    "group" => "Dirmoon.Niches.Grouping.group/1 runs Step 4, Filter and Group"
  }

  # Glossary terms and external product names whose words look avoided:
  # "Filter and Group" is Step 4, "Step Group" is a glossary term and "Search
  # Console" is Google's product, not a Research Run. Only these exact
  # phrases are removed from a name before it is checked; the rest of the name
  # is still checked.
  @known_phrases ~r/FilterAndGroup|filter[_-]and[_-]group|StepGroups?|step[_-]groups?|SearchConsole|search[_-]console/

  # Avoided words that also occur in an ordinary, unrelated sense, recognised
  # by the exact names they appear in. Every name listed here must still occur
  # in lib/, so an allowance goes when its name does.
  @unrelated_senses [
    # Ecto query builders: each returns an Ecto.Query.
    %{
      word: "query",
      names:
        ~w(account_connection_query account_niches_query account_pages_query account_runs_query by_token_and_context_query in_progress_steps_query list_query run_phrases_query run_steps_query session_token_query user_tokens_query verify_change_email_token_query verify_magic_link_token_query verify_session_token_query)
    },
    # The Search Console API's `searchAnalytics/query` endpoint and its
    # `query` dimension (`SearchConsole.Client.query/1` and its helpers).
    %{word: "query", names: ~w(query query_answer query_request query_row)},
    # DataForSEO wraps every request and answer in "tasks".
    %{word: "task", names: ~w(post_task task_answer task_result)},
    # The kinds of structured request the LLM seam accepts (`LLM.tasks/0`,
    # the `task:` key of a request): one per output contract, not a Step.
    %{word: "task", names: ~w(tasks task unknown_llm_task)},
    # The HTTP verb.
    %{word: "post", names: ~w(post post_site post_task post_token)},
    # Oban jobs that run the Steps.
    %{word: "job", names: ~w(job step_job insert_step_job stop_and_cancel_jobs cancellable_job_states)},
    # Phoenix's flash group component.
    %{word: "group", names: ~w(flash_group)},
    # Phoenix.PubSub topics.
    %{word: "topic", names: ~w(topic user_session_topic)},
    # A URL path segment (RFC 3986) in the Netlify deploy URL.
    %{word: "segment", names: ~w(encode_segment)}
  ]

  test "no module, function, field or attr name uses a word the glossary says to avoid" do
    avoided = avoided_terms(File.read!(@glossary_path))

    offences =
      @source_glob
      |> Path.wildcard()
      |> Enum.flat_map(&offences_in_file(&1, avoided))

    assert offences == []
  end

  test "the check catches an avoided word in a new function name" do
    avoided = avoided_terms(File.read!(@glossary_path))
    source = "defmodule Dirmoon.Example do\n  def register_user(attrs), do: attrs\nend\n"

    assert [%{name: "register_user", avoided: "registration"}] = offences_in_source(source, avoided)
  end

  test "the check catches an avoided word in a name that only shares an allowed suffix" do
    avoided = avoided_terms(File.read!(@glossary_path))
    source = "defmodule Dirmoon.Example do\n  def niche_topic(niche), do: niche\nend\n"

    assert [%{name: "niche_topic", avoided: "topic"}] = offences_in_source(source, avoided)
  end

  test "the check catches an avoided word in an atom literal used as a value" do
    avoided = avoided_terms(File.read!(@glossary_path))
    source = "defmodule Dirmoon.Example do\n  def check(list), do: {:error, :too_many_keywords}\nend\n"

    assert [%{name: "too_many_keywords", avoided: "keyword"}] = offences_in_source(source, avoided)
  end

  test "the check catches an avoided word in a template id and an assign" do
    avoided = avoided_terms(File.read!(@glossary_path))
    source = ~s(<ul id="cluster-list"><li>{@segment_name}</li></ul>\n)

    assert [%{name: "cluster-list", avoided: "cluster"}, %{name: "segment_name", avoided: "segment"}] =
             offences_in_source(source, avoided)
  end

  test "every allowed name still occurs in lib" do
    names =
      @source_glob
      |> Path.wildcard()
      |> Enum.flat_map(&(&1 |> File.read!() |> declared_names()))
      |> MapSet.new()

    allowed = Map.keys(@allowed_names) ++ Enum.flat_map(@unrelated_senses, & &1.names)

    assert Enum.reject(allowed, &MapSet.member?(names, &1)) == []
  end

  test "no glossary definition uses one of its own term's avoided words" do
    misuses =
      for %{term: term, definition: definition, avoided: avoided} <- definitions(File.read!(@glossary_path)),
          word <- avoided,
          Regex.match?(~r/(?<!\p{L})#{Regex.escape(word)}(?!\p{L})/iu, definition) do
        %{term: term, avoided: word}
      end

    assert misuses == []
  end

  test "the definition check finds an avoided word used in its own definition" do
    glossary = "**Account**:\nThe tenant: everything belongs to one.\n_Avoid_: Customer (as a model name), tenant\n"

    assert [%{term: "Account", avoided: ["customer", "tenant"]}] = definitions(glossary)
  end

  test "the check catches an avoided word in a module name and a schema field" do
    avoided = avoided_terms(File.read!(@glossary_path))
    source = "defmodule Dirmoon.Phrases.KeywordList do\n  schema \"x\" do\n    field :stage, :string\n  end\nend\n"

    assert [%{name: "Dirmoon.Phrases.KeywordList"}, %{name: "stage"}] = offences_in_source(source, avoided)
  end

  defp avoided_terms(glossary) do
    ~r/^_Avoid_:\s*(.+)$/m
    |> Regex.scan(glossary, capture: :all_but_first)
    |> Enum.flat_map(fn [list] -> String.split(list, ",") end)
    |> Enum.map(&(&1 |> String.replace(~r/\(.*?\)/, "") |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.map(&%{term: &1, words: String.split(&1)})
  end

  defp definitions(glossary) do
    ~r/^\*\*(.+?)\*\*:\n((?:(?!_Avoid_:).+\n)+)_Avoid_:\s*(.+)$/m
    |> Regex.scan(glossary, capture: :all_but_first)
    |> Enum.map(fn [term, definition, avoided_list] ->
      %{
        term: term,
        definition: String.replace(definition, ~r/`[^`]*`/, ""),
        avoided: avoided_list |> avoided_words() |> Enum.map(&Enum.join(&1, " "))
      }
    end)
  end

  defp avoided_words(avoided_list) do
    avoided_list
    |> String.split(",")
    |> Enum.map(&(&1 |> String.replace(~r/\(.*?\)/, "") |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.split/1)
  end

  defp offences_in_file(path, avoided) do
    path
    |> File.read!()
    |> offences_in_source(avoided)
    |> Enum.map(&Map.put(&1, :file, path))
  end

  defp offences_in_source(source, avoided) do
    for name <- source |> declared_names() |> Enum.uniq(),
        not Map.has_key?(@allowed_names, name),
        checked_fragments = name |> String.replace(@known_phrases, " ") |> fragments(),
        %{term: term, words: words} <- avoided,
        not unrelated_sense?(name, term),
        uses_words?(checked_fragments, words) do
      %{name: name, avoided: term}
    end
  end

  defp declared_names(source) do
    patterns = [
      ~r/^\s*defmodule\s+([\w.]+)/m,
      ~r/^\s*(?:def|defp|defmacro|defmacrop|defguard|defguardp)\s+([a-z_][\w?!]*)/m,
      ~r/^\s*(?:field|embeds_one|embeds_many|belongs_to|has_many|has_one|attr|slot)\s+:([\w?!]+)/m,
      ~r/^\s*@(?:type|typep|opaque)\s+([a-z_][\w?!]*)/m,
      # Map and keyword-list keys.
      ~r/(?<![\w:"])([a-z_][a-z0-9_]*[?!]?):(?=\s)/,
      # Atom literals used as values: statuses, reasons, task names.
      ~r/(?<![\w:]):([a-z_][a-z0-9_]*[?!]?)/,
      # Template ids, static or the static start of an interpolated one.
      ~r/\bid=\{?"([a-z][\w-]*)/,
      # Assigns in templates (and module attributes).
      ~r/@([a-z_][a-z0-9_]*[?!]?)/
    ]

    patterns
    |> Enum.flat_map(&Regex.scan(&1, source, capture: :all_but_first))
    |> List.flatten()
  end

  defp unrelated_sense?(name, term) do
    Enum.any?(@unrelated_senses, &(&1.word == term and name in &1.names))
  end

  defp fragments(name) do
    ~r/[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+/
    |> Regex.scan(name)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
  end

  defp uses_words?(fragments, words) do
    fragments
    |> Enum.chunk_every(length(words), 1, :discard)
    |> Enum.any?(fn window ->
      window |> Enum.zip(words) |> Enum.all?(fn {fragment, word} -> same_word?(fragment, word) end)
    end)
  end

  defp same_word?(fragment, word) do
    fragment in [word, word <> "s", word <> "es"] or
      (String.length(fragment) >= 7 and String.length(word) >= 7 and
         String.slice(fragment, 0, 6) == String.slice(word, 0, 6))
  end
end
