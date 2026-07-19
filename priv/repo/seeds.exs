# Dev seeds — resets the vault to *only* the seeded example capsules, with real
# drand-timelock ciphertext so the artifacts actually open in the UI.
#
#     mix run priv/repo/seeds.exs
#
# Wipes every capsule (and its cascade) plus the audit projection, then reseeds
# each owner with the example capsules. Each artifact is sealed (via tlock-js, the
# same library the browser uses) to a drand round that has *already* been emitted,
# so "Try to open" reveals the note immediately. Destructive; refuses to run in prod.

alias MementoMori.{Accounts, Repo, Vault}
alias MementoMori.Accounts.{Owner, Scope}
alias MementoMori.Timelock.Drand
alias MementoMori.Vault.{AccessContract, AuditEvent, Capsule}

if function_exported?(Mix, :env, 0) and Mix.env() == :prod do
  raise "priv/repo/seeds.exs refuses to wipe capsules in prod."
end

assets_dir = Path.expand("../../assets", __DIR__)

# Fixed clock for the whole run, so a capsule's artifact round and its contract
# round agree. Each capsule's round is offset from `now` by its
# `unlock_in_seconds` (default -300 = ~5 min ago, already emitted → opens now).
# A positive offset (e.g. 90) seals into the future: locked until the round lands.
now = DateTime.utc_now()
round_for = fn spec -> Drand.round_at(DateTime.add(now, Map.get(spec, :unlock_in_seconds, -300))) end

# Real timelock sealer: shells out to tlock-js. Plaintext is base64'd onto argv
# to sidestep shell escaping; the armored ciphertext comes back on stdout.
sealer = fn artifact, spec ->
  case System.cmd(
         "node",
         ["tlock_seal.mjs", Integer.to_string(round_for.(spec)), Base.encode64(artifact.note)],
         cd: assets_dir,
         stderr_to_stdout: false
       ) do
    {armored, 0} -> armored
    {out, code} -> raise "tlock_seal.mjs failed (#{code}): #{out}"
  end
end

# Capsule children (artifacts, access_contracts, trustees, beneficiaries,
# attestations) cascade via on_delete: :delete_all. audit_events is a projection
# with no FK, so clear it explicitly.
{capsules_deleted, _} = Repo.delete_all(Capsule)
Repo.delete_all(AuditEvent)

owners = Repo.all(Owner)

for owner <- owners do
  scope = Scope.for_owner(owner)
  capsules = Vault.seed_example_capsules(scope, sealer)

  # A pure-time (:date) contract per capsule, sealed to that capsule's own round,
  # so the index reads "Time-locked · drand round N" instead of "No unlock set"
  # and the unlock instant lines up with its artifacts.
  for {capsule, spec} <- Enum.zip(capsules, Vault.example_capsules()) do
    round = round_for.(spec)

    %AccessContract{}
    |> AccessContract.changeset(%{
      trigger_type: :date,
      timelock_round: round,
      embargo_until: Drand.round_time(round) |> DateTime.truncate(:second),
      capsule_id: capsule.id
    })
    |> Repo.insert!()
  end

  Accounts.mark_starters_seeded(owner)
end

future = Enum.filter(Vault.example_capsules(), &Map.has_key?(&1, :unlock_in_seconds))

IO.puts(
  "Reset: deleted #{capsules_deleted} capsule(s); seeded #{length(owners)} owner(s). " <>
    "#{length(future)} capsule(s) sealed into the future — watch them unlock."
)
