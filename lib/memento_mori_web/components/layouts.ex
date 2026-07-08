defmodule MementoMoriWeb.Layouts do
  @moduledoc """
  App layout + shell. `Layouts.app/1` renders the Memento Mori console shell:
  a fixed left sidebar (brand, theme toggle, nav, owner footer) beside a
  scrolling main column. Every LiveView keeps calling it exactly as before —

      <Layouts.app flash={@flash} current_scope={@current_scope}>
        …page…
      </Layouts.app>

  — and may optionally pass `active={:capsules}` (or `:settings`) to light the
  matching nav item.
  """
  use MementoMoriWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil, doc: "the current scope"
  attr :active, :atom, default: nil, doc: "which nav item to highlight (:capsules | :settings)"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="mm-shell">
      <aside class="mm-sidebar">
        <div class="flex items-start justify-between gap-2">
          <div>
            <div class="mm-brand-mark">Memento Mori</div>
            <div class="mm-brand-sub">DIGITAL ESTATE</div>
          </div>
          <.theme_toggle />
        </div>

        <nav :if={@current_scope} class="mm-nav">
          <.link navigate={~p"/capsules"} class={["mm-nav-item", @active == :capsules && "active"]}>
            <.icon name="hero-squares-2x2" class="size-4 opacity-85" /> Capsules
          </.link>
          <.link navigate={~p"/owners/settings"} class={["mm-nav-item", @active == :settings && "active"]}>
            <.icon name="hero-cog-6-tooth" class="size-4 opacity-85" /> Settings
          </.link>
        </nav>

        <div class="mm-foot">
          <%= if @current_scope && @current_scope.owner do %>
            <div class="mm-owner-name">{@current_scope.owner.email}</div>
            <div class="mm-owner-meta">Owner · signed in</div>
            <.link href={~p"/owners/log-out"} method="delete" class="mm-foot-link">
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-3.5" /> Log out
            </.link>
          <% else %>
            <div class="mm-owner-meta">Not signed in</div>
            <.link navigate={~p"/owners/log-in"} class="mm-foot-link">
              <.icon name="hero-arrow-right-end-on-rectangle" class="size-3.5" /> Log in
            </.link>
            <.link navigate={~p"/owners/register"} class="mm-foot-link">
              <.icon name="hero-user-plus" class="size-3.5" /> Sign up
            </.link>
          <% end %>
        </div>
      </aside>

      <main class="mm-main">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Compact dark/light/system theme toggle. The app defaults to dark now
  (see app.css: the dark theme is `default: true; prefersdark: true`).
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border border-base-300 bg-base-300 rounded-full w-fit">
      <div class="absolute w-1/3 h-full rounded-full border border-base-200 bg-base-100 brightness-150 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />
      <button class="flex p-1.5 cursor-pointer w-1/3" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system">
        <.icon name="hero-computer-desktop-micro" class="size-3.5 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-1.5 cursor-pointer w-1/3" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="light">
        <.icon name="hero-sun-micro" class="size-3.5 opacity-75 hover:opacity-100" />
      </button>
      <button class="flex p-1.5 cursor-pointer w-1/3" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="dark">
        <.icon name="hero-moon-micro" class="size-3.5 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
