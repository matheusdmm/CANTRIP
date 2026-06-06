import envoy
import gleam/list
import gleam/string
import simplifile

pub fn load(path: String) -> Nil {
  case simplifile.read(path) {
    Error(_) -> Nil
    Ok(raw) ->
      raw
      |> string.split("\n")
      |> list.each(apply_line)
  }
}

fn apply_line(line: String) -> Nil {
  let trimmed = string.trim(line)
  case trimmed == "" || string.starts_with(trimmed, "#") {
    True -> Nil
    False ->
      case string.split_once(trimmed, "=") {
        Error(_) -> Nil
        Ok(#(key, value)) -> {
          let key = string.trim(key)
          let value = strip_quotes(string.trim(value))
          case envoy.get(key) {
            Ok(_) -> Nil
            Error(_) -> envoy.set(key, value)
          }
        }
      }
  }
}

pub fn strip_quotes(s: String) -> String {
  let pairs = [#("\"", "\""), #("'", "'")]
  list.fold(pairs, s, fn(acc, p) {
    let #(open, close) = p
    case string.starts_with(acc, open) && string.ends_with(acc, close) {
      True -> acc |> string.drop_start(1) |> string.drop_end(1)
      False -> acc
    }
  })
}
