# CANTRIP

A digital spell tracker for D&D 5.5e. Pick your class and level, see which spells
you can cast, and keep track of used spell slots and "at hand" (prepared) spells
during a session — no more flipping through the book at the table. Interface is
in Brazilian Portuguese.

Under the hood: a Gleam server (runs on the Erlang VM) serving a JSON API plus a
single self-contained HTML page (Alpine.js, no build step) as the frontend.

## Running locally

Requires [Gleam](https://gleam.run) installed.

```sh
cp .env.example .env   # defaults to http://127.0.0.1:8080
gleam run               # starts the server
gleam test              # runs the test suite
```

Without a `.env` file, the server falls back to `0.0.0.0:8080` (the Docker/production
configuration) instead of localhost.

## Regenerating the spell dataset

`priv/spells.json` is generated from the Player's Handbook HTML — you need your own
legally obtained copy in `test/` to run this:

```sh
python scripts/parse_phb.py
```

Most contributors won't need this; the generated `priv/spells.json` is already
checked in.

## Endpoints

```
GET    /                                       Dashboard (HTML)
GET    /api/health                             { ok: true }

GET    /classes                                Caster classes
GET    /classes/:slug/spells[?level=N]         Spells for a class
GET    /spells/:slug                           One spell

GET    /classes/:slug/session                  Current session state
PUT    /classes/:slug/session  { level: N }    Set caster level
POST   /classes/:slug/cast     { spell_level: N }   Spend a slot
POST   /classes/:slug/long-rest                Restore all slots
POST   /classes/:slug/short-rest               Warlock-only effect

POST   /classes/:slug/at-hand  { spell_slug: "..." }   Bookmark
DELETE /classes/:slug/at-hand/:spell-slug              Unbookmark
POST   /classes/:slug/at-hand/clear                    Wipe bookmarks
```

## Deploy

`Dockerfile` to deploy on Coolify and be happy :)
