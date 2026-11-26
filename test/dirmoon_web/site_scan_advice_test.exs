defmodule DirmoonWeb.SiteScanAdviceTest do
  use ExUnit.Case, async: true

  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.Findings
  alias Dirmoon.SiteScans.SiteScan
  alias DirmoonWeb.SiteScanAdvice

  @jargon ~w(niche phrase keyword SERP canonical)

  test "every check and level the Findings can give has a title, a meaning and, for something to fix, an action" do
    for %{question: question, check: check, level: level} <- Findings.checks() do
      finding = Finding.new(%{question: question, check: check, level: level})
      %{title: title, meaning: meaning, action: action} = SiteScanAdvice.sentences(finding)

      assert title =~ ~r/\S/, "#{check} #{level} has no title"
      assert meaning =~ ~r/\S/, "#{check} #{level} has no meaning"

      if level in [:problem, :warning],
        do: assert(action =~ ~r/\S/, "#{check} #{level} has no action"),
        else: assert(is_nil(action), "#{check} #{level} has an action")
    end
  end

  test "no sentence uses the words the owner doesn't know" do
    for %{question: question, check: check, level: level} <- Findings.checks(),
        sentence <- finding_sentences(%{question: question, check: check, level: level}),
        word <- @jargon do
      refute sentence =~ ~r/\b#{word}/i, "#{check} #{level} says “#{word}”"
    end
  end

  test "counts are written with thousands separators and the noun that agrees with them" do
    assert %{title: "1 page tells Google to leave it out."} = advice(:findable, :noindex, :warning, page_count: 1)

    assert %{title: "1,200 pages tell Google to leave them out."} =
             advice(:findable, :noindex, :warning, page_count: 1_200)

    assert %{title: "1 link on your site leads to a page that doesn't exist."} =
             advice(:findable, :broken_links, :problem, page_count: 1)

    assert %{title: "3 titles are too long."} = advice(:page_content, :long_titles, :warning, page_count: 3)
    assert %{title: "1 page has no title."} = advice(:page_content, :missing_title, :problem, page_count: 1)

    assert %{title: "1 page does not say which language it is in."} =
             advice(:business, :language_declared, :warning, page_count: 1)

    assert %{title: "2 pages do not say which language they are in."} =
             advice(:business, :language_declared, :warning, page_count: 2)

    assert %{title: "1 page is reached through several redirects."} =
             advice(:findable, :redirect_chains, :warning, page_count: 1)

    assert %{title: "1 page asks for a password."} = advice(:findable, :password_pages, :warning, page_count: 1)
    assert %{title: "1 page gives the visitor no next step."} = advice(:visitor, :ways_to_act, :warning, page_count: 1)
  end

  test "no sentence offers to run a finished scan again, as there is no way to" do
    for %{question: question, check: check, level: level} <- Findings.checks(),
        sentence <- finding_sentences(%{question: question, check: check, level: level}) do
      refute sentence =~ ~r/running the scan again/i, "#{check} #{level} offers to run the scan again"
    end
  end

  test "Google's page count is compared with the pages read only as far as the figures go" do
    assert %{title: "Google has about 12 pages of your site.", meaning: close} =
             advice(:findable, :indexed_pages, :good, figures: %{indexed_count: 12, pages_read: 10})

    assert close == "I read 10 pages on your site. Google's count is rough, but it isn't far from that."

    assert %{title: "Google has about 400 pages of your site.", meaning: more} =
             advice(:findable, :indexed_pages, :good, figures: %{indexed_count: 400, pages_read: 10})

    assert more ==
             "I read 10 pages on your site. Google knows more pages of your site than I read: your site may be larger than what I read, or Google may still keep old pages. Its count is rough."

    assert %{meaning: double} = advice(:findable, :indexed_pages, :good, figures: %{indexed_count: 20, pages_read: 10})
    assert double =~ "isn't far from that"
    refute double =~ "about as many"
  end

  test "pages matching no topic are said to match none of this research's topics, and may serve another purpose" do
    assert %{
             title: "2 pages match none of the topics in this research.",
             meaning:
               "These pages aren't about any topic I found for this research, and they don't show up on Google for any of the searches I checked. They may still serve another purpose, such as helping visitors already on your site.",
             action: "If they should bring visits from Google, make them about something people search for."
           } = advice(:niche_coverage, :pages_answering_no_phrase, :warning, page_count: 2)
  end

  test "every Finding that counts something agrees with a count of one" do
    for {question, check, level, attributes, expected} <- [
          {:findable, :noindex, :warning, [],
           %{
             meaning:
               "This page has a noindex tag (a tag that tells Google to leave a page out), so it won't show up on Google. If you hid it on purpose, that's fine.",
             action: "If it should show up on Google, ask whoever runs your site to remove the tag from it."
           }},
          {:findable, :broken_links, :problem, [],
           %{
             meaning:
               "Someone who clicks it lands on an error page instead of what they wanted, and Google wastes its visit on it.",
             action:
               "Fix the link or point it at the right page. If a page moved, ask whoever runs your site to send its old address to the new one."
           }},
          {:findable, :unreadable_pages, :warning, [],
           %{
             title: "I couldn't open 1 page.",
             meaning:
               "It didn't answer in time or the connection dropped. It may have been a passing hiccup, or your server may be slow or overloaded.",
             action: "Open this page yourself. If it is slow or doesn't load, tell whoever hosts your site."
           }},
          {:findable, :password_pages, :warning, [],
           %{
             meaning:
               "Google can't read what's behind a login, so this page won't show up on Google. If you hid it on purpose, that's fine.",
             action: "If it should be public, remove the login from it."
           }},
          {:findable, :blocked_pages, :warning, [],
           %{
             title: "Your robots.txt keeps Google out of 1 page.",
             meaning:
               "Your robots.txt (a file that tells search engines which pages they may read) blocks this page, so Google won't read it. If you hid it on purpose, that's fine.",
             action: "If it should show up on Google, ask whoever runs your site to remove its rule from robots.txt."
           }},
          {:findable, :indexed_pages, :warning, [figures: %{indexed_count: 1, pages_read: 1}],
           %{title: "Google seems to have only about 1 page of your site."}},
          {:page_content, :duplicate_titles, :warning, [], %{title: "1 page shares a title with another page."}},
          {:page_content, :long_titles, :warning, [],
           %{
             title: "1 title is too long.",
             meaning:
               "Google cuts titles (the blue link in its results) after about 60 characters, so the end of this one won't show.",
             action: "Shorten it and put the most important words first."
           }},
          {:page_content, :short_titles, :warning, [], %{title: "1 title is very short."}},
          {:page_content, :missing_description, :warning, [], %{title: "1 page has no description."}},
          {:page_content, :duplicate_descriptions, :warning, [],
           %{title: "1 page shares a description with another page."}},
          {:page_content, :long_descriptions, :warning, [],
           %{
             title: "1 description is too long.",
             meaning:
               "Google cuts descriptions (the lines under the blue link) after about 160 characters, so the end of this one won't show.",
             action: "Shorten it and say the most important thing first."
           }},
          {:page_content, :missing_main_heading, :warning, [], %{title: "1 page has no main heading."}},
          {:page_content, :several_main_headings, :warning, [], %{title: "1 page has more than one main heading."}},
          {:page_content, :little_text, :warning, [], %{title: "1 page has very little text."}},
          {:page_content, :duplicate_text, :warning, [], %{title: "1 page repeats the text of another page."}},
          {:niche_coverage, :niches_without_page, :problem, [figures: %{niche_count: 1, niches: [%{name: "Hotel"}]}],
           %{
             title: "1 topic worth going after has no page on your site.",
             meaning:
               "People search for it, but no page of yours is about it, so Google has nothing of yours to show for it: “Hotel”.",
             action:
               "Choose this topic in the results and I'll write the brief for its page: the plan and the text, ready to hand over."
           }},
          {:niche_coverage, :niches_with_page, :good, [figures: %{niche_count: 1}],
           %{
             title: "1 topic worth going after already has a page.",
             meaning: "Your site has a page about it, so Google has something of yours to show when people search for it."
           }},
          {:niche_coverage, :pages_answering_no_phrase, :warning, [],
           %{
             title: "1 page matches none of the topics in this research.",
             meaning:
               "This page isn't about any topic I found for this research, and it doesn't show up on Google for any of the searches I checked. It may still serve another purpose, such as helping visitors already on your site.",
             action: "If it should bring visits from Google, make it about something people search for."
           }},
          {:niche_coverage, :close_to_first_page, :warning, [figures: %{phrase_count: 1}],
           %{
             title: "1 search has you just past Google's first page.",
             meaning:
               "For this search your site is at position 11 to 20, on Google's second page, where few people look. Improving the page that shows up is the usual way to move up, though nothing guarantees it.",
             action:
               "Make that page more useful to the people who type it. Add text about what they want, give it a clear title and link to it from your other pages."
           }},
          {:visitor, :viewport, :warning, [],
           %{
             title: "1 page is not set up for phone screens.",
             meaning:
               "It has no viewport setting (a line in the page code that fits the page to a phone's screen), so phones show it shrunken."
           }},
          {:visitor, :ways_to_act, :warning, [],
           %{
             meaning:
               "It has no phone link, e-mail link, form or button, so someone who likes what they read has to go looking for how to reach you.",
             action: "Add a clear next step to it: a “Call us” button, a form or a link to your contact page."
           }},
          {:business, :phone_numbers, :warning, [figures: %{phone_count: 1}],
           %{title: "Your pages show 1 phone number."}},
          {:business, :tappable_contact, :good, [figures: %{phone_count: 1, email_count: 1}],
           %{meaning: "I found 1 phone number and 1 e-mail address as links on your pages."}}
        ] do
      sentences = advice(question, check, level, Keyword.put_new(attributes, :page_count, 1))
      assert Map.take(sentences, Map.keys(expected)) == expected, "#{check} #{level} doesn't agree with one"
    end
  end

  test "a figure of an unexpected type is left out of the sentence" do
    assert %{title: "Some topics worth going after have no page on your site."} =
             advice(:niche_coverage, :niches_without_page, :problem, figures: %{niche_count: "dużo", niches: "nic"})

    assert %{title: "Some images on some pages have no description."} =
             advice(:page_content, :images_without_description, :warning, page_count: nil, figures: %{images: "?"})

    assert %{meaning: meaning} = advice(:visitor, :performance_score, :warning, figures: %{score: "?"})
    assert meaning =~ "an unknown score"
    assert %{meaning: meaning} = advice(:visitor, :largest_contentful_paint, :good, figures: %{milliseconds: nil})
    assert meaning =~ "an unknown time"
    assert %{meaning: meaning} = advice(:visitor, :interaction_to_next_paint, :good, figures: %{milliseconds: nil})
    assert meaning =~ "an unknown time"
    assert %{meaning: meaning} = advice(:visitor, :cumulative_layout_shift, :good, figures: %{value: nil, source: 7})
    assert meaning =~ "is unknown (measured by Google)"
  end

  test "the speed figures say whether Google's test or real visitors measured them" do
    assert %{meaning: lab} =
             advice(:visitor, :largest_contentful_paint, :problem, figures: %{milliseconds: 4_800, source: "lab"})

    assert lab =~ "shows after 4.8 seconds (measured by Google's test)"

    assert %{meaning: page} =
             advice(:visitor, :interaction_to_next_paint, :warning, figures: %{milliseconds: 1_250, source: "page"})

    assert page =~ "1,250 milliseconds to react to a tap (measured on real visitors' phones)"

    assert %{meaning: origin} =
             advice(:visitor, :cumulative_layout_shift, :problem, figures: %{value: 0.3, source: "origin"})

    assert origin =~ "0.30 (measured on real visitors' phones across your whole site)"

    assert %{meaning: score} = advice(:visitor, :performance_score, :problem, figures: %{score: 41.6})
    assert score =~ "scored it 42 out of 100 (measured by Google's test)"
  end

  test "each failed phone check is named in plain words" do
    for id <- ["meta-viewport", "viewport-insight"] do
      assert %{title: "Your home page isn't set up for phone screens."} =
               advice(:visitor, :phone_usability, :warning, figures: %{check_id: id})
    end

    assert %{title: "Buttons and links on your home page are hard to tap."} =
             advice(:visitor, :phone_usability, :warning, figures: %{check_id: "target-size"})

    assert %{title: "Google's phone test found a problem on your home page."} =
             advice(:visitor, :phone_usability, :warning, figures: %{check_id: "inny-test"})
  end

  test "checks not made say why, without blaming the owner" do
    assert %{meaning: "Phone speed wasn't checked: Google's speed test isn't connected here."} =
             advice(:visitor, :speed, :not_checked, figures: %{reason: "not_configured"})

    assert %{meaning: "Google's speed test was busy" <> _rest} =
             advice(:visitor, :speed, :not_checked, figures: %{reason: "quota"})

    assert %{meaning: "Google's speed test couldn't open your home page."} =
             advice(:visitor, :speed, :not_checked, figures: %{reason: "page_unreachable"})

    assert %{meaning: "Google's speed test failed. I'll try again in the next research of this site."} =
             advice(:visitor, :speed, :not_checked, figures: %{reason: "failed"})

    assert %{
             meaning: "Google's speed test was busy and turned me away. I'll try again in the next research of this site."
           } =
             advice(:visitor, :speed, :not_checked, figures: %{reason: "quota"})

    assert %{meaning: "The service I use to look up the number of your pages on Google isn't connected here."} =
             advice(:findable, :indexed_pages, :not_checked, figures: %{reason: "not_configured"})

    assert %{meaning: "This research runs on test data" <> _rest} =
             advice(:findable, :indexed_pages, :not_checked, figures: %{reason: "not_in_demo_data"})

    assert %{
             meaning:
               "I asked for the number of your pages on Google, but the request failed. I'll try again in the next research of this site."
           } =
             advice(:findable, :indexed_pages, :not_checked, figures: %{reason: "failed"})

    assert %{title: "I can't tell whether Google has all your pages.", meaning: meaning} =
             advice(:findable, :indexed_pages, :not_checked,
               figures: %{reason: "page_limit_reached", indexed_count: 30, pages_read: 50}
             )

    assert meaning =~ "about 30 pages of your site. I stopped after reading 50 pages"
  end

  test "the matching of pages to topics says why it isn't done" do
    assert %{meaning: "I'll do it once I've read your site" <> _rest} =
             advice(:niche_coverage, :niche_matching, :not_checked, figures: %{reason: "not_ready"})

    assert %{meaning: "This research runs on test data" <> _rest} =
             advice(:niche_coverage, :niche_matching, :not_checked, figures: %{reason: "not_in_demo_data"})

    assert %{meaning: "The AI service I use to match pages to topics isn't connected here."} =
             advice(:niche_coverage, :niche_matching, :not_checked, figures: %{reason: "not_configured"})

    assert %{meaning: "I tried to match your pages to the topics, but it failed."} =
             advice(:niche_coverage, :niche_matching, :not_checked, figures: %{reason: "failed"})
  end

  test "the Business Profile says what was found and why it wasn't looked up" do
    found = %{found: true, links_to_site: true, title: "Firma testowa", rating: 4, votes: 12}

    assert %{
             meaning:
               "I found “Firma testowa” on Google, rated 4.0 from 12 reviews, and its website link points here." <> _rest
           } =
             advice(:business, :business_profile, :good, figures: found)

    assert %{
             title: "Your Google Business Profile doesn't link to your site.",
             meaning: "I found “Firma” on Google, but" <> _rest
           } =
             advice(:business, :business_profile, :warning, figures: %{found: true, name: "Firma", votes: 0, rating: 3.0})

    assert %{title: "I couldn't find a Google Business Profile for “Firma”."} =
             advice(:business, :business_profile, :warning, figures: %{found: false, name: "Firma"})

    assert %{title: "I couldn't find a Google Business Profile for your business."} =
             advice(:business, :business_profile, :warning, figures: %{found: false, name: nil})

    assert %{meaning: "Your site's structured data (labels in the page code" <> _rest} =
             advice(:business, :business_profile, :not_checked, figures: %{reason: "no_business_name"})

    assert %{meaning: "Google's business listings can't be searched for your area."} =
             advice(:business, :business_profile, :not_checked, figures: %{reason: "unavailable"})

    assert %{meaning: "The service I use to look up your Business Profile isn't connected here."} =
             advice(:business, :business_profile, :not_checked, figures: %{reason: "not_configured"})
  end

  test "the sites linking to yours are counted in plain words, said to be approximate, and never promise a place" do
    assert %{
             title: "17 other sites link to yours.",
             meaning:
               "Links from other sites are one of the ways Google decides how much to trust a site. The count comes from a third-party index of links, so it is approximate."
           } = advice(:business, :linking_sites, :good, figures: %{count: 17})

    assert %{title: "1 other site links to yours."} = advice(:business, :linking_sites, :good, figures: %{count: 1})

    assert %{title: "1,250 other sites link to yours."} =
             advice(:business, :linking_sites, :good, figures: %{count: 1_250})

    assert %{title: "Some other sites link to yours."} =
             advice(:business, :linking_sites, :good, figures: %{count: "17"})

    assert %{title: "No other site links to yours yet.", meaning: meaning, action: "Ask the businesses" <> _rest} =
             advice(:business, :linking_sites, :warning, figures: %{count: 0})

    assert meaning =~ "third-party index of links"

    assert %{title: "I don't know how many other sites link to yours.", meaning: "The third-party index" <> _rest} =
             advice(:business, :linking_sites, :not_checked, figures: %{reason: "no_data"})

    assert %{meaning: "The service I use to count links from other sites turned the request away."} =
             advice(:business, :linking_sites, :not_checked, figures: %{reason: "unavailable"})

    assert %{meaning: "The service I use to look up the number of sites that link to yours isn't connected here."} =
             advice(:business, :linking_sites, :not_checked, figures: %{reason: "not_configured"})

    assert %{meaning: "I asked for the number of sites that link to yours, but the request failed." <> _rest} =
             advice(:business, :linking_sites, :not_checked, figures: %{reason: "failed"})
  end

  test "figures behind a Finding are named in its sentences" do
    assert %{meaning: "I opened https://a.example/ and https://www.a.example/. Both" <> _rest} =
             advice(:findable, :www_and_bare, :warning,
               figures: %{addresses: ["https://a.example/", "https://www.a.example/"]}
             )

    assert %{
             meaning:
               "Your robots.txt (a file that tells search engines which pages they may read) answered with an error (code 503)." <>
                 _rest
           } =
             advice(:findable, :robots_txt, :warning, figures: %{status: 503})

    assert %{title: "Your site has no robots.txt, so Google may read every page."} =
             advice(:findable, :robots_txt, :good, figures: %{present: false})

    assert %{title: "Your robots.txt lets Google in."} = advice(:findable, :robots_txt, :good, figures: %{present: true})
    assert %{meaning: meaning} = advice(:findable, :sitemap, :good, figures: %{page_count: 12})
    assert meaning =~ "Yours lists 12 pages."

    assert %{meaning: "I checked 1 link between your pages, and each opened a page."} =
             advice(:findable, :broken_links, :good, figures: %{links_checked: 1})

    assert %{meaning: "Every link between your pages that I checked opened a page."} =
             advice(:findable, :broken_links, :good)

    assert %{title: "Google seems to have only about 2 pages of your site."} =
             advice(:findable, :indexed_pages, :warning, figures: %{indexed_count: 2, pages_read: 30})

    assert %{title: "3 of 10 images on 2 pages have no description."} =
             advice(:page_content, :images_without_description, :warning,
               page_count: 2,
               figures: %{images: 10, without_description: 3}
             )

    assert %{title: "1 image on 1 page has no description."} =
             advice(:page_content, :images_without_description, :warning,
               page_count: 1,
               figures: %{without_description: 1}
             )

    assert %{meaning: meaning} =
             advice(:niche_coverage, :niches_without_page, :problem,
               figures: %{niche_count: 5, niches: Enum.map(1..5, &%{id: &1, name: "Temat #{&1}", volume: 10})}
             )

    assert meaning =~ ": “Temat 1”, “Temat 2”, “Temat 3” and 2 more."

    assert %{title: "Your pages show 2 different phone numbers.", meaning: phones} =
             advice(:business, :phone_numbers, :warning,
               figures: %{phone_count: 2, phones: ["+48500000001", "+48500000002"]}
             )

    assert phones =~ ": “+48500000001”, “+48500000002”."

    assert %{meaning: "I found 1 phone number and 2 e-mail addresses as links on your pages."} =
             advice(:business, :tappable_contact, :good, figures: %{phone_count: 1, email_count: 2})

    assert %{
             meaning:
               "Structured data (labels in the page code that tell Google your name, address and prices) help Google understand your business. I found these kinds: “LocalBusiness”."
           } =
             advice(:business, :structured_data, :good, figures: %{types: ["LocalBusiness"]})

    assert %{
             meaning:
               "Structured data (labels in the page code that tell Google your name, address and prices) help Google understand your business."
           } =
             advice(:business, :structured_data, :good, figures: %{types: []})

    assert %{
             meaning:
               "Google's test found no viewport setting (a line in the page code that fits the page to a phone's screen), so phones show a shrunken desktop page."
           } =
             advice(:visitor, :phone_usability, :warning, figures: %{check_id: "meta-viewport"})

    assert %{title: "Your pages say they are in: pl, en."} =
             advice(:business, :declared_languages, :good, figures: %{languages: ["pl", "en"]})

    assert %{title: "2 searches have you just past Google's first page."} =
             advice(:niche_coverage, :close_to_first_page, :warning, figures: %{phrase_count: 2})

    assert %{title: "1 topic has more than one page: “Hotel”."} =
             advice(:niche_coverage, :several_pages_for_one_niche, :warning,
               figures: %{niches: [%{id: 1, name: "Hotel"}]}
             )

    assert %{title: "2 topics have more than one page: “Hotel”, “Spa”."} =
             advice(:niche_coverage, :several_pages_for_one_niche, :warning,
               figures: %{niches: [%{id: 1, name: "Hotel"}, %{id: 2, name: "Spa"}]}
             )

    assert %{title: "Some topics have more than one page."} =
             advice(:niche_coverage, :several_pages_for_one_niche, :warning, figures: %{niches: "?"})
  end

  test "the questions are plain, with what people search for first" do
    assert SiteScanAdvice.questions_in_screen_order() ==
             [:niche_coverage, :findable, :page_content, :visitor, :business]

    for question <- Finding.questions() do
      assert SiteScanAdvice.question(question) =~ ~r/\?$/
    end
  end

  test "each level has a text label, so colour is never the only sign" do
    assert Enum.map(Finding.levels(), &SiteScanAdvice.level_label/1) == [
             "Fix this",
             "Worth improving",
             "Not checked",
             "Fine"
           ]
  end

  test "the status sentence says in the first person where the scan stands" do
    scanning = %SiteScan{status: :scanning, pages_read: 12, updated_at: DateTime.utc_now()}
    stale = %{scanning | updated_at: DateTime.shift(DateTime.utc_now(), hour: -3)}
    done = %SiteScan{status: :done, pages_read: 34}
    problem = Finding.new(%{question: :findable, check: :https, level: :problem})
    good = Finding.new(%{question: :findable, check: :sitemap, level: :good})

    assert SiteScanAdvice.status_line(%{scan: scanning, domain: "strona.example", findings: []}) ==
             "I'm reading strona.example: 12 pages so far."

    assert SiteScanAdvice.status_line(%{scan: stale, domain: "strona.example", findings: []}) ==
             "My reading of strona.example stopped part-way, after 12 pages. I can pick it up where it stopped."

    assert SiteScanAdvice.status_line(%{scan: done, domain: "strona.example", findings: [problem, good]}) ==
             "I read 34 pages of strona.example and found 1 thing to fix."

    assert SiteScanAdvice.status_line(%{scan: %SiteScan{status: :failed}, domain: "strona.example", findings: []}) ==
             "I couldn't read strona.example."

    assert SiteScanAdvice.status_line(%{scan: nil}) == "This research has no site to read."
    assert SiteScanAdvice.progress_line(done, "strona.example") == "I read 34 pages of strona.example."
  end

  defp advice(question, check, level, attributes \\ []) do
    finding =
      Finding.new(%{question: question, check: check, level: level, figures: Keyword.get(attributes, :figures, %{})})

    SiteScanAdvice.sentences(%{finding | page_count: Keyword.get(attributes, :page_count, 3)})
  end

  defp finding_sentences(pair) do
    pair
    |> Map.put(:figures, %{reason: "failed"})
    |> Finding.new()
    |> SiteScanAdvice.sentences()
    |> Map.values()
    |> Enum.filter(&is_binary/1)
  end
end
