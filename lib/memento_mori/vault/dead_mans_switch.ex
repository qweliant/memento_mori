defmodule MementoMori.Vault.DeadMansSwitch do
  @moduledoc """
  The dead-man's switch: an Oban worker, scheduled hourly (see the `Oban.Plugins.Cron`
  entry in config), that fires the inactivity trigger for every sealed capsule
  whose owner has gone silent past its contract's threshold.

  This is the automated counterpart to an owner manually firing a trigger. It
  deliberately does no more than move a capsule to `:triggered` — the trustee
  quorum, cooling-off, and withhold-on-doubt paths that follow are unchanged, so
  a mistaken silence never releases anything on its own. Correctness over
  availability: the switch opens the case; people (and the contract) still decide.
  """
  use Oban.Worker, queue: :timers, max_attempts: 3

  require Logger

  alias MementoMori.Vault

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    due = Vault.due_inactivity_capsules()

    if due != [] do
      Logger.info("dead-man's switch: #{length(due)} capsule(s) tripped inactivity")
    end

    Enum.each(due, fn capsule ->
      case Vault.trigger_inactivity(capsule.id) do
        :ok ->
          Logger.info("dead-man's switch fired inactivity trigger for capsule #{capsule.id}")

        {:error, reason} ->
          # The read-model row and the aggregate can briefly disagree (async
          # projection); the aggregate is authoritative, so a rejected fire is
          # expected and safe — log and move on.
          Logger.warning(
            "dead-man's switch could not fire capsule #{capsule.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
