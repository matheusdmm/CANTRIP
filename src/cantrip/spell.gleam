import gleam/dynamic/decode
import gleam/json
import gleam/string

pub type Spell {
  Spell(
    name: String,
    slug: String,
    level: Int,
    school: String,
    classes: List(String),
    casting_time: String,
    range: String,
    components: String,
    duration: String,
    ritual: Bool,
    concentration: Bool,
    description: String,
  )
}

pub fn decoder() -> decode.Decoder(Spell) {
  use name <- decode.field("name", decode.string)
  use slug <- decode.field("slug", decode.string)
  use level <- decode.field("level", decode.int)
  use school <- decode.field("school", decode.string)
  use classes <- decode.field("classes", decode.list(decode.string))
  use casting_time <- decode.field("casting_time", decode.string)
  use range <- decode.field("range", decode.string)
  use components <- decode.field("components", decode.string)
  use duration <- decode.field("duration", decode.string)
  use ritual <- decode.field("ritual", decode.bool)
  use concentration <- decode.field("concentration", decode.bool)
  use description <- decode.field("description", decode.string)
  decode.success(Spell(
    name:,
    slug:,
    level:,
    school:,
    classes:,
    casting_time:,
    range:,
    components:,
    duration:,
    ritual:,
    concentration:,
    description:,
  ))
}

pub fn to_json(spell: Spell) -> json.Json {
  json.object([
    #("name", json.string(spell.name)),
    #("slug", json.string(spell.slug)),
    #("level", json.int(spell.level)),
    #("school", json.string(spell.school)),
    #("classes", json.array(spell.classes, json.string)),
    #("casting_time", json.string(spell.casting_time)),
    #("range", json.string(spell.range)),
    #("components", json.string(spell.components)),
    #("duration", json.string(spell.duration)),
    #("ritual", json.bool(spell.ritual)),
    #("concentration", json.bool(spell.concentration)),
    #("description", json.string(spell.description)),
  ])
}

/// Lowercase + strip accents → `mago`, `clerigo`, `guardiao`.
/// Used to match a URL slug like `/classes/clerigo/spells` against
/// the Portuguese class names stored in each spell record.
pub fn class_slug(class: String) -> String {
  class
  |> string.lowercase
  |> string.to_graphemes
  |> fold_ascii("")
}

fn fold_ascii(graphemes: List(String), acc: String) -> String {
  case graphemes {
    [] -> acc
    [g, ..rest] -> fold_ascii(rest, acc <> deaccent(g))
  }
}

/// Matches the non latin keyboard with the proper names
fn deaccent(g: String) -> String {
  case g {
    "á" | "â" | "ã" | "à" | "ä" -> "a"
    "é" | "ê" | "è" | "ë" -> "e"
    "í" | "î" | "ì" | "ï" -> "i"
    "ó" | "ô" | "õ" | "ò" | "ö" -> "o"
    "ú" | "û" | "ù" | "ü" -> "u"
    "ç" -> "c"
    "ñ" -> "n"
    other -> other
  }
}
