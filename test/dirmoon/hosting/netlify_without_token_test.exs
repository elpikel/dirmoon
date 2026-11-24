defmodule Dirmoon.Hosting.NetlifyWithoutTokenTest do
  use ExUnit.Case, async: false

  alias Dirmoon.Hosting.Netlify

  test "creating a site without a configured token fails as not configured and sends nothing" do
    configured = Application.fetch_env!(:dirmoon, Netlify)
    Application.put_env(:dirmoon, Netlify, Keyword.delete(configured, :token))
    on_exit(fn -> Application.put_env(:dirmoon, Netlify, configured) end)

    Req.Test.stub(Netlify, fn conn -> flunk("unexpected request to #{conn.request_path}") end)

    assert Netlify.create_site(%{site_name: "dirmoon-strona"}) == {:error, :hosting_not_configured}
  end

  test "deploying with an empty token fails as not configured and sends nothing" do
    configured = Application.fetch_env!(:dirmoon, Netlify)
    Application.put_env(:dirmoon, Netlify, Keyword.put(configured, :token, ""))
    on_exit(fn -> Application.put_env(:dirmoon, Netlify, configured) end)

    Req.Test.stub(Netlify, fn conn -> flunk("unexpected request to #{conn.request_path}") end)

    assert Netlify.deploy(%{site_id: "site-without-token", html: "<html></html>"}) ==
             {:error, :hosting_not_configured}
  end
end
