# Changelog

Memento Mori — a technical PoC for provenance-guaranteed digital inheritance.
Encrypt-on-device, open-only-at-the-right-moment, never a griefbot.

## Foundations

- Phoenix 1.8 (binary-id, Postgres, LiveView), owner auth via `phx.gen.auth`
  (pbkdf2 — Argon2/bcrypt need a C toolchain that isn't available here).
- Event-sourced capsule domain (Commanded + EventStore): `CapsuleAggregate`
  state machine `draft → sealed → triggered → verifying → released|withheld →
  claimed`, with a hash-chained, tamper-evident `AuditLedger`.
- Cloak encryption at rest (`envelope`, trustee/beneficiary email) with an
  HMAC blind index for lookups. Oban wired for future timers/fixity.

## Phase 1 — drand timelock, folded into the capsule flow

- Client-side timelock via `tlock-js` (drand quicknet). Artifacts are encrypted
  in the browser to a future drand round and only the ciphertext reaches the
  server (`CiphertextStore`, a local Files.com stand-in). Opening is refused by
  the network until the round is emitted.
- `AccessContract` `:date` path computes the drand round server-side
  (`Timelock.Drand`) so client and server agree. `Vault.add_sealed_artifact/3`
  captures a PREMIS sha256 fixity digest and dispatches `AddArtifact`.
- The capsule **Show** page became a console: set contract → seal artifacts →
  seal capsule → open → hash-chained audit ledger with a verify badge.

## Phase 2 — trustees, beneficiaries, condition path

- `Trustee` / `Beneficiary` enrollment with the **trustee ≠ beneficiary**
  invariant enforced via blind-index lookup.
- `:death` / `:life_event` / `:inactivity` contracts with an N-of-M trustee
  quorum. Full lifecycle driver on the console (fire → verify → threshold →
  release → claim), each action guarded by the aggregate.

## Phase 3 — capability-gated public flows

- **Trustee attestation** via signed capability links (`CapabilityToken`,
  `Phoenix.Token`). Public `/attest/:token` page (no account); attesting records
  an `Attestation` and confirms the trustee. The quorum is now real
  (attestation count), replacing the console's earlier simulation.
- **Beneficiary claim portal** at `/claim/:token` — a public LiveView (it needs
  the client-side timelock-decrypt hook). Beneficiaries open released artifacts
  client-side and **accept** or **defer** (consent — an inheritance can't
  ambush you).
- Owner console shows per-party invite/claim links.
- Retired the standalone `/timelock` demo (its mechanism now lives in the real
  capsule flow); extracted drand math to `Timelock.Drand`; dropped
  `sealed_messages`.
- Fixed a latent `HashedHMAC` config bug (missing `algorithm`) that would have
  crashed the first trustee/beneficiary enrollment.

## Known gaps / next

- Attestations are real but not yet cryptographically signed by a trustee
  keypair; capability links are bearer tokens (would be emailed + add
  proof-of-possession in production).
- Async projections (~400 ms) mean the console nudges a reload after dispatches.
- Not yet built: the dead-man's-switch Oban job, real file uploads (beyond text
  notes), owner MFA/passkeys.
