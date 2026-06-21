# CANTRIP

D&D 5.5e spell reference and at-hand tracker for caster classes.

Built in Gleam on the BEAM (Erlang VM). single-file Alpine.js dashboard served from the same Gleam server.

## Running locally

You will need to have a `.env` file, use the .env.example as basis.

This needs to be setup, otherwise it will run on 0.0.0.0:8080 and pick the configuration for docker.

After that, just launch with `gleam run`.

```sh
gleam run    # starts the server on http://localhost:8080
gleam test   # runs the test suite
```

## Regenerating the spell dataset

You need to have bought the Players Hand Book in HTML OR PDF format if you need to regenerate it for some reason.

`priv/spells.json` is parsed from the PHB HTML in `test/`:

```sh
python scripts/parse_phb.py
```

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
