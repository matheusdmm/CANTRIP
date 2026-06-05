/// Spell-slot progressions for D&D 5.5e (2024 PHB).
///
/// `SlotTable` is a 9-element list: index 0 = number of 1st-level slots,
/// index 8 = number of 9th-level slots. Warlock's Pact Magic uses the same
/// shape — at level 5 a Warlock has `[0, 0, 2, 0, 0, 0, 0, 0, 0]` (two 3rd-level
/// slots) which recover on a short rest.
import gleam/list
import gleam/result

pub type SlotTable {
  SlotTable(slots: List(Int))
}

pub type SlotError {
  UnknownClass(String)
  LevelOutOfRange(Int)
}

pub fn empty() -> SlotTable {
  SlotTable([0, 0, 0, 0, 0, 0, 0, 0, 0])
}

pub fn max_slots(class_slug: String, level: Int) -> Result(SlotTable, SlotError) {
  case class_slug {
    "bardo" | "clerigo" | "druida" | "feiticeiro" | "mago" -> full_caster(level)
    "paladino" | "guardiao" -> half_caster(level)
    "bruxo" -> warlock(level)
    other -> Error(UnknownClass(other))
  }
}

/// Returns True if this class recovers its slots on short rest (Warlock only).
pub fn recovers_on_short_rest(class_slug: String) -> Bool {
  class_slug == "bruxo"
}

/// Reads the count of slots remaining at a given spell level (1-9).
/// Returns 0 if the level is out of range.
pub fn count_at(table: SlotTable, spell_level: Int) -> Int {
  let SlotTable(slots) = table
  case spell_level >= 1 && spell_level <= 9 {
    True ->
      case list.drop(slots, spell_level - 1) {
        [n, ..] -> n
        [] -> 0
      }
    False -> 0
  }
}

/// Decrement a slot at `spell_level`. Returns Error if no slot is available.
pub fn consume(table: SlotTable, spell_level: Int) -> Result(SlotTable, Nil) {
  let SlotTable(slots) = table
  case update_at(slots, spell_level - 1, fn(n) {
    case n > 0 {
      True -> Ok(n - 1)
      False -> Error(Nil)
    }
  }) {
    Ok(new) -> Ok(SlotTable(new))
    Error(_) -> Error(Nil)
  }
}

fn update_at(
  xs: List(Int),
  idx: Int,
  f: fn(Int) -> Result(Int, Nil),
) -> Result(List(Int), Nil) {
  case xs, idx {
    [], _ -> Error(Nil)
    [head, ..rest], 0 -> {
      use new <- result.try(f(head))
      Ok([new, ..rest])
    }
    [head, ..rest], n -> {
      use rest <- result.try(update_at(rest, n - 1, f))
      Ok([head, ..rest])
    }
  }
}

fn full_caster(level: Int) -> Result(SlotTable, SlotError) {
  case level {
    1 -> Ok(SlotTable([2, 0, 0, 0, 0, 0, 0, 0, 0]))
    2 -> Ok(SlotTable([3, 0, 0, 0, 0, 0, 0, 0, 0]))
    3 -> Ok(SlotTable([4, 2, 0, 0, 0, 0, 0, 0, 0]))
    4 -> Ok(SlotTable([4, 3, 0, 0, 0, 0, 0, 0, 0]))
    5 -> Ok(SlotTable([4, 3, 2, 0, 0, 0, 0, 0, 0]))
    6 -> Ok(SlotTable([4, 3, 3, 0, 0, 0, 0, 0, 0]))
    7 -> Ok(SlotTable([4, 3, 3, 1, 0, 0, 0, 0, 0]))
    8 -> Ok(SlotTable([4, 3, 3, 2, 0, 0, 0, 0, 0]))
    9 -> Ok(SlotTable([4, 3, 3, 3, 1, 0, 0, 0, 0]))
    10 -> Ok(SlotTable([4, 3, 3, 3, 2, 0, 0, 0, 0]))
    11 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 0, 0, 0]))
    12 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 0, 0, 0]))
    13 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 1, 0, 0]))
    14 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 1, 0, 0]))
    15 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 1, 1, 0]))
    16 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 1, 1, 0]))
    17 -> Ok(SlotTable([4, 3, 3, 3, 2, 1, 1, 1, 1]))
    18 -> Ok(SlotTable([4, 3, 3, 3, 3, 1, 1, 1, 1]))
    19 -> Ok(SlotTable([4, 3, 3, 3, 3, 2, 1, 1, 1]))
    20 -> Ok(SlotTable([4, 3, 3, 3, 3, 2, 2, 1, 1]))
    n -> Error(LevelOutOfRange(n))
  }
}

fn half_caster(level: Int) -> Result(SlotTable, SlotError) {
  case level {
    1 -> Ok(SlotTable([0, 0, 0, 0, 0, 0, 0, 0, 0]))
    2 -> Ok(SlotTable([2, 0, 0, 0, 0, 0, 0, 0, 0]))
    3 -> Ok(SlotTable([3, 0, 0, 0, 0, 0, 0, 0, 0]))
    4 -> Ok(SlotTable([3, 0, 0, 0, 0, 0, 0, 0, 0]))
    5 -> Ok(SlotTable([4, 2, 0, 0, 0, 0, 0, 0, 0]))
    6 -> Ok(SlotTable([4, 2, 0, 0, 0, 0, 0, 0, 0]))
    7 -> Ok(SlotTable([4, 3, 0, 0, 0, 0, 0, 0, 0]))
    8 -> Ok(SlotTable([4, 3, 0, 0, 0, 0, 0, 0, 0]))
    9 -> Ok(SlotTable([4, 3, 2, 0, 0, 0, 0, 0, 0]))
    10 -> Ok(SlotTable([4, 3, 2, 0, 0, 0, 0, 0, 0]))
    11 -> Ok(SlotTable([4, 3, 3, 0, 0, 0, 0, 0, 0]))
    12 -> Ok(SlotTable([4, 3, 3, 0, 0, 0, 0, 0, 0]))
    13 -> Ok(SlotTable([4, 3, 3, 1, 0, 0, 0, 0, 0]))
    14 -> Ok(SlotTable([4, 3, 3, 1, 0, 0, 0, 0, 0]))
    15 -> Ok(SlotTable([4, 3, 3, 2, 0, 0, 0, 0, 0]))
    16 -> Ok(SlotTable([4, 3, 3, 2, 0, 0, 0, 0, 0]))
    17 -> Ok(SlotTable([4, 3, 3, 3, 1, 0, 0, 0, 0]))
    18 -> Ok(SlotTable([4, 3, 3, 3, 1, 0, 0, 0, 0]))
    19 -> Ok(SlotTable([4, 3, 3, 3, 2, 0, 0, 0, 0]))
    20 -> Ok(SlotTable([4, 3, 3, 3, 2, 0, 0, 0, 0]))
    n -> Error(LevelOutOfRange(n))
  }
}

/// Warlock Pact Magic. All slots are the same spell-level and recover on a short rest.
fn warlock(level: Int) -> Result(SlotTable, SlotError) {
  let pact = fn(count: Int, slot_level: Int) -> SlotTable {
    let zeros_before = list.repeat(0, slot_level - 1)
    let zeros_after = list.repeat(0, 9 - slot_level)
    SlotTable(list.flatten([zeros_before, [count], zeros_after]))
  }
  case level {
    1 -> Ok(pact(1, 1))
    2 -> Ok(pact(2, 1))
    3 -> Ok(pact(2, 2))
    4 -> Ok(pact(2, 2))
    5 -> Ok(pact(2, 3))
    6 -> Ok(pact(2, 3))
    7 -> Ok(pact(2, 4))
    8 -> Ok(pact(2, 4))
    9 -> Ok(pact(2, 5))
    10 -> Ok(pact(2, 5))
    11 -> Ok(pact(3, 5))
    12 -> Ok(pact(3, 5))
    13 -> Ok(pact(3, 5))
    14 -> Ok(pact(3, 5))
    15 -> Ok(pact(3, 5))
    16 -> Ok(pact(3, 5))
    17 -> Ok(pact(4, 5))
    18 -> Ok(pact(4, 5))
    19 -> Ok(pact(4, 5))
    20 -> Ok(pact(4, 5))
    n -> Error(LevelOutOfRange(n))
  }
}
