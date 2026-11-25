defmodule DirmoonWeb.Router do
  use DirmoonWeb, :router

  import DirmoonWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DirmoonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  scope "/", DirmoonWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/", PageController, :home
    post "/sign-up", SignUpController, :create
  end

  scope "/app", DirmoonWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/", AppController, :index
    get "/search-console/connect", SearchConsoleController, :connect
    get "/search-console/callback", SearchConsoleController, :callback
    delete "/search-console", SearchConsoleController, :delete

    live_session :app,
      on_mount: [{DirmoonWeb.UserAuth, :require_authenticated}, {DirmoonWeb.Layouts, :app_body}] do
      live "/research/new", NewResearchLive
      live "/runs", RunsLive
      live "/runs/:id", RunLive
      live "/runs/:id/results", ResultsLive
      live "/pages", PagesLive
      live "/pages/:id", PageLive
    end
  end

  scope "/", DirmoonWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{DirmoonWeb.UserAuth, :require_authenticated}, {DirmoonWeb.Layouts, :app_body}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", DirmoonWeb do
    pipe_through [:browser]

    live_session :current_user, on_mount: [{DirmoonWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:dirmoon, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DirmoonWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
