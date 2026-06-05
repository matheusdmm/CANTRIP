# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
gleam run        # start server (requires .env — see .env.example)
gleam test       # run test suite
gleam build      # compile without running
```

To regenerate `priv/spells.json` from the PHB HTML (requires the source file in `test/`):
```sh
python scripts/parse_phb.py
```

## Architecture

Single-binary Gleam application on the BEAM (Erlang/OTP). One HTTP server (Wisp + Mist) serves both a JSON API and the frontend SPA from `priv/static/index.html`.

### Backend modules

- **`src/cantrip.gleam`** — entry point, router, all HTTP handlers, and `.env` loader. Pattern-matches path segments directly; no router library.
- **`src/cantrip/session.gleam`** — OTP actor that owns all mutable state. One actor for the whole app. Keyed by class slug (`Dict(String, Session)`). All session mutations go through message-passing to this actor.
- **`src/cantrip/slots.gleam`** — pure spell-slot tables for D&D 5.5e. `SlotTable` is a 9-element `List(Int)` where index 0 = 1st-level slots. Encodes full-caster, half-caster, and Warlock (Pact Magic) progressions.
- **`src/cantrip/spell.gleam`** — `Spell` type, JSON decoder/encoder, and `class_slug/1` which lowercases + strips Portuguese diacritics to produce URL slugs.

### Frontend

`priv/static/index.html` is a self-contained Alpine.js SPA — inline CSS, inline JS, no build step. Alpine.js is loaded from CDN. The server just `simplifile.read`s and serves this file on `GET /`. The primary audience is **PT-BR**: all UI text, labels, and error messages are in Brazilian Portuguese.

### State model

Session state is **in-memory only** — no database. Restarting the server wipes all sessions. Each class gets its own `Session` record (level, max_slots, slots_remaining, at_hand set). Sessions are lazily initialized on first access.

### Class slugs (Portuguese)

Spell data uses Portuguese class names. `class_slug/1` in `spell.gleam` converts them to URL slugs: `"Clérigo" → "clerigo"`, `"Bruxo" → "bruxo"`, etc. The full set recognized by `slots.gleam` is: `bardo`, `clerigo`, `druida`, `feiticeiro`, `mago` (full casters), `paladino`, `guardiao` (half casters), `bruxo` (Warlock — Pact Magic, recovers on short rest).

### Deploy

`Dockerfile` uses a single-stage Gleam image (`gleam export erlang-shipment`) targeting Render.com (`render.yaml`). In production `HOST=0.0.0.0` and `PORT` is injected by Render; locally the `.env` file sets `HOST=127.0.0.1`.
