defmodule DirmoonWeb.Controllers.Page.HomeTest do
  use DirmoonWeb.ConnCase, async: true

  @free_promise ~r/\b(free|trials?|no card|no credit card|without a card|credits?)\b/i

  test "a signed-out visitor sees the landing page on the dotted page with the nav card", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("[data-layout=landing].page-dots") |> Enum.count() == 1
    assert document |> LazyHTML.query("#landing-nav [data-part=brand]") |> Enum.count() == 1
  end

  test "the hero headline says to validate a business idea before building, with the lime underline",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    headline = LazyHTML.query(document, "#landing-hero h1")

    assert squish(headline) == "Validate your business idea before you build it."

    assert headline |> LazyHTML.query("[data-part=underline] svg[data-part=stroke] path.stroke-accent") |> Enum.count() ==
             1

    assert headline |> LazyHTML.query("[data-part=underline] svg[data-part=rocket]") |> Enum.count() == 1
  end

  test "the hero sign-up form has a labelled email input and a Create account button", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    form = LazyHTML.query(document, "#landing-hero form#sign-up-form-hero[action='/sign-up'][method=post]")
    [email_input_id] = form |> LazyHTML.query("input[type=email][name='user[email]']") |> LazyHTML.attribute("id")

    assert form |> LazyHTML.query("label.sr-only[for='#{email_input_id}']") |> squish() != ""
    assert form |> LazyHTML.query("button[type=submit]") |> squish() == "Create account"
  end

  test "the closing band has a second sign-up form", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    form = LazyHTML.query(document, "form#sign-up-form-closing[action='/sign-up']")
    [email_input_id] = form |> LazyHTML.query("input[type=email][name='user[email]']") |> LazyHTML.attribute("id")

    assert form |> LazyHTML.query("label.sr-only[for='#{email_input_id}']") |> squish() != ""
    assert form |> LazyHTML.query("button[type=submit]") |> squish() == "Create account"
  end

  test "the page is in English, with an English title", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("html") |> LazyHTML.attribute("lang") == ["en"]

    assert document |> LazyHTML.query("title") |> squish() ==
             "Validate your business idea with Google search data · dirmoon"

    for phrase <- ["niche finder", "monthly search volume", "keyword competition"] do
      assert document |> LazyHTML.query("#journey-lead") |> squish() =~ phrase
    end
  end

  test "the hero lead says what dirmoon does in two short sentences", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-hero #hero-lead") |> squish() ==
             "Describe your idea in one sentence. dirmoon checks what people really search for on Google and tells you, in plain words, if it's worth building."
  end

  test "the description offers both testing an idea and a list of what to fix on an existing website, within 160 characters",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert [description] = document |> LazyHTML.query("meta[name=description]") |> LazyHTML.attribute("content")

    assert description ==
             "Niche finder: test a business idea with real monthly search volume and keyword competition. " <>
               "Or paste your site and get a plain-English list of what to fix."

    assert String.length(description) <= 160
  end

  test "the description keeps the search terms people use for this kind of tool", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert [description] = document |> LazyHTML.query("meta[name=description]") |> LazyHTML.attribute("content")

    for phrase <- ["niche finder", "monthly search volume", "keyword competition"] do
      assert String.downcase(description) =~ phrase
    end
  end

  test "the page names its one address and may be listed by search engines", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("link[rel=canonical]") |> LazyHTML.attribute("href") ==
             [DirmoonWeb.Endpoint.url() <> "/"]

    assert document |> LazyHTML.query("meta[name=robots]") |> Enum.count() == 0
  end

  test "a shared link shows the page's title, description and the sharing image", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    property = fn name -> document |> LazyHTML.query("meta[property='#{name}']") |> LazyHTML.attribute("content") end

    assert property.("og:type") == ["website"]
    assert property.("og:site_name") == ["dirmoon"]
    assert property.("og:url") == [DirmoonWeb.Endpoint.url() <> "/"]
    assert property.("og:title") == ["Validate your business idea with Google search data"]

    assert property.("og:description") ==
             document |> LazyHTML.query("meta[name=description]") |> LazyHTML.attribute("content")

    assert property.("og:image:alt") == ["dirmoon: validate your business idea before you build it."]
    assert [image_url] = property.("og:image")
    assert String.starts_with?(image_url, DirmoonWeb.Endpoint.url() <> "/images/og")

    assert document |> LazyHTML.query("meta[name='twitter:card']") |> LazyHTML.attribute("content") ==
             ["summary_large_image"]
  end

  test "the sharing image the page names is served as a 1200 by 630 PNG", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    [image_url] = document |> LazyHTML.query("meta[property='og:image']") |> LazyHTML.attribute("content")

    image = get(conn, URI.parse(image_url).path)

    assert image.status == 200
    assert get_resp_header(image, "content-type") == ["image/png"]
    assert <<_signature::binary-size(16), 1200::32, 630::32, _rest::binary>> = image.resp_body
  end

  test "the structured data names the site and who runs it, and nothing the page doesn't say", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    home = DirmoonWeb.Endpoint.url() <> "/"

    assert [json] = document |> LazyHTML.query("script[type='application/ld+json']") |> Enum.map(&LazyHTML.text/1)
    assert %{"@context" => "https://schema.org", "@graph" => [website, organization]} = Jason.decode!(json)

    assert [description] = document |> LazyHTML.query("meta[name=description]") |> LazyHTML.attribute("content")

    assert website == %{
             "@type" => "WebSite",
             "@id" => home <> "#website",
             "url" => home,
             "name" => "dirmoon",
             "description" => description,
             "inLanguage" => "en",
             "publisher" => %{"@id" => home <> "#organization"}
           }

    assert %{"@type" => "Organization", "@id" => organization_id, "name" => "dirmoon", "url" => ^home, "logo" => logo} =
             organization

    assert organization_id == home <> "#organization"
    assert Map.keys(organization) == ["@id", "@type", "logo", "name", "url"]
    assert conn |> get(URI.parse(logo).path) |> response(200)
  end

  test "the hero holds only the headline, the lead and the sign-up form: no line about an existing website, no note under the form",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-hero p") |> LazyHTML.attribute("id") == ["hero-lead"]
    assert document |> LazyHTML.query("#landing-hero a[href='#existing-site']") |> Enum.count() == 0
    assert document |> LazyHTML.query("form[action='/sign-up'] p") |> Enum.count() == 0
    assert document |> LazyHTML.query("section#existing-site") |> Enum.count() == 1
  end

  test "the section for an existing website comes after the journey, then pricing, then the closing band",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("main > section") |> LazyHTML.attribute("id") ==
             ~w(landing-hero journey existing-site pricing closing)
  end

  test "the pricing section has an eyebrow and a heading, then the two ways to pay", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    section = LazyHTML.query(document, "section#pricing")

    assert section |> LazyHTML.query("#pricing-heading") |> squish() ==
             "Pricing One research to try it, or a monthly plan."

    assert section |> LazyHTML.query("h2") |> squish() == "One research to try it, or a monthly plan."

    assert section |> LazyHTML.query("#pricing-options > article") |> LazyHTML.attribute("id") ==
             ~w(pricing-single-research pricing-monthly-plan)
  end

  test "the one research card shows the configured single price, paid once, and that it never expires",
       %{conn: conn} do
    offer = Dirmoon.Billing.offer()
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    card = LazyHTML.query(document, "#pricing-single-research")

    assert card |> LazyHTML.query("h3") |> squish() == "One research"
    assert card |> LazyHTML.query("#pricing-single-research-price") |> squish() == "$#{offer.single_price}"
    assert card |> LazyHTML.query("[data-part=price-note]") |> squish() == "paid once"

    assert card |> LazyHTML.query("[data-part=details]") |> squish() ==
             "One research, to try dirmoon. It never expires."
  end

  test "the monthly plan card shows the configured monthly price and number of researches a month, which don't carry over",
       %{conn: conn} do
    offer = Dirmoon.Billing.offer()
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    card = LazyHTML.query(document, "#pricing-monthly-plan")

    assert card |> LazyHTML.query("h3") |> squish() == "Monthly plan"
    assert card |> LazyHTML.query("#pricing-monthly-plan-price") |> squish() == "$#{offer.monthly_price}"
    assert card |> LazyHTML.query("[data-part=price-note]") |> squish() == "a month"

    assert card |> LazyHTML.query("[data-part=details]") |> squish() ==
             "#{offer.monthly_researches} researches a month. Researches you don't use in a month don't carry over."
  end

  test "both pricing cards say what a research includes, with the configured numbers of briefs and price checks",
       %{conn: conn} do
    offer = Dirmoon.Billing.offer()
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    for card_id <- ~w(pricing-single-research pricing-monthly-plan) do
      card = LazyHTML.query(document, "##{card_id}")

      assert card |> LazyHTML.query("[data-part=includes-lead]") |> squish() == "Each research includes:"

      assert card |> LazyHTML.query("##{card_id}-includes li") |> Enum.map(&squish/1) == [
               "Up to #{offer.briefs_per_research} briefs: the plan and the text for one page each",
               "Up to #{offer.price_checks_per_research} competitor price checks",
               "For an existing site, a scan of your site"
             ]
    end
  end

  test "each pricing card's dark button leads to the closing sign-up form, which stays the page's one primary action",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#pricing-single-research a#pricing-single-research-sign-up") |> squish() ==
             "Create account"

    assert document |> LazyHTML.query("#pricing-monthly-plan a#pricing-monthly-plan-sign-up") |> squish() ==
             "Create account"

    assert document
           |> LazyHTML.query("#pricing-single-research-sign-up, #pricing-monthly-plan-sign-up")
           |> LazyHTML.attribute("href") == ["#closing", "#closing"]

    assert document
           |> LazyHTML.query("#pricing-single-research-sign-up, #pricing-monthly-plan-sign-up")
           |> LazyHTML.attribute("data-variant") == ["dark", "dark"]

    assert document |> LazyHTML.query("main [data-variant=lime]") |> Enum.count() == 0

    assert document |> LazyHTML.query("section#closing form#sign-up-form-closing") |> Enum.count() == 1
  end

  test "under the pricing cards one line says you create an account with your email, then pay on Stripe's page",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#pricing #pricing-how-to-pay") |> squish() ==
             "You create an account with your email, then pay on Stripe's secure page."
  end

  test "the nav offers a Pricing link to the pricing section next to Sign in", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-nav nav a") |> LazyHTML.attribute("id") ==
             ~w(pricing-link sign-in-link)

    assert document |> LazyHTML.query("#landing-nav a#pricing-link[href='#pricing']") |> squish() == "Pricing"
    assert document |> LazyHTML.query("#landing-nav a#pricing-link[data-variant]") |> Enum.count() == 0
  end

  test "nothing on the landing page promises anything free, a trial or no card", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    meta_texts =
      document
      |> LazyHTML.query("title, meta[name=description], meta[property^='og:'], meta[name^='twitter:']")
      |> Enum.flat_map(&[LazyHTML.text(&1) | LazyHTML.attribute(&1, "content")])

    page_text = Enum.join([squish(LazyHTML.query(document, "body")) | meta_texts], " ")

    assert "Try it free" =~ @free_promise
    refute "A freelancer's freedom" =~ @free_promise
    refute page_text =~ @free_promise
  end

  test "the section for an existing website promises a plain-English list of what to fix from up to the scan's page limit",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    section = LazyHTML.query(document, "#existing-site")

    assert section |> LazyHTML.query("#existing-site-heading") |> squish() ==
             "Already have a website? Paste your address. Get a list of what to fix."

    assert section |> LazyHTML.query("h2") |> squish() == "Paste your address. Get a list of what to fix."

    assert section |> LazyHTML.query("[data-part=intro]") |> squish() ==
             "dirmoon reads up to #{Dirmoon.SiteScans.page_limit()} pages of your site and tells you in plain words what to fix first."
  end

  test "the section says plainly what the report tells you, in the report's order", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    section = LazyHTML.query(document, "#existing-site")

    assert section |> LazyHTML.query("[data-part=findings-lead]") |> squish() == "It tells you:"

    assert section |> LazyHTML.query("#existing-site-findings [data-part=finding]") |> Enum.map(&squish/1) == [
             "Which topics people search for that your site has no page for",
             "Whether Google can find and read your pages",
             "Whether each page says clearly what it offers",
             "Whether it loads fast and works on a phone",
             "Whether Google can see you are a real business"
           ]

    assert section |> LazyHTML.query("h3, [data-part=level], [data-part=examples-label]") |> Enum.count() == 0
  end

  test "nothing the section says about an existing website carries a number", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    findings = document |> LazyHTML.query("#existing-site [data-part=finding]") |> Enum.map(&squish/1)

    assert Enum.count(findings) == 5
    assert Enum.reject(findings, &(&1 =~ ~r/\d/)) == findings
  end

  test "the section says what comes next: a brief for a missing topic and your page beside your competitors'",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#existing-site-next") |> squish() ==
             "A topic with no page? Ask for its brief: the plan and the text for that page. " <>
               "dirmoon also sets your page beside your competitors' pages."
  end

  test "the page asks no questions about an existing website and nowhere names the keyword API's vendor",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#existing-site-answers, #existing-site-report-panel") |> Enum.count() == 0
    refute document |> LazyHTML.query("main") |> squish() =~ "DataForSEO"
  end

  test "the lead under the steps' heading explains its search terms in plain words as it goes", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
    lead = document |> LazyHTML.query("#journey-lead") |> squish()

    assert lead =~ "the monthly search volume (how often people search)"
    assert lead =~ "the keyword competition (who holds Google's first page)"
    assert lead =~ "then tells you which topics are worth going after."
  end

  test "the journey asks whether to start the business", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    journey = LazyHTML.query(document, "#journey")

    assert journey |> LazyHTML.query("h2.sr-only") |> squish() == "Should I start this business?"
    refute squish(journey) =~ "From idea to decision"
    assert journey |> LazyHTML.query("#journey-intro") |> Enum.count() == 0
    assert document |> LazyHTML.query("#how-it-works") |> Enum.count() == 0
  end

  test "the journey is one trip of six numbered stops, from the launch to the arrival", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    journey = LazyHTML.query(document, "#journey #journey-steps")

    assert journey |> LazyHTML.query("[data-part=step]") |> LazyHTML.attribute("id") ==
             ~w(journey-steps-launch journey-steps-demand journey-steps-click-price journey-steps-competition journey-steps-competitor-prices journey-steps-arrival)

    assert journey |> LazyHTML.query("[data-part=step] [data-part=number]") |> Enum.map(&squish/1) ==
             ~w(01 02 03 04 05 06)

    assert journey |> LazyHTML.query("[data-part=step] h3") |> Enum.map(&squish/1) == [
             "How do I validate my business idea?",
             "How do I know if people are searching for my business idea?",
             "What would a Google Ads click cost for my idea?",
             "Who is on the first page of Google, and is the competition too strong?",
             "What do my competitors charge?",
             "What are my chances of a successful business?"
           ]

    assert journey |> LazyHTML.query("[data-part=label]") |> Enum.count() == 0
  end

  test "a dotted path passes a plain numbered marker at every stop, with no rocket, pad or flag",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    journey = LazyHTML.query(document, "#journey-steps")

    assert journey |> LazyHTML.query("[data-part=flight-path][aria-hidden=true]") |> Enum.count() == 1
    assert journey |> LazyHTML.query("svg[data-rocket]") |> Enum.count() == 0

    assert journey |> LazyHTML.query("[data-part=step] [data-part=marker]") |> LazyHTML.attribute("data-marker") ==
             ~w(launch question question question question arrival)

    assert journey |> LazyHTML.query("[data-part=marker] .hero-flag-solid") |> Enum.count() == 0
  end

  test "each of the traveller's questions is answered at its stop with the real example", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    answers =
      Enum.map(
        ~w(demand click-price competition competitor-prices),
        &(document |> LazyHTML.query("#journey-steps-#{&1} [data-part=lead]") |> squish())
      )

    assert answers == [
             "dirmoon shows how many times a month people type it into Google. In the example, people look for skate rental 1,090 times a month: about 36 times a day.",
             "dirmoon shows what businesses pay Google for one ad click. For skate rental it is $6.79. A high price means a customer is worth money.",
             "dirmoon lists every site on Google's first page and tells you how hard it is to get there. For skate rental: businesses like yours and big portals, so it will be a fight.",
             "Ask, and dirmoon opens your competitors' pages and lists the prices they publish, each with a link."
           ]

    assert document |> LazyHTML.query("#journey-steps-demand [data-part=lead] strong") |> Enum.map(&squish/1) ==
             ["1,090 times a month"]

    assert document |> LazyHTML.query("#journey-steps-click-price [data-part=lead] strong") |> squish() == "$6.79"
  end

  test "each question appears exactly once on the page", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    main = document |> LazyHTML.query("main") |> squish()

    for question <- [
          "How do I know if people are searching for my business idea?",
          "What would a Google Ads click cost for my idea?",
          "Who is on the first page of Google, and is the competition too strong?",
          "What do my competitors charge?"
        ] do
      assert main |> String.split(question) |> Enum.count() == 2
    end

    assert document |> LazyHTML.query("#journey dl, #journey [data-part=questions]") |> Enum.count() == 0
  end

  test "the journey no longer has a step about dirmoon checking real search data", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    journey = document |> LazyHTML.query("#journey") |> squish()

    refute journey =~ "dirmoon checks real search data"
    refute journey =~ "It does not guess"
    refute journey =~ "AI only suggests where to look"
    refute journey =~ "API fees"
    assert document |> LazyHTML.query("#journey-steps-research, #journey-steps-sources") |> Enum.count() == 0
  end

  test "the trip launches from the idea described in one sentence", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    launch = LazyHTML.query(document, "#journey-steps-launch")

    assert launch |> LazyHTML.query("[data-part=lead]") |> squish() ==
             "Describe it in one sentence. dirmoon checks it against what people really search for on Google."

    assert launch |> LazyHTML.query("blockquote") |> Enum.count() == 0
  end

  test "the last step answers with a score, a plain verdict and one real example, without a report mock-up",
       %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    arrival = LazyHTML.query(document, "#journey-steps-arrival")

    assert arrival |> LazyHTML.query("[data-part=lead]") |> squish() ==
             "dirmoon gives your idea a score from 0 to 10 and a plain verdict: worth a try, worth it but hard, " <>
               "or probably not worth it. Skate rental scored 7.7 out of 10: worth it, but hard."

    assert arrival |> LazyHTML.query("[data-part=decision]") |> Enum.map(&squish/1) == [
             "Then dirmoon writes the plan and the text for your page, ready to hand to whoever builds your site."
           ]

    assert document |> LazyHTML.query("#journey [data-surface=dark], #journey figure") |> Enum.count() == 0
  end

  test "a signed-out visitor is offered sign-in in the nav", %{conn: conn} do
    document = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#landing-nav a#sign-in-link[data-variant=dark][href='/users/log-in']") |> squish() ==
             "Sign in"

    assert document |> LazyHTML.query("#landing-nav a[href='/app']") |> Enum.count() == 0
  end

  test "a signed-in user opening the landing page is redirected to the app", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = get(conn, ~p"/")

    assert redirected_to(conn) == ~p"/app"
  end

  test "after logging out the landing page shows no notice", %{conn: conn} do
    %{conn: conn} = sign_up_and_log_in_user(%{conn: conn})

    conn = delete(conn, ~p"/users/log-out")

    document = conn |> recycle() |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert document |> LazyHTML.query("#flash-group, [role=alert]") |> Enum.count() == 0
  end

  defp squish(node) do
    node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end
end
