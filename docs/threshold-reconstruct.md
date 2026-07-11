# Threshold reconstruction for `secret_key` artifacts

Status: **design spec** (not yet built). Owner: Vault domain.

## Why this exists

Most artifacts take the `:deliver` release path: on release the capsule's content
key (CEK) is re-wrapped to the beneficiary's `claim_public_key` and they open it.
That's fine for a letter or a will — the *operator* is trusted not to peek because
the CEK is only ever handled client-side, but a single beneficiary receiving the
whole thing is acceptable.

A **`secret_key`** artifact (password-manager master key, wallet seed phrase,
recovery codes) has a sharper requirement: *no single party should be able to
reconstruct it before the release conditions are met* — not the operator, not any
one trustee, and not the beneficiary acting alone. That is the whole "trustless
env-var service" idea applied to inheritance. `ArtifactKind.release_strategy/1`
returns `:threshold_reconstruct` for exactly this kind; this doc specifies that
path.

## Threat model / invariant

Let `k` = `access_contract.quorum_threshold`, `n` = number of enrolled trustees
(`quorum_size`). The construction must hold this table true at all times:

| Party                         | Can reconstruct the secret? |
| ----------------------------- | --------------------------- |
| Operator (us), pre- or post-release | **Never** — only ever holds ciphertext + shares encrypted to keys we don't have |
| Any single trustee            | **Never** — holds exactly one Shamir share |
| Any `k-1` colluding trustees  | **Never** — below the reconstruction threshold |
| `k` trustees + beneficiary, conditions met | **Yes** — the only path |
| Beneficiary alone             | **Never** — needs `k` trustees to contribute |

`:threshold_reconstruct` therefore pairs with a **condition contract** (trustee
quorum), not a bare `:date` timelock — there have to be trustees to hold shares.
A timelock *may* be layered on top later (shares also sealed to a drand round),
but the base spec is quorum-gated.

## Cryptographic construction (two layers)

All crypto is **client-side**, consistent with the zero-knowledge boundary in
`MementoMori.Encryption.Vault` (the operator never sees a CEK).

1. **Content layer.** The owner's secret is encrypted in the browser under a
   random CEK → armored ciphertext, stored via `CiphertextStore` exactly like any
   other artifact (`Artifact.ciphertext_ref`). Nothing new here.

2. **Key layer (new).** The CEK is split with **Shamir Secret Sharing** into `n`
   shares, threshold `k`. Share `i` is encrypted to **trustee `i`'s
   `public_key`**. The operator stores only these per-trustee-encrypted shares.
   The CEK itself is discarded in the browser after splitting — it exists whole
   *only* for the moment of sealing, on the owner's device.

Reconstruction re-encrypts, it does not centralize: at release each attesting
trustee decrypts *their one share* and re-encrypts it to the beneficiary's
`claim_public_key` (proxy hand-off). The beneficiary collects `k` such shares,
Shamir-combines them to recover the CEK, and decrypts the ciphertext — all in
their browser. The server is a blind courier of encrypted shares throughout.

## New persisted state

Everything below is opaque to the operator (ciphertext or public keys only).

- **`trustee.public_key`** — already exists. Populated at trustee key enrollment
  (see below), currently unused.
- **`beneficiary.claim_public_key`** — already exists. Populated when the
  beneficiary enrolls a claim keypair.
- **`key_shares`** table (new):

  ```
  key_shares
    id            :binary_id
    artifact_id   → artifacts (the secret_key artifact this CEK belongs to)
    trustee_id    → trustees  (whose public_key the share is sealed to)
    beneficiary_id → beneficiaries (nullable; whom it's destined for)
    share_for_trustee    :binary   -- Shamir share encrypted to trustee.public_key
    share_for_beneficiary :binary  -- filled at attest time: re-encrypted to claim key
    contributed_at :utc_datetime   -- when the trustee handed their share off
    timestamps
  ```

  `share_for_trustee` is written at seal time; `share_for_beneficiary` +
  `contributed_at` are written when that trustee attests. A capsule is
  reconstructable once `k` rows have a non-null `share_for_beneficiary`.

- **`artifact` marker.** No new column needed — `artifact.kind == :secret_key`
  *is* the marker, and `release_strategy(:secret_key) == :threshold_reconstruct`
  is the branch. (If a capsule ever mixes kinds, reconstruction is per-artifact,
  which the `key_shares.artifact_id` FK already supports.)

## Lifecycle touchpoints

### 0. Enrollment (prerequisite, sequencing-critical)

Threshold custody needs keys to exist *before* sealing:

- **Trustee keys.** When a trustee accepts their capability link
  (`MementoMoriWeb.CapabilityToken`), their browser generates a keypair, POSTs the
  public half → `trustee.public_key`, keeps the private half (downloaded /
  passphrase-wrapped locally). Until this happens the trustee cannot receive a
  share.
- **Beneficiary claim key.** Same pattern at the claim link, or the owner asks the
  beneficiary to pre-enroll a recovery key during setup. Needed before a trustee
  can re-encrypt a share *to* them.

**Sealing a `secret_key` artifact is blocked until `n ≥ k` trustees have
`public_key` set and the beneficiary has a `claim_public_key`.** The seal UI
should surface this as a precondition, the way it already nags "enroll trustees
first" for a condition contract.

### 1. Seal (owner, client-side)

Extends the `CapsuleSeal` hook path. When `kind == :secret_key`:

1. Encrypt secret → ciphertext under fresh CEK (existing flow).
2. Fetch the `n` trustee public keys (rendered into the seal panel as data attrs,
   like `data-round` today).
3. `shares = shamir.split(CEK, {threshold: k, shares: n})`.
4. For each trustee `i`: `enc_i = encryptTo(trustee_i.public_key, shares[i])`.
5. Push `sealed` with the ciphertext **and** `key_shares: [{trustee_id, enc_i}]`.
6. Discard CEK and raw shares from memory.

Server (`Vault.add_sealed_artifact`) stores the artifact as today, then inserts
the `key_shares` rows (`share_for_trustee = enc_i`). The `ArtifactAdded` event is
unchanged; share storage is read-model plumbing, not an aggregate concern.

### 2. Attest + contribute (trustee, client-side)

Today attesting is a server action (`Vault.record_attestation`). For a
`:threshold_reconstruct` capsule the attest page gains a client-side step:

1. Trustee decrypts their `share_for_trustee` with their private key.
2. Re-encrypts to `beneficiary.claim_public_key` → `share_for_beneficiary`.
3. Submits it alongside the attestation.

The trustee's own share is plaintext in their browser for that instant — one
share, below threshold, useless alone. Server writes `share_for_beneficiary` +
`contributed_at`. **A trustee who attests but declines to contribute their share
counts toward the quorum but not toward reconstruction** — see the gate below.

### 3. Release gate (aggregate)

`:deliver` capsules release when the attestation quorum is met. For
`:threshold_reconstruct` the gate is stricter and must be enforced in
`CapsuleAggregate`, not just the read model:

> Release is legal only when **≥ k trustees have both attested *and* contributed a
> `share_for_beneficiary`** for every `secret_key` artifact in the capsule.

Concretely, add a command/event pair so the count is an event-sourced fact:

```elixir
# Commands
defmodule ContributeShare do
  defstruct [:capsule_id, :artifact_id, :trustee_id, :beneficiary_id]
end

# Events
defmodule ShareContributed do
  @derive Jason.Encoder
  defstruct [:capsule_id, :artifact_id, :trustee_id, :contributed_at]
end
```

The aggregate tallies `ShareContributed` per artifact; `RecordThresholdMet` /
`ReleaseCapsule` reject with `{:error, :shares_incomplete}` until every
`secret_key` artifact has `k`. This keeps the audit ledger honest: "who handed
off a share, when" is chained like everything else. No share *material* goes in
the event — only the fact that a contribution happened.

### 4. Claim + reconstruct (beneficiary, client-side)

Extends the claim portal (`claim_live.ex`, `get_claim_context`). For each
`secret_key` artifact:

1. Fetch the `k` `share_for_beneficiary` blobs.
2. Decrypt each with the claim private key.
3. `CEK = shamir.combine(shares)`.
4. Decrypt `ciphertext_ref` contents with the CEK → reveal the secret.

If fewer than `k` shares have been contributed, the portal shows "waiting on N
more trustees," never a partial secret.

## Domain wiring summary

- **Seam:** `ArtifactKind.release_strategy(kind)` already branches `:deliver` vs
  `:threshold_reconstruct`. Everything above hangs off that one function.
- **New:** `key_shares` table + schema; `ContributeShare`/`ShareContributed`
  command+event; aggregate tally + stricter release guard; three client-side
  crypto steps (split at seal, re-encrypt at attest, combine at claim); key
  enrollment for trustees and beneficiaries.
- **Unchanged:** ciphertext storage, the zero-knowledge boundary, the audit
  chain shape, the `:deliver` path for every other kind.

## Failure modes & edges

- **Trustee loses their private key** → their share is unrecoverable. Mitigation:
  `n > k` (spare shares); optionally allow the owner to re-issue by re-sealing.
- **Beneficiary loses claim key before reconstruction** → re-enroll a new claim
  key and have trustees re-contribute (re-encrypt to the new key). Shares are
  never exposed to the operator in this dance.
- **Trustee/beneficiary overlap** → already forbidden (`counterpart?/3`); critical
  here, since a party who is both could hold a share *and* be the recipient.
- **Quorum met but shares incomplete** → capsule sits in `:verifying`; the gate
  refuses `:released`. Surface "attested but no share contributed" per trustee.
- **Mixed-kind capsule** → reconstruction is per-artifact (`key_shares.artifact_id`);
  a will (`:deliver`) and a seed phrase (`:threshold_reconstruct`) can co-exist in
  one capsule and release by their own rules.

## Suggested build order

1. **Key enrollment** — trustee `public_key` + beneficiary `claim_public_key`
   capture at the capability links (no secrets ever sent). Nothing reconstructs
   yet; this is pure groundwork.
2. **`key_shares` schema + seal-time split** — store shares; assert the
   `n ≥ k` + beneficiary-key precondition before allowing a `secret_key` seal.
3. **Attest-time contribution** — `ContributeShare`/`ShareContributed`, the
   re-encryption step, aggregate tally.
4. **Stricter release gate** — block release until shares complete.
5. **Claim-time reconstruction** — combine + decrypt in the beneficiary portal.

Pick a vetted Shamir + sealed-box library on the JS side; do not hand-roll the
field arithmetic or the box encryption.
