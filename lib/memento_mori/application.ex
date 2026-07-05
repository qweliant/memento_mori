defmodule MementoMori.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        MementoMoriWeb.Telemetry,
        MementoMori.Repo,
        # Encryption vault must start before anything that reads/writes encrypted fields
        MementoMori.Encryption.Vault,
        {DNSCluster, query: Application.get_env(:memento_mori, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: MementoMori.PubSub},
        # Background jobs (dead-man's-switch timers, fixity sweeps)
        {Oban, Application.fetch_env!(:memento_mori, Oban)}
      ] ++
        [
          # Command dispatch / event-sourcing boundary for the capsule engine.
          # In dev/prod its adapter boots MementoMori.EventStore (Postgres); in
          # test it uses the in-memory adapter.
          MementoMori.CommandedApp
        ] ++
        projection_children() ++
        [
          # Start to serve requests, typically the last entry
          MementoMoriWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MementoMori.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Async read-model projections. Skipped in test, where the ledger/state logic
  # is verified as pure functions rather than through the live subscription.
  defp projection_children do
    if Application.get_env(:memento_mori, :start_projections, true) do
      [MementoMori.Vault.CapsuleStateProjector, MementoMori.Vault.AuditLedger]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MementoMoriWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
