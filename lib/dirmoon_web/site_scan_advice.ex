defmodule DirmoonWeb.SiteScanAdvice do
  @moduledoc """
  What the "Your site" screen says about a Site Scan, in plain English for a
  small-business owner who doesn't know SEO: each Finding as a title, what
  it means and what to do (`sentences/1`), the plain question each group of
  Findings answers (`question/1`), the label of each level (`level_label/1`)
  and the first-person sentences about the scan itself (`progress_line/2`,
  `status_line/1`).

  Every check and level `Dirmoon.SiteScans.Findings.checks/0` lists has its
  copy here. Figures come from the Finding and are formatted with
  `Dirmoon.Format`; a figure of an unexpected type is left out of the
  sentence, never shown raw. Jargon is explained in the same sentence,
  Niches are "topics" and Phrases "searches", and nothing promises a place
  on Google.
  """

  alias Dirmoon.Format
  alias Dirmoon.SiteScans
  alias Dirmoon.SiteScans.Finding
  alias Dirmoon.SiteScans.SiteScan

  @questions %{
    niche_coverage: "Does your site cover what people search for?",
    findable: "Can Google find and read your site?",
    page_content: "Does each page say what it is about?",
    visitor: "Does it work for a visitor on a phone?",
    business: "Does it look like a real business to Google?"
  }

  @level_labels %{problem: "Fix this", warning: "Worth improving", good: "Fine", not_checked: "Not checked"}

  @page_forms %{one: "page", other: "pages"}
  @niche_forms %{one: "topic", other: "topics"}
  @phrase_forms %{one: "search", other: "searches"}
  @thing_forms %{one: "thing", other: "things"}
  @link_forms %{one: "link", other: "links"}
  @title_forms %{one: "title", other: "titles"}
  @description_forms %{one: "description", other: "descriptions"}
  @image_forms %{one: "image", other: "images"}
  @number_forms %{one: "phone number", other: "phone numbers"}
  @address_forms %{one: "e-mail address", other: "e-mail addresses"}
  @linking_site_forms %{one: "other site", other: "other sites"}
  @names_shown 3

  @sources %{
    "page" => "measured on real visitors' phones",
    "origin" => "measured on real visitors' phones across your whole site",
    "lab" => "measured by Google's test"
  }

  @who_runs_the_site "whoever runs your site"
  @viewport_explained "viewport setting (a line in the page code that fits the page to a phone's screen)"
  @structured_data_explained "Structured data (labels in the page code that tell Google your name, address and prices)"
  @robots_explained "robots.txt (a file that tells search engines which pages they may read)"
  @noindex_explained "a noindex tag (a tag that tells Google to leave a page out)"
  @sitemap_explained "a sitemap (a list of your pages for Google)"
  @title_explained "the title (the line Google shows as the blue link in its results)"
  @next_research "I'll try again in the next research of this site."
  @why_links_count "Links from other sites are one of the ways Google decides how much to trust a site."
  @approximate_links "The count comes from a third-party index of links, so it is approximate."

  @doc "The plain question a group of Findings answers, as the screen's heading."
  def question(question), do: Map.fetch!(@questions, question)

  @doc "The questions in the order the screen shows them: what only dirmoon can tell first."
  def questions_in_screen_order do
    [:niche_coverage | Finding.questions() -- [:niche_coverage]]
  end

  @doc "The label shown beside a Finding's level marker."
  def level_label(level), do: Map.fetch!(@level_labels, level)

  @doc """
  One line saying where the scan of the site at `domain` stands: reading,
  read, stopped part-way on dirmoon's side (`Dirmoon.SiteScans.stale?/1`)
  or failed.
  """
  def progress_line(%SiteScan{status: :scanning, pages_read: pages_read} = scan, domain) do
    if SiteScans.stale?(scan),
      do: "My reading of #{domain} stopped part-way, after #{pages(pages_read)}. I can pick it up where it stopped.",
      else: "I'm reading #{domain}: #{pages(pages_read)} so far."
  end

  def progress_line(%SiteScan{status: :done, pages_read: pages_read}, domain),
    do: "I read #{pages(pages_read)} of #{domain}."

  def progress_line(%SiteScan{status: :failed}, domain), do: "I couldn't read #{domain}."

  @doc """
  The "Your site" screen's status sentence: the progress line, and for a
  finished scan how many things it found to fix (problems and warnings).
  `scan` is nil for a run without a site.
  """
  def status_line(%{scan: nil}), do: "This research has no site to read."

  def status_line(%{scan: %SiteScan{status: :done, pages_read: pages_read}, domain: domain, findings: findings}) do
    case Enum.count(findings, &(&1.level in [:problem, :warning])) do
      0 -> "I read #{pages(pages_read)} of #{domain} and found nothing to fix."
      to_fix -> "I read #{pages(pages_read)} of #{domain} and found #{counted(to_fix, @thing_forms)} to fix."
    end
  end

  def status_line(%{scan: scan, domain: domain}), do: progress_line(scan, domain)

  @doc """
  What the screen says about one Finding: `%{title:, meaning:, action:}`,
  each a short sentence; `action` is nil when there is nothing to do (good
  news, or a check that was not made).
  """
  def sentences(%Finding{check: check, level: level, page_count: page_count, figures: figures}) do
    advice(check, level, %{count: page_count, figures: figures})
  end

  defp advice(:https, :problem, _finding),
    do:
      sentences(
        "Your site doesn't open over a secure connection (https).",
        "Browsers mark pages without https as “Not secure”, and Google prefers secure sites. Many visitors leave when they see the warning.",
        "Ask #{@who_runs_the_site} to switch on https (a free certificate is enough) and send every http address to its https version."
      )

  defp advice(:https, :good, _finding),
    do:
      sentences(
        "Your site opens over a secure connection (https).",
        "Browsers show it as secure, as visitors and Google expect."
      )

  defp advice(:www_and_bare, :warning, %{figures: figures}),
    do:
      sentences(
        "Your site answers both with and without “www.”.",
        "#{listed_addresses(figures[:addresses])}Both show the site without sending one to the other, so Google may see two copies of it and split its attention between them.",
        "Ask #{@who_runs_the_site} to send one address to the other with a permanent redirect (a 301), so only one is left."
      )

  defp advice(:www_and_bare, :good, _finding),
    do:
      sentences(
        "Your site has one address, with or without “www.”.",
        "One version sends visitors to the other, so Google sees a single site."
      )

  defp advice(:robots_txt, :problem, _finding),
    do:
      sentences(
        "Your robots.txt tells Google to stay out of the whole site.",
        "Your #{@robots_explained} blocks every page, so Google can't read your site and won't show it.",
        "Ask #{@who_runs_the_site} to remove the “Disallow: /” line from robots.txt."
      )

  defp advice(:robots_txt, :warning, %{figures: figures}),
    do:
      sentences(
        "I couldn't read your robots.txt.",
        "Your #{@robots_explained} answered with an error#{status_note(figures[:status])}. When Google gets an error there, it may stop reading your site for a while.",
        "Ask #{@who_runs_the_site} to make robots.txt open normally, or remove it if you don't need it."
      )

  defp advice(:robots_txt, :good, %{figures: %{present: false}}),
    do:
      sentences(
        "Your site has no robots.txt, so Google may read every page.",
        "A #{@robots_explained} is optional. Without one, Google reads everything it finds."
      )

  defp advice(:robots_txt, :good, _finding),
    do: sentences("Your robots.txt lets Google in.", "Your #{@robots_explained} doesn't block your site.")

  defp advice(:noindex, :problem, _finding),
    do:
      sentences(
        "Your home page tells Google to leave it out.",
        "Your home page has #{@noindex_explained}, so Google won't show it in its results.",
        "Ask #{@who_runs_the_site} to remove the noindex tag from the home page, and check the other pages listed here too."
      )

  defp advice(:noindex, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "tells", "tell")} Google to leave #{agree(count, "it", "them")} out.",
        "#{agree(count, "This page has", "These pages have")} #{@noindex_explained}, so #{agree(count, "it", "they")} won't show up on Google. #{on_purpose(count)}",
        "If #{agree(count, "it", "any of them")} should show up on Google, ask #{@who_runs_the_site} to remove the tag from it."
      )

  defp advice(:noindex, :good, _finding),
    do: sentences("No page tells Google to leave it out.", "None of the pages I read has #{@noindex_explained}.")

  defp advice(:sitemap, :warning, _finding),
    do:
      sentences(
        "Your site has no sitemap.",
        "#{capitalised(@sitemap_explained)} helps Google find every page, especially new ones and those few links lead to.",
        "Ask #{@who_runs_the_site} to add a sitemap at /sitemap.xml. Most site builders can make one for you."
      )

  defp advice(:sitemap, :good, %{figures: figures}),
    do:
      sentences(
        "Your site has a sitemap.",
        "#{capitalised(@sitemap_explained)} helps Google find every page.#{sitemap_count(figures[:page_count])}"
      )

  defp advice(:broken_links, :problem, %{count: count}),
    do:
      sentences(
        "#{capitalised(counted(count, @link_forms))} on your site #{agree(count, "leads", "lead")} to a page that doesn't exist.",
        "Someone who clicks #{agree(count, "it", "one of them")} lands on an error page instead of what they wanted, and Google wastes its visit on #{agree(count, "it", "them")}.",
        "Fix #{agree(count, "the link", "each link")} or point it at the right page. If a page moved, ask #{@who_runs_the_site} to send its old address to the new one."
      )

  defp advice(:broken_links, :good, %{figures: figures}),
    do: sentences("I found no broken link.", links_checked_sentence(count(figures[:links_checked])))

  defp advice(:unreadable_pages, :warning, %{count: count}),
    do:
      sentences(
        "I couldn't open #{pages(count)}.",
        "#{agree(count, "It", "They")} didn't answer in time or the connection dropped. It may have been a passing hiccup, or your server may be slow or overloaded.",
        "Open #{agree(count, "this page", "these pages")} yourself. If #{agree(count, "it is slow or doesn't", "they are slow or don't")} load, tell whoever hosts your site."
      )

  defp advice(:unreadable_pages, :good, _finding),
    do:
      sentences("Every page I tried opened.", "None of your pages timed out or dropped the connection while I read them.")

  defp advice(:redirect_chains, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "is", "are")} reached through several redirects.",
        "A redirect sends a visitor from one address to another. Two or more in a row slow the page down, and Google may stop following them.",
        "Ask #{@who_runs_the_site} to point links and redirects straight at the final address."
      )

  defp advice(:redirect_chains, :good, _finding),
    do:
      sentences(
        "No page goes through a chain of redirects.",
        "Each page I read opens directly, or after one redirect (a jump from one address to another) at most."
      )

  defp advice(:password_pages, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "asks", "ask")} for a password.",
        "Google can't read what's behind a login, so #{agree(count, "this page", "these pages")} won't show up on Google. #{on_purpose(count)}",
        "If #{agree(count, "it", "any of them")} should be public, remove the login from it."
      )

  defp advice(:password_pages, :good, _finding),
    do: sentences("No page asks for a password.", "Google can read every page I opened.")

  defp advice(:blocked_pages, :warning, %{count: count}),
    do:
      sentences(
        "Your robots.txt keeps Google out of #{pages(count)}.",
        "Your #{@robots_explained} blocks #{agree(count, "this page", "these pages")}, so Google won't read #{agree(count, "it", "them")}. #{on_purpose(count)}",
        "If #{agree(count, "it", "any of them")} should show up on Google, ask #{@who_runs_the_site} to remove its rule from robots.txt."
      )

  defp advice(:blocked_pages, :good, _finding),
    do: sentences("Your robots.txt blocks none of the pages I found.", "Google may read every page your site links to.")

  defp advice(:indexed_pages, :problem, _finding),
    do:
      sentences(
        "Google shows none of your pages.",
        "When I asked Google for the pages it has from your site, it had none, so nobody finds you through Google yet.",
        "Add your site to Google Search Console (Google's free tool for site owners) and send it your sitemap. Check that no noindex tag or robots.txt rule hides the site."
      )

  defp advice(:indexed_pages, :warning, %{figures: figures}),
    do:
      sentences(
        "Google seems to have only about #{pages(count(figures[:indexed_count]))} of your site.",
        "I read #{pages(count(figures[:pages_read]))} on your site. Google's count is rough, but a gap this big usually means it hasn't found or kept many of your pages.",
        "Make sure your sitemap lists every page, and link to the missing pages from your other pages."
      )

  defp advice(:indexed_pages, :good, %{figures: figures}),
    do:
      sentences(
        "Google has about #{pages(count(figures[:indexed_count]))} of your site.",
        "I read #{pages(count(figures[:pages_read]))} on your site. #{indexed_compared(count(figures[:indexed_count]), count(figures[:pages_read]))}"
      )

  defp advice(:indexed_pages, :not_checked, %{figures: %{reason: "page_limit_reached"} = figures}),
    do:
      sentences(
        "I can't tell whether Google has all your pages.",
        "Google has about #{pages(count(figures[:indexed_count]))} of your site. I stopped after reading #{pages(count(figures[:pages_read]))}, so your site may have more than I saw and the two can't be compared."
      )

  defp advice(:indexed_pages, :not_checked, %{figures: figures}),
    do:
      sentences(
        "I didn't check how many of your pages Google has.",
        not_checked_reason(figures[:reason], "the number of your pages on Google")
      )

  defp advice(:missing_title, :problem, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "has", "have")} no title.",
        "#{capitalised(@title_explained)} tells people and Google what a page is about. Without one, Google makes up its own.",
        "Give each page a short title of its own that says what it offers, for example the service and your town."
      )

  defp advice(:missing_title, :good, _finding),
    do: sentences("Every page has a title.", "#{capitalised(@title_explained)} tells people what each page is about.")

  defp advice(:duplicate_titles, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "shares", "share")} a title with another page.",
        "When pages have the same title (the blue link in Google's results), Google can't tell which one to show, and people can't tell them apart.",
        "Give each page a title of its own that says what is different about it."
      )

  defp advice(:duplicate_titles, :good, _finding),
    do: sentences("Each page has a title of its own.", "No two pages share the line Google shows as the blue link.")

  defp advice(:long_titles, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(counted(count, @title_forms))} #{agree(count, "is", "are")} too long.",
        "Google cuts titles (the blue link in its results) after about 60 characters, so the end of #{agree(count, "this one", "these")} won't show.",
        "Shorten #{agree(count, "it", "them")} and put the most important words first."
      )

  defp advice(:long_titles, :good, _finding),
    do: sentences("No title is too long.", "Every title fits in Google's results without being cut.")

  defp advice(:short_titles, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(counted(count, @title_forms))} #{agree(count, "is", "are")} very short.",
        "A title (the blue link in Google's results) under 10 characters says little about the page, and Google may replace it with its own.",
        "Write titles that say what the page offers, for example the service and your town."
      )

  defp advice(:short_titles, :good, _finding),
    do: sentences("No title is too short.", "Every title has room to say what its page offers.")

  defp advice(:missing_description, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "has", "have")} no description.",
        "The description (the two lines Google may show under the blue link) helps people decide to click. Without one, Google picks some text from the page.",
        "Write one or two sentences for each page saying what the visitor gets there."
      )

  defp advice(:missing_description, :good, _finding),
    do: sentences("Every page has a description.", "The description is the text Google may show under the blue link.")

  defp advice(:duplicate_descriptions, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "shares", "share")} a description with another page.",
        "People see the same text (the lines under the blue link in Google's results) for different pages and can't tell them apart.",
        "Write a description of its own for each page."
      )

  defp advice(:duplicate_descriptions, :good, _finding),
    do:
      sentences(
        "Each page has a description of its own.",
        "No two pages share the text Google may show under the blue link."
      )

  defp advice(:long_descriptions, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(counted(count, @description_forms))} #{agree(count, "is", "are")} too long.",
        "Google cuts descriptions (the lines under the blue link) after about 160 characters, so the end of #{agree(count, "this one", "these")} won't show.",
        "Shorten #{agree(count, "it", "them")} and say the most important thing first."
      )

  defp advice(:long_descriptions, :good, _finding),
    do: sentences("No description is too long.", "Every description fits in Google's results without being cut.")

  defp advice(:missing_main_heading, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "has", "have")} no main heading.",
        "The main heading (the big headline at the top of a page) tells visitors and Google at a glance what the page is about.",
        "Add one clear headline at the top of each page that says what it offers."
      )

  defp advice(:missing_main_heading, :good, _finding),
    do: sentences("Every page has a main heading.", "Each page opens with a headline that says what it is about.")

  defp advice(:several_main_headings, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "has", "have")} more than one main heading.",
        "A page with several main headings (big headlines marked as the most important) makes it harder for Google to tell what the page is mainly about.",
        "Keep one main heading per page and make the others smaller headings."
      )

  defp advice(:several_main_headings, :good, _finding),
    do: sentences("Every page has one main heading.", "Google can tell what each page is mainly about.")

  defp advice(:little_text, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "has", "have")} very little text.",
        "Pages with fewer than 150 words give Google little to go on, and rarely answer a visitor's question.",
        "Add useful text: what you offer, for whom, where, how it works and what it costs."
      )

  defp advice(:little_text, :good, _finding),
    do: sentences("Every page has a fair amount of text.", "Each page gives visitors and Google something to read.")

  defp advice(:duplicate_text, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "repeats", "repeat")} the text of another page.",
        "When pages say the same thing word for word, Google shows only one of them, and the others are wasted.",
        "Rewrite each page so it says something of its own, or merge pages that cover the same thing."
      )

  defp advice(:duplicate_text, :good, _finding),
    do: sentences("Every page has text of its own.", "No two pages say the same thing word for word.")

  defp advice(:images_without_description, :warning, %{count: count, figures: figures}),
    do:
      sentences(
        "#{images_lacking(figures)} on #{pages(count)} #{agree(count(figures[:without_description]), "has", "have")} no description.",
        "An image description (alt text: a few words read out to people who can't see the image, and read by Google) tells Google what the image shows.",
        "Add a short description to each image saying what it shows."
      )

  defp advice(:images_without_description, :good, _finding),
    do: sentences("Every image has a description.", "Google and people who can't see the images know what they show.")

  defp advice(:niche_matching, :not_checked, %{figures: figures}),
    do: sentences("I haven't matched your pages to the topics yet.", matching_reason(figures[:reason]))

  defp advice(:niches_without_page, :problem, %{figures: figures}) do
    niche_count = count(figures[:niche_count])

    sentences(
      "#{capitalised(counted(niche_count, @niche_forms))} worth going after #{agree(niche_count, "has", "have")} no page on your site.",
      "People search for #{agree(niche_count, "it", "these")}, but no page of yours is about #{agree(niche_count, "it", "them")}, so Google has nothing of yours to show for #{agree(niche_count, "it", "them")}#{named(niche_names(figures[:niches]))}.",
      "Choose #{agree(niche_count, "this topic", "one of these topics")} in the results and I'll write the brief for its page: the plan and the text, ready to hand over."
    )
  end

  defp advice(:niches_with_page, :good, %{figures: figures}) do
    niche_count = count(figures[:niche_count])

    sentences(
      "#{capitalised(counted(niche_count, @niche_forms))} worth going after already #{agree(niche_count, "has", "have")} a page.",
      "Your site has a page about #{agree(niche_count, "it", "each of these")}, so Google has something of yours to show when people search for #{agree(niche_count, "it", "them")}."
    )
  end

  defp advice(:several_pages_for_one_niche, :warning, %{figures: figures}),
    do:
      sentences(
        "#{split_niches(niche_names(figures[:niches]))}#{named(niche_names(figures[:niches]))}.",
        "When two pages are about the same thing, they compete with each other on Google, and neither does as well as one strong page would.",
        "Merge them into one page, or make each about something clearly different."
      )

  defp advice(:several_pages_for_one_niche, :good, _finding),
    do: sentences("No topic is split over several pages.", "Each topic your pages cover has one page about it.")

  defp advice(:pages_answering_no_phrase, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "matches", "match")} none of the topics in this research.",
        "#{agree(count, "This page isn't", "These pages aren't")} about any topic I found for this research, and #{agree(count, "it doesn't", "they don't")} show up on Google for any of the searches I checked. #{agree(count, "It", "They")} may still serve another purpose, such as helping visitors already on your site.",
        "If #{agree(count, "it", "they")} should bring visits from Google, make #{agree(count, "it", "them")} about something people search for."
      )

  defp advice(:pages_answering_no_phrase, :good, _finding),
    do:
      sentences(
        "Every page matches a topic or a search.",
        "Each page is about a topic in this research or shows up on Google for a search I checked."
      )

  defp advice(:close_to_first_page, :warning, %{figures: figures}) do
    phrase_count = count(figures[:phrase_count])

    sentences(
      "#{capitalised(counted(phrase_count, @phrase_forms))} #{agree(phrase_count, "has", "have")} you just past Google's first page.",
      "For #{agree(phrase_count, "this search", "these searches")} your site is at position 11 to 20, on Google's second page, where few people look. Improving the page that shows up is the usual way to move up, though nothing guarantees it.",
      "Make that page more useful to the people who type #{agree(phrase_count, "it", "those searches")}. Add text about what they want, give it a clear title and link to it from your other pages."
    )
  end

  defp advice(:speed, :not_checked, %{figures: figures}),
    do: sentences("I didn't check how fast your site is on a phone.", speed_reason(figures[:reason]))

  defp advice(:performance_score, level, %{figures: figures}) do
    score = score_text(figures[:score])

    case level do
      :problem ->
        sentences(
          "Your home page is slow on a phone.",
          "Google's test scored it #{score} out of 100 (measured by Google's test). Below 50 is slow: many visitors leave before it loads.",
          "Ask #{@who_runs_the_site} to make images smaller, remove scripts you don't use and check the hosting is fast enough."
        )

      :warning ->
        sentences(
          "Your home page could be faster on a phone.",
          "Google's test scored it #{score} out of 100 (measured by Google's test). 90 or more counts as fast.",
          "Ask #{@who_runs_the_site} to make images smaller and remove scripts you don't use."
        )

      :good ->
        sentences(
          "Your home page is fast on a phone.",
          "Google's test scored it #{score} out of 100 (measured by Google's test)."
        )
    end
  end

  defp advice(:largest_contentful_paint, level, %{figures: figures}) do
    shown = "Its main content shows after #{seconds_text(figures[:milliseconds])} (#{source(figures[:source])})."

    case level do
      :problem ->
        sentences(
          "The main content of your home page takes long to show on a phone.",
          "#{shown} Under 2.5 seconds is good; after 4 many visitors give up.",
          "Make the biggest image or block at the top lighter, and ask #{@who_runs_the_site} to load it first."
        )

      :warning ->
        sentences(
          "The main content of your home page shows a bit slowly on a phone.",
          "#{shown} Under 2.5 seconds is good.",
          "Make the biggest image or block at the top lighter."
        )

      :good ->
        sentences("The main content of your home page shows quickly on a phone.", shown)
    end
  end

  defp advice(:interaction_to_next_paint, level, %{figures: figures}) do
    reacts = "It takes #{milliseconds_text(figures[:milliseconds])} to react to a tap (#{source(figures[:source])})."

    case level do
      :problem ->
        sentences(
          "Your home page is slow to react to a tap.",
          "#{reacts} Under 200 milliseconds feels instant; over 500 feels broken.",
          "Ask #{@who_runs_the_site} to cut heavy scripts (chat widgets, trackers, sliders) that keep the phone busy."
        )

      :warning ->
        sentences(
          "Your home page reacts to taps a bit slowly.",
          "#{reacts} Under 200 milliseconds feels instant.",
          "Ask #{@who_runs_the_site} to cut scripts you don't need."
        )

      :good ->
        sentences("Your home page reacts quickly to taps.", reacts)
    end
  end

  defp advice(:cumulative_layout_shift, level, %{figures: figures}) do
    moves =
      "Its layout shift score (how much things move while it loads) is #{shift_text(figures[:value])} (#{source(figures[:source])}); under 0.1 is good."

    case level do
      :problem ->
        sentences(
          "Your home page jumps around while it loads.",
          "#{moves} When things move, people tap the wrong thing.",
          "Ask #{@who_runs_the_site} to reserve space for images, ads and banners so nothing moves."
        )

      :warning ->
        sentences(
          "Your home page moves a little while it loads.",
          moves,
          "Ask #{@who_runs_the_site} to reserve space for images and banners."
        )

      :good ->
        sentences("Your home page stays still while it loads.", moves)
    end
  end

  defp advice(:phone_usability, :warning, %{figures: %{check_id: check_id}})
       when check_id in ["viewport-insight", "meta-viewport"],
       do:
         sentences(
           "Your home page isn't set up for phone screens.",
           "Google's test found no #{@viewport_explained}, so phones show a shrunken desktop page.",
           "Ask #{@who_runs_the_site} to add the viewport setting."
         )

  defp advice(:phone_usability, :warning, %{figures: %{check_id: "target-size"}}),
    do:
      sentences(
        "Buttons and links on your home page are hard to tap.",
        "Google's test found buttons or links too small, or too close together, to hit with a finger.",
        "Make them bigger and put more space between them."
      )

  defp advice(:phone_usability, :warning, _finding),
    do:
      sentences(
        "Google's phone test found a problem on your home page.",
        "One of its checks of how the page works on a phone failed.",
        "Ask #{@who_runs_the_site} to run Google's PageSpeed Insights on the home page and fix what it flags."
      )

  defp advice(:phone_usability, :good, _finding),
    do:
      sentences(
        "Your home page passed Google's phone checks.",
        "Google's test checked that it fits a phone's screen and that buttons are easy to tap."
      )

  defp advice(:viewport, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "is", "are")} not set up for phone screens.",
        "#{agree(count, "It has", "They have")} no #{@viewport_explained}, so phones show #{agree(count, "it", "them")} shrunken.",
        "Ask #{@who_runs_the_site} to add the viewport setting to every page."
      )

  defp advice(:viewport, :good, _finding),
    do: sentences("Every page is set up for phone screens.", "Each page fits the width of a phone.")

  defp advice(:ways_to_act, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "gives", "give")} the visitor no next step.",
        "#{agree(count, "It has", "They have")} no phone link, e-mail link, form or button, so someone who likes what they read has to go looking for how to reach you.",
        "Add a clear next step to #{agree(count, "it", "each")}: a “Call us” button, a form or a link to your contact page."
      )

  defp advice(:ways_to_act, :good, _finding),
    do:
      sentences(
        "Every page gives the visitor a next step.",
        "Each page has a phone link, an e-mail link, a form or a button."
      )

  defp advice(:tappable_contact, :warning, _finding),
    do:
      sentences(
        "No page has a phone or e-mail link a visitor can tap.",
        "I looked for links that start a call or an e-mail with one tap and found none. On a phone, people then have to copy your number by hand, and many won't.",
        "Make your phone number and e-mail address into links on every page, for example in the header or footer."
      )

  defp advice(:tappable_contact, :good, %{figures: figures}),
    do:
      sentences(
        "Visitors can call or write to you with one tap.",
        "I found #{counted(count(figures[:phone_count]), @number_forms)} and #{counted(count(figures[:email_count]), @address_forms)} as links on your pages."
      )

  defp advice(:address_in_structured_data, :warning, _finding),
    do:
      sentences(
        "Your address isn't in your pages' structured data.",
        "#{@structured_data_explained} let Google show your business correctly. I didn't check addresses written as plain text.",
        "Ask #{@who_runs_the_site} to add your business name, address and phone as structured data for a local business."
      )

  defp advice(:address_in_structured_data, :good, _finding),
    do:
      sentences(
        "Your address is in your pages' structured data.",
        "#{@structured_data_explained} help Google show where your business is."
      )

  defp advice(:phone_numbers, :warning, %{figures: figures}),
    do:
      sentences(
        "Your pages show #{counted(count(figures[:phone_count]), %{one: "phone number", other: "different phone numbers"})}.",
        "Google trusts a business more when its number is the same everywhere. Several can be right, say for two offices, but check none is out of date#{named(strings(figures[:phones]))}.",
        "Remove old numbers and use the same main number on every page and on your Google Business Profile."
      )

  defp advice(:phone_numbers, :good, _finding),
    do:
      sentences(
        "Your pages use one phone number.",
        "The same number everywhere helps Google trust your business details."
      )

  defp advice(:structured_data, :warning, _finding),
    do:
      sentences(
        "Your pages have no structured data.",
        "#{@structured_data_explained} help Google understand your business, and can make your results stand out.",
        "Ask #{@who_runs_the_site} to add structured data for your business and your services."
      )

  defp advice(:structured_data, :good, %{figures: figures}),
    do:
      sentences(
        "Your pages have structured data.",
        "#{@structured_data_explained} help Google understand your business.#{structured_data_kinds(strings(figures[:types]))}"
      )

  defp advice(:language_declared, :warning, %{count: count}),
    do:
      sentences(
        "#{capitalised(pages(count))} #{agree(count, "does", "do")} not say which language #{agree(count, "it is", "they are")} in.",
        "The language tag (a line in the page code naming its language) helps Google show a page to people who speak it.",
        "Ask #{@who_runs_the_site} to set the page language on every page."
      )

  defp advice(:language_declared, :good, _finding),
    do:
      sentences("Every page says which language it is in.", "Google can show each page to people who speak its language.")

  defp advice(:declared_languages, :good, %{figures: figures}),
    do:
      sentences(
        "Your pages say they are in: #{figures[:languages] |> strings() |> Enum.join(", ")}.",
        "This is the language code your pages give Google. Check that it matches the language they are written in."
      )

  defp advice(:business_profile, :good, %{figures: figures}),
    do:
      sentences(
        "Your Google Business Profile links to your site.",
        "I found #{profile_name(figures)} on Google#{rating(figures)}, and its website link points here. A Business Profile is your free listing on Google Maps and in search."
      )

  defp advice(:business_profile, :warning, %{figures: %{found: true} = figures}),
    do:
      sentences(
        "Your Google Business Profile doesn't link to your site.",
        "I found #{profile_name(figures)} on Google#{rating(figures)}, but its website link is empty or points elsewhere.",
        "Open your profile at business.google.com and set its website to this site's address."
      )

  defp advice(:business_profile, :warning, %{figures: figures}),
    do:
      sentences(
        "I couldn't find a Google Business Profile for #{looked_up_name(figures[:name])}.",
        "A Business Profile (your free listing on Google Maps and in search) is often the first thing local customers see. Yours may exist under another name.",
        "If you have none, create one at business.google.com; if you have one, check its name matches your site."
      )

  defp advice(:business_profile, :not_checked, %{figures: figures}),
    do: sentences("I didn't look for your Google Business Profile.", profile_reason(figures[:reason]))

  defp advice(:linking_sites, :good, %{figures: figures}) do
    count = count(figures[:count])

    sentences(
      "#{capitalised(counted(count, @linking_site_forms))} #{agree(count, "links", "link")} to yours.",
      "#{@why_links_count} #{@approximate_links}"
    )
  end

  defp advice(:linking_sites, :warning, _finding),
    do:
      sentences(
        "No other site links to yours yet.",
        "#{@why_links_count} The count comes from a third-party index of links, which may miss a few.",
        "Ask the businesses you work with, and the local directories and associations you belong to, to link to your site."
      )

  defp advice(:linking_sites, :not_checked, %{figures: figures}),
    do: sentences("I don't know how many other sites link to yours.", linking_sites_reason(figures[:reason]))

  defp sentences(title, meaning, action \\ nil), do: %{title: title, meaning: meaning, action: action}

  defp not_checked_reason("not_configured", what), do: "The service I use to look up #{what} isn't connected here."

  defp not_checked_reason("not_in_demo_data", what),
    do: "This research runs on test data, so I don't show an invented figure for #{what}."

  defp not_checked_reason(_failed, what), do: "I asked for #{what}, but the request failed. #{@next_research}"

  defp matching_reason("not_ready"),
    do: "I'll do it once I've read your site and finished putting the searches into topics."

  defp matching_reason("not_in_demo_data"),
    do: "This research runs on test data, so I don't present an invented match between your pages and topics."

  defp matching_reason("not_configured"), do: "The AI service I use to match pages to topics isn't connected here."
  defp matching_reason(_failed), do: "I tried to match your pages to the topics, but it failed."

  defp speed_reason("not_configured"), do: "Phone speed wasn't checked: Google's speed test isn't connected here."

  defp speed_reason("quota"), do: "Google's speed test was busy and turned me away. #{@next_research}"

  defp speed_reason("page_unreachable"), do: "Google's speed test couldn't open your home page."
  defp speed_reason(_failed), do: "Google's speed test failed. #{@next_research}"

  defp profile_reason("no_business_name"),
    do:
      "Your site's structured data (labels in the page code that tell Google your name, address and prices) doesn't name the business, so I didn't know what to look for."

  defp profile_reason("unavailable"), do: "Google's business listings can't be searched for your area."
  defp profile_reason(reason), do: not_checked_reason(reason, "your Business Profile")

  defp linking_sites_reason("no_data"),
    do:
      "The third-party index of links I use has no figure for your site yet. Small and new sites are often missing from it."

  defp linking_sites_reason("unavailable"),
    do: "The service I use to count links from other sites turned the request away."

  defp linking_sites_reason(reason), do: not_checked_reason(reason, "the number of sites that link to yours")

  defp pages(count), do: counted(count, @page_forms)

  defp counted(count, forms) when is_integer(count) and count >= 0,
    do: "#{Format.integer(count)} #{Format.plural(count, forms)}"

  defp counted(_unknown, %{other: other}), do: "some #{other}"

  defp count(value) when is_integer(value) and value >= 0, do: value
  defp count(_not_a_count), do: nil

  defp capitalised(text), do: String.capitalize(String.first(text)) <> String.slice(text, 1..-1//1)

  defp on_purpose(count), do: "If you hid #{agree(count, "it", "them")} on purpose, that's fine."

  defp agree(1, one, _other), do: one
  defp agree(_count, _one, other), do: other

  defp strings(list) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp strings(_not_a_list), do: []

  defp niche_names(niches) when is_list(niches), do: for(%{name: name} when is_binary(name) <- niches, do: name)
  defp niche_names(_not_a_list), do: []

  defp named([]), do: ""

  defp named(names) do
    {shown, rest} = Enum.split(names, @names_shown)
    more = if rest == [], do: "", else: " and #{Format.integer(length(rest))} more"
    ": " <> Enum.map_join(shown, ", ", &"“#{&1}”") <> more
  end

  defp listed_addresses(addresses) do
    case strings(addresses) do
      [] -> ""
      addresses -> "I opened #{Enum.join(addresses, " and ")}. "
    end
  end

  defp indexed_compared(indexed, read) when is_integer(indexed) and is_integer(read) and indexed > 2 * read,
    do:
      "Google knows more pages of your site than I read: your site may be larger than what I read, or Google may still keep old pages. Its count is rough."

  defp indexed_compared(_indexed, _read), do: "Google's count is rough, but it isn't far from that."

  defp split_niches([]), do: "Some topics have more than one page"

  defp split_niches(names),
    do: "#{counted(length(names), @niche_forms)} #{agree(length(names), "has", "have")} more than one page"

  defp structured_data_kinds([]), do: ""
  defp structured_data_kinds(types), do: " I found these kinds#{named(types)}."

  defp status_note(status) when is_integer(status), do: " (code #{status})"
  defp status_note(_none), do: ""

  defp sitemap_count(count) when is_integer(count) and count > 0, do: " Yours lists #{pages(count)}."
  defp sitemap_count(_none), do: ""

  defp links_checked_sentence(nil), do: "Every link between your pages that I checked opened a page."

  defp links_checked_sentence(checked),
    do: "I checked #{counted(checked, @link_forms)} between your pages, and each opened a page."

  defp images_lacking(figures) do
    case {count(figures[:without_description]), count(figures[:images])} do
      {nil, _images} -> "Some images"
      {lacking, nil} -> capitalised(counted(lacking, @image_forms))
      {lacking, images} -> "#{Format.integer(lacking)} of #{counted(images, @image_forms)}"
    end
  end

  defp score_text(score) when is_number(score), do: Format.integer(round(score))
  defp score_text(_none), do: "an unknown score"

  defp seconds_text(milliseconds) when is_number(milliseconds),
    do: "#{milliseconds |> Kernel./(1_000) |> Decimal.from_float() |> Format.decimal(1)} seconds"

  defp seconds_text(_none), do: "an unknown time"

  defp milliseconds_text(milliseconds) when is_number(milliseconds),
    do: "#{Format.integer(round(milliseconds))} milliseconds"

  defp milliseconds_text(_none), do: "an unknown time"

  defp shift_text(value) when is_number(value), do: value |> Kernel.*(1.0) |> Decimal.from_float() |> Format.decimal(2)
  defp shift_text(_none), do: "unknown"

  defp source(source), do: Map.get(@sources, source, "measured by Google")

  defp profile_name(%{title: title}) when is_binary(title), do: "“#{title}”"
  defp profile_name(figures), do: looked_up_name(figures[:name])

  defp looked_up_name(name) when is_binary(name), do: "“#{name}”"
  defp looked_up_name(_none), do: "your business"

  defp rating(%{rating: rating, votes: votes}) when is_number(rating) and is_integer(votes) and votes > 0,
    do:
      ", rated #{rating |> Kernel.*(1.0) |> Decimal.from_float() |> Format.decimal(1)} from #{counted(votes, %{one: "review", other: "reviews"})}"

  defp rating(_figures), do: ""
end
