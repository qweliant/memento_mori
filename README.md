<!-- PROJECT SHIELDS -->
[![Tests](https://github.com/qweliant/memento_mori/actions/workflows/test.yml/badge.svg)](https://github.com/qweliant/memento_mori/actions/workflows/test.yml)

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![License][license-shield]][license-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <h3 align="center">Memento Mori</h3>

  <p align="center">
    Leave letters, photos, and memories for the people you love — opened exactly when the time is right.
    <br />
    <a href="https://github.com/qweliant/memento_mori/issues">Report Bug</a>
    &middot;
    <a href="https://github.com/qweliant/memento_mori/issues">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#architecture">Architecture</a></li>
    <li><a href="#impact--implications">Impact & Implications</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->

## About The Project

Memento Mori is a place to leave something behind for the people you love. A letter. Some
photos. A few words you want them to have. You pick when it reaches them, whether that's a
birthday years off or the day after you're gone.

You fill a **capsule**, you decide when it opens, and the people you picked receive it then
and not before. Think of a time capsule, minus the shovel and the hoping someone digs it up.

Three promises hold the whole thing together:

- **Only you can open it early.** Your capsule is locked on your own device before it ever
  reaches us. We hold the sealed box. We never hold the key.
- **It opens at the right time, and not before.** Set a date and the internet's own clock
  keeps it shut until then. Set it for "after I'm gone" and a few people you trust have to
  agree first.
- **It's really from you.** Your people get exactly what you left, unchanged. No fake,
  AI-generated version of you. This isn't a chatbot of the dead. It's your words, kept safe
  and handed on.

> **This is an experimental proof of concept**, not a finished product or a legal instrument.
> It's a working exploration of how digital inheritance *could* feel — warm, private, and
> honest — rather than something to trust with your real estate today.

### Built With

- [![Elixir][Elixir-badge]][Elixir-url]
- [![Phoenix][Phoenix-badge]][Phoenix-url]
- [![PostgreSQL][PostgreSQL-badge]][PostgreSQL-url]
- [![Tailwind CSS][Tailwind-badge]][Tailwind-url]

Plus [drand](https://drand.love) timelock encryption (via `tlock-js`) for the "opens on a
date" path, and [Commanded](https://github.com/commanded/commanded) event sourcing for a
tamper-evident history of every capsule.

<!-- GETTING STARTED -->

## Getting Started

### Prerequisites

- **Elixir 1.20+ / Erlang 27+** — easiest via [mise](https://mise.jdx.dev) (a `.mise.toml`
  is checked in), or install them however you like.
- **PostgreSQL 14+** running locally (the app uses two databases: one for data, one for the
  event store).
- **Node.js + npm** — only to install the front-end crypto library (`tlock-js`) the first
  time.

### Installation

Clone the repo:

```sh
git clone https://github.com/qweliant/memento_mori.git
cd memento_mori
```

Install the toolchain (if you use mise) and the front-end dependency:

```sh
mise install
npm install --prefix assets
```

Set up and run — `mix setup` fetches dependencies, creates both databases (data + event
store), runs migrations, and builds assets:

```sh
mix setup
mix phx.server
```

Then open [`localhost:4000`](http://localhost:4000), create an owner account, and confirm it
from the dev mailbox at [`localhost:4000/dev/mailbox`](http://localhost:4000/dev/mailbox).

Run the tests with:

```sh
mix test
```

For production you'll need to set `SECRET_KEY_BASE`, `DATABASE_URL`, `EVENTSTORE_URL`,
`CLOAK_KEY`, and `CLOAK_HMAC_KEY` (see `config/runtime.exs`).

<!-- ARCHITECTURE -->

## Architecture

A single Phoenix app with two faces: a **console** where an owner builds and manages capsules,
and a set of **public links** the people they name can use without ever making an account.

- **Capsules are event-sourced.** Every change — drafted, sealed, triggered, released,
  claimed — is an immutable event (Commanded + a Postgres event store). The lifecycle is a
  guarded state machine, so an empty capsule can't be sealed and nothing is released until
  it's genuinely allowed to be.
- **A hash-chained history.** Those events are projected into a tamper-evident audit ledger
  (each entry hashes the one before it), so you can prove the record hasn't been altered.
- **Two ways to open.** A capsule's "access contract" is either a **date** — the content key
  is timelock-encrypted to a future [drand](https://drand.love) round, so the network itself
  refuses to open it early — or a **condition** ("after I'm gone") confirmed by an N-of-M
  quorum of trusted people.
- **Encrypted on the device.** Files are encrypted in the browser before upload; the server
  only ever stores ciphertext. Sensitive fields (like emails) are encrypted at rest with a
  blind index for lookups.
- **People without accounts.** Trustees (who confirm) and beneficiaries (who receive) act
  through signed, single-purpose links — no login required.

<!-- IMPACT -->

### Impact & Implications

- **Peace of mind, kept simple.** The point is to make leaving something behind feel safe and
  unhurried — not to hand you a cryptography homework assignment.
- **Dignity over imitation.** A deliberate line in the sand: Memento Mori preserves what a
  person actually made and hands it on. It will never synthesize a fake voice or chatbot of
  the deceased.
- **Consent both ways.** The people who receive a capsule can accept, or quietly defer — an
  inheritance should never ambush someone. And a trustee can only *confirm*; they can never
  also receive, so no one can both trigger a release and collect from it.
- **Honest limits.** This is a proof of concept. It is not legal advice, not an estate plan,
  and not audited for production use. Today's access links are bearer links (whoever holds
  the link can act), and the "after I'm gone" flow is confirmed by trusted people rather than
  by any official record.

<!-- ROADMAP -->

## Roadmap

- [x] Owner accounts and the capsule console
- [x] Fill a capsule, encrypt on the device, and seal it
- [x] "Opens on a date" via drand timelock — provably can't open early
- [x] "Opens after I'm gone" via a trusted-people quorum, with a full release flow
- [x] Tamper-evident, hash-chained history for every capsule
- [x] Public links for trustees (confirm) and beneficiaries (receive)
- [x] Consistent light / dark theming
- [ ] Automatic reminders and a "haven't heard from you" safety check
- [ ] Real file uploads (photos, documents) beyond text notes
- [ ] Stronger account security (passkeys / two-factor)
- [ ] Harden the access links (from bearer links to proof-of-identity)

See the [open issues](https://github.com/qweliant/memento_mori/issues) for the full list.

<!-- CONTRIBUTING -->

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire,
and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<!-- LICENSE -->

## License

This is an experimental proof of concept and is not yet released under an open-source license
— all rights reserved for now. If you'd like to use or build on it, please open an issue.

<!-- MARKDOWN LINKS & IMAGES -->

[contributors-shield]: https://img.shields.io/github/contributors/qweliant/memento_mori.svg?style=for-the-badge
[contributors-url]: https://github.com/qweliant/memento_mori/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/qweliant/memento_mori.svg?style=for-the-badge
[forks-url]: https://github.com/qweliant/memento_mori/network/members
[stars-shield]: https://img.shields.io/github/stars/qweliant/memento_mori.svg?style=for-the-badge
[stars-url]: https://github.com/qweliant/memento_mori/stargazers
[issues-shield]: https://img.shields.io/github/issues/qweliant/memento_mori.svg?style=for-the-badge
[issues-url]: https://github.com/qweliant/memento_mori/issues
[license-shield]: https://img.shields.io/github/license/qweliant/memento_mori.svg?style=for-the-badge
[license-url]: https://github.com/qweliant/memento_mori/blob/main/LICENSE
[Elixir-badge]: https://img.shields.io/badge/Elixir-4B275F?style=for-the-badge&logo=elixir&logoColor=white
[Elixir-url]: https://elixir-lang.org/
[Phoenix-badge]: https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenix&logoColor=white
[Phoenix-url]: https://www.phoenixframework.org/
[PostgreSQL-badge]: https://img.shields.io/badge/PostgreSQL-336791?style=for-the-badge&logo=postgresql&logoColor=white
[PostgreSQL-url]: https://www.postgresql.org/
[Tailwind-badge]: https://img.shields.io/badge/Tailwind_CSS-38B2AC?style=for-the-badge&logo=tailwind-css&logoColor=white
[Tailwind-url]: https://tailwindcss.com/
