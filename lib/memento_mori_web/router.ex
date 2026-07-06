defmodule MementoMoriWeb.Router do
  use MementoMoriWeb, :router

  import MementoMoriWeb.OwnerAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MementoMoriWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_owner
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MementoMoriWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", MementoMoriWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:memento_mori, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MementoMoriWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", MementoMoriWeb do
    pipe_through [:browser, :require_authenticated_owner]

    live_session :require_authenticated_owner,
      on_mount: [{MementoMoriWeb.OwnerAuth, :require_authenticated}] do
      live "/owners/settings", OwnerLive.Settings, :edit
      live "/owners/settings/confirm-email/:token", OwnerLive.Settings, :confirm_email

      live "/capsules", CapsuleLive.Index, :index
      live "/capsules/new", CapsuleLive.Form, :new
      live "/capsules/:id", CapsuleLive.Show, :show
      live "/capsules/:id/edit", CapsuleLive.Form, :edit
    end

    post "/owners/update-password", OwnerSessionController, :update_password
  end

  scope "/", MementoMoriWeb do
    pipe_through [:browser]

    live_session :current_owner,
      on_mount: [{MementoMoriWeb.OwnerAuth, :mount_current_scope}] do
      live "/owners/register", OwnerLive.Registration, :new
      live "/owners/log-in", OwnerLive.Login, :new
      live "/owners/log-in/:token", OwnerLive.Confirmation, :new
    end

    post "/owners/log-in", OwnerSessionController, :create
    delete "/owners/log-out", OwnerSessionController, :delete
  end
end
