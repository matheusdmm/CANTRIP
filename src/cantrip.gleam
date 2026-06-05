import envoy
import gleam/dynamic/decode
import gleam/erlang/application
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import mist
import simplifile
import cantrip/session
import cantrip/slots
import cantrip/spell.{type Spell}
import wisp
import wisp/wisp_mist

pub type Context {
  Context(spells: List(Spell), sessions: session.Handle, priv_dir: String)
}

pub fn main() -> Nil {
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(priv) = application.priv_directory("cantrip")
  let assert Ok(spells) = load_spells_from(priv)
  io.println("Loaded " <> int.to_string(list.length(spells)) <> " spells")

  let assert Ok(sessions) = session.start()
  io.println("Session actor started")

  let ctx = Context(spells:, sessions:, priv_dir: priv)
  let handler = handle_request(_, ctx)

  let host = host_from_env()
  let port = port_from_env()
  io.println("Listening on " <> host <> ":" <> int.to_string(port))

  let assert Ok(_) =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.bind(host)
    |> mist.port(port)
    |> mist.start

  process.sleep_forever()
}

fn host_from_env() -> String {
  envoy.get("HOST") |> result.unwrap("127.0.0.1")
}

fn port_from_env() -> Int {
  envoy.get("PORT")
  |> result.try(int.parse)
  |> result.unwrap(8080)
}

fn load_spells_from(priv: String) -> Result(List(Spell), String) {
  use raw <- result.try(
    simplifile.read(priv <> "/spells.json")
    |> result.map_error(simplifile.describe_error),
  )
  let list_decoder = decode.at(["spells"], decode.list(spell.decoder()))
  json.parse(raw, list_decoder)
  |> result.map_error(fn(e) { "JSON parse error: " <> json_error_to_string(e) })
}

fn json_error_to_string(err: json.DecodeError) -> String {
  case err {
    json.UnexpectedEndOfInput -> "unexpected end of input"
    json.UnexpectedByte(b) -> "unexpected byte: " <> b
    json.UnexpectedSequence(s) -> "unexpected sequence: " <> s
    json.UnableToDecode(_) -> "unable to decode against schema"
  }
}

fn handle_request(req: wisp.Request, ctx: Context) -> wisp.Response {
  use req <- middleware(req)
  case wisp.path_segments(req) {
    [] -> serve_spa(ctx)
    ["api", "health"] -> health()
    ["classes"] -> list_classes(ctx)
    ["classes", class_slug, "spells"] -> list_class_spells(req, ctx, class_slug)
    ["spells", slug] -> get_spell(ctx, slug)

    ["classes", class_slug, "session"] -> session_route(req, ctx, class_slug)
    ["classes", class_slug, "cast"] -> cast_route(req, ctx, class_slug)
    ["classes", class_slug, "long-rest"] ->
      rest_route(req, ctx, class_slug, session.long_rest)
    ["classes", class_slug, "short-rest"] ->
      rest_route(req, ctx, class_slug, session.short_rest)

    ["classes", class_slug, "at-hand"] -> at_hand_post(req, ctx, class_slug)
    ["classes", class_slug, "at-hand", "clear"] ->
      at_hand_clear(req, ctx, class_slug)
    ["classes", class_slug, "at-hand", spell_slug] ->
      at_hand_delete(req, ctx, class_slug, spell_slug)

    _ -> wisp.not_found()
  }
}

fn middleware(
  req: wisp.Request,
  handle: fn(wisp.Request) -> wisp.Response,
) -> wisp.Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  handle(req)
}

fn health() -> wisp.Response {
  json.object([
    #("ok", json.bool(True)),
    #("msg", json.string("cantrip online")),
  ])
  |> json.to_string
  |> wisp.json_response(200)
}

fn serve_spa(ctx: Context) -> wisp.Response {
  case simplifile.read(ctx.priv_dir <> "/static/index.html") {
    Ok(html) -> wisp.html_response(html, 200)
    Error(_) -> wisp.internal_server_error()
  }
}

fn list_classes(ctx: Context) -> wisp.Response {
  let classes =
    ctx.spells
    |> list.flat_map(fn(s) { s.classes })
    |> list.unique
    |> list.sort(string.compare)

  classes
  |> json.array(of: fn(name) {
    json.object([
      #("name", json.string(name)),
      #("slug", json.string(spell.class_slug(name))),
    ])
  })
  |> json.to_string
  |> wisp.json_response(200)
}

fn list_class_spells(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
) -> wisp.Response {
  let level_filter = parse_level_query(wisp.get_query(req))

  let matching =
    ctx.spells
    |> list.filter(fn(s) {
      list.any(s.classes, fn(c) { spell.class_slug(c) == class_slug })
    })
    |> list.filter(fn(s) {
      case level_filter {
        Ok(level) -> s.level == level
        Error(_) -> True
      }
    })
    |> list.sort(fn(a, b) {
      case int.compare(a.level, b.level) {
        order.Eq -> string.compare(a.name, b.name)
        other -> other
      }
    })

  case matching {
    [] -> wisp.not_found()
    _ ->
      matching
      |> json.array(of: spell.to_json)
      |> json.to_string
      |> wisp.json_response(200)
  }
}

fn get_spell(ctx: Context, slug: String) -> wisp.Response {
  case list.find(ctx.spells, fn(s) { s.slug == slug }) {
    Ok(s) -> spell.to_json(s) |> json.to_string |> wisp.json_response(200)
    Error(_) -> wisp.not_found()
  }
}

// ----- session endpoints -----

fn session_route(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
) -> wisp.Response {
  case req.method {
    http.Get -> {
      let s = session.get(ctx.sessions, class_slug)
      ok_json(session_to_json(s))
    }
    http.Put -> {
      use body <- wisp.require_json(req)
      let level_decoder = {
        use level <- decode.field("level", decode.int)
        decode.success(level)
      }
      case decode.run(body, level_decoder) {
        Ok(level) ->
          session.set_level(ctx.sessions, class_slug, level)
          |> session_result_response
        Error(_) -> wisp.bad_request("expected { level: <int> }")
      }
    }
    _ -> wisp.method_not_allowed([http.Get, http.Put])
  }
}

fn cast_route(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
) -> wisp.Response {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_json(req)
  let spell_level_decoder = {
    use n <- decode.field("spell_level", decode.int)
    decode.success(n)
  }
  case decode.run(body, spell_level_decoder) {
    Ok(spell_level) ->
      session.cast(ctx.sessions, class_slug, spell_level)
      |> session_result_response
    Error(_) -> wisp.bad_request("expected { spell_level: <int> }")
  }
}

fn rest_route(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
  op: fn(session.Handle, String) -> Result(session.Session, session.DomainError),
) -> wisp.Response {
  use <- wisp.require_method(req, http.Post)
  op(ctx.sessions, class_slug)
  |> session_result_response
}

fn at_hand_post(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
) -> wisp.Response {
  use <- wisp.require_method(req, http.Post)
  use body <- wisp.require_json(req)
  let slug_decoder = {
    use s <- decode.field("spell_slug", decode.string)
    decode.success(s)
  }
  case decode.run(body, slug_decoder) {
    Ok(spell_slug) -> {
      let s = session.add_at_hand(ctx.sessions, class_slug, spell_slug)
      ok_json(session_to_json(s))
    }
    Error(_) -> wisp.bad_request("expected { spell_slug: <string> }")
  }
}

fn at_hand_delete(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
  spell_slug: String,
) -> wisp.Response {
  use <- wisp.require_method(req, http.Delete)
  let s = session.remove_at_hand(ctx.sessions, class_slug, spell_slug)
  ok_json(session_to_json(s))
}

fn at_hand_clear(
  req: wisp.Request,
  ctx: Context,
  class_slug: String,
) -> wisp.Response {
  use <- wisp.require_method(req, http.Post)
  let s = session.clear_at_hand(ctx.sessions, class_slug)
  ok_json(session_to_json(s))
}

// ----- response helpers / encoders -----

fn ok_json(body: json.Json) -> wisp.Response {
  body |> json.to_string |> wisp.json_response(200)
}

fn session_result_response(
  r: Result(session.Session, session.DomainError),
) -> wisp.Response {
  case r {
    Ok(s) -> ok_json(session_to_json(s))
    Error(err) -> domain_error_response(err)
  }
}

fn domain_error_response(err: session.DomainError) -> wisp.Response {
  let #(status, message) = case err {
    session.LevelNotSet -> #(409, "session level not set; PUT /session first")
    session.InvalidSlotLevel(n) -> #(
      400,
      "invalid spell level: " <> int.to_string(n),
    )
    session.NoSlotsAvailable(n) -> #(
      409,
      "no slots available at level " <> int.to_string(n),
    )
    session.SlotsError(slots.UnknownClass(c)) -> #(404, "unknown class: " <> c)
    session.SlotsError(slots.LevelOutOfRange(n)) -> #(
      400,
      "level out of range (1-20): " <> int.to_string(n),
    )
  }
  json.object([
    #("error", json.string(message)),
  ])
  |> json.to_string
  |> wisp.json_response(status)
}

fn session_to_json(s: session.Session) -> json.Json {
  let level_json = case s.level {
    Some(n) -> json.int(n)
    None -> json.null()
  }
  json.object([
    #("level", level_json),
    #("max_slots", slot_table_to_json(s.max_slots)),
    #("slots_remaining", slot_table_to_json(s.slots_remaining)),
    #(
      "at_hand",
      set.to_list(s.at_hand)
        |> list.sort(string.compare)
        |> json.array(json.string),
    ),
  ])
}

fn slot_table_to_json(t: slots.SlotTable) -> json.Json {
  let slots.SlotTable(xs) = t
  json.array(xs, json.int)
}

fn parse_level_query(query: List(#(String, String))) -> Result(Int, Nil) {
  use v <- result.try(list.key_find(query, "level"))
  int.parse(v)
}
