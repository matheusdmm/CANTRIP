import gleam/int
import gleam/list
import gleam/result

pub fn parse_level(params: List(#(String, String))) -> Result(Int, Nil) {
  use v <- result.try(list.key_find(params, "level"))
  int.parse(v)
}
