/// Per-class session state, owned by a single actor.
///
/// One actor for the whole app keeps things simple at this scale (~hundreds of
/// keys, single-user). On the BEAM, an actor is a process — message-passing
/// keeps the state thread-safe without locks.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/set.{type Set}
import cantrip/slots.{type SlotTable}

pub type Session {
  Session(
    level: Option(Int),
    max_slots: SlotTable,
    slots_remaining: SlotTable,
    at_hand: Set(String),
  )
}

pub type DomainError {
  LevelNotSet
  InvalidSlotLevel(Int)
  NoSlotsAvailable(Int)
  SlotsError(slots.SlotError)
}

type State {
  State(by_class: Dict(String, Session))
}

pub opaque type Handle {
  Handle(subject: Subject(Msg))
}

type Msg {
  Get(class: String, reply: Subject(Session))
  SetLevel(class: String, level: Int, reply: Subject(Result(Session, DomainError)))
  Cast(class: String, spell_level: Int, reply: Subject(Result(Session, DomainError)))
  LongRest(class: String, reply: Subject(Result(Session, DomainError)))
  ShortRest(class: String, reply: Subject(Result(Session, DomainError)))
  AddAtHand(class: String, spell_slug: String, reply: Subject(Session))
  RemoveAtHand(class: String, spell_slug: String, reply: Subject(Session))
  ClearAtHand(class: String, reply: Subject(Session))
  Restore(
    class: String,
    level: Int,
    slots_remaining: SlotTable,
    at_hand: Set(String),
    reply: Subject(Session),
  )
}

pub fn start() -> Result(Handle, actor.StartError) {
  use started <- result.try(
    actor.new(State(by_class: dict.new()))
    |> actor.on_message(handle_message)
    |> actor.start,
  )
  Ok(Handle(subject: started.data))
}

pub fn empty_session() -> Session {
  Session(
    level: None,
    max_slots: slots.empty(),
    slots_remaining: slots.empty(),
    at_hand: set.new(),
  )
}

fn get_or_init(state: State, class: String) -> Session {
  case dict.get(state.by_class, class) {
    Ok(s) -> s
    Error(_) -> empty_session()
  }
}

fn put(state: State, class: String, session: Session) -> State {
  State(by_class: dict.insert(state.by_class, class, session))
}

fn handle_message(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Get(class, reply) -> {
      process.send(reply, get_or_init(state, class))
      actor.continue(state)
    }

    SetLevel(class, level, reply) ->
      case slots.max_slots(class, level) {
        Ok(table) -> {
          let prev = get_or_init(state, class)
          let session =
            Session(
              level: Some(level),
              max_slots: table,
              slots_remaining: table,
              at_hand: prev.at_hand,
            )
          process.send(reply, Ok(session))
          actor.continue(put(state, class, session))
        }
        Error(e) -> {
          process.send(reply, Error(SlotsError(e)))
          actor.continue(state)
        }
      }

    Cast(class, spell_level, reply) ->
      case validate_cast(state, class, spell_level) {
        Ok(session) -> {
          process.send(reply, Ok(session))
          actor.continue(put(state, class, session))
        }
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(state)
        }
      }

    LongRest(class, reply) -> {
      let session = get_or_init(state, class)
      case session.level {
        None -> {
          process.send(reply, Error(LevelNotSet))
          actor.continue(state)
        }
        Some(_) -> {
          let restored = Session(..session, slots_remaining: session.max_slots)
          process.send(reply, Ok(restored))
          actor.continue(put(state, class, restored))
        }
      }
    }

    ShortRest(class, reply) -> {
      let session = get_or_init(state, class)
      case session.level, slots.recovers_on_short_rest(class) {
        None, _ -> {
          process.send(reply, Error(LevelNotSet))
          actor.continue(state)
        }
        Some(_), True -> {
          let restored = Session(..session, slots_remaining: session.max_slots)
          process.send(reply, Ok(restored))
          actor.continue(put(state, class, restored))
        }
        Some(_), False -> {
          process.send(reply, Ok(session))
          actor.continue(state)
        }
      }
    }

    AddAtHand(class, spell_slug, reply) -> {
      let session = get_or_init(state, class)
      let updated =
        Session(..session, at_hand: set.insert(session.at_hand, spell_slug))
      process.send(reply, updated)
      actor.continue(put(state, class, updated))
    }

    RemoveAtHand(class, spell_slug, reply) -> {
      let session = get_or_init(state, class)
      let updated =
        Session(..session, at_hand: set.delete(session.at_hand, spell_slug))
      process.send(reply, updated)
      actor.continue(put(state, class, updated))
    }

    ClearAtHand(class, reply) -> {
      let session = get_or_init(state, class)
      let updated = Session(..session, at_hand: set.new())
      process.send(reply, updated)
      actor.continue(put(state, class, updated))
    }

    Restore(class, level, slots_remaining, at_hand, reply) -> {
      case slots.max_slots(class, level) {
        Ok(max) -> {
          let session =
            Session(
              level: Some(level),
              max_slots: max,
              slots_remaining: slots_remaining,
              at_hand: at_hand,
            )
          process.send(reply, session)
          actor.continue(put(state, class, session))
        }
        Error(_) -> {
          process.send(reply, empty_session())
          actor.continue(state)
        }
      }
    }
  }
}

fn validate_cast(
  state: State,
  class: String,
  spell_level: Int,
) -> Result(Session, DomainError) {
  let session = get_or_init(state, class)
  use _ <- result.try(case session.level {
    Some(_) -> Ok(Nil)
    None -> Error(LevelNotSet)
  })
  use _ <- result.try(case spell_level >= 1 && spell_level <= 9 {
    True -> Ok(Nil)
    False -> Error(InvalidSlotLevel(spell_level))
  })
  case slots.consume(session.slots_remaining, spell_level) {
    Ok(new_slots) -> Ok(Session(..session, slots_remaining: new_slots))
    Error(_) -> Error(NoSlotsAvailable(spell_level))
  }
}

// ----- public API used by the HTTP handlers -----

pub fn get(handle: Handle, class: String) -> Session {
  process.call(handle.subject, 100, Get(class, _))
}

pub fn set_level(
  handle: Handle,
  class: String,
  level: Int,
) -> Result(Session, DomainError) {
  process.call(handle.subject, 100, SetLevel(class, level, _))
}

pub fn cast(
  handle: Handle,
  class: String,
  spell_level: Int,
) -> Result(Session, DomainError) {
  process.call(handle.subject, 100, Cast(class, spell_level, _))
}

pub fn long_rest(handle: Handle, class: String) -> Result(Session, DomainError) {
  process.call(handle.subject, 100, LongRest(class, _))
}

pub fn short_rest(handle: Handle, class: String) -> Result(Session, DomainError) {
  process.call(handle.subject, 100, ShortRest(class, _))
}

pub fn add_at_hand(handle: Handle, class: String, spell_slug: String) -> Session {
  process.call(handle.subject, 100, AddAtHand(class, spell_slug, _))
}

pub fn remove_at_hand(
  handle: Handle,
  class: String,
  spell_slug: String,
) -> Session {
  process.call(handle.subject, 100, RemoveAtHand(class, spell_slug, _))
}

pub fn clear_at_hand(handle: Handle, class: String) -> Session {
  process.call(handle.subject, 100, ClearAtHand(class, _))
}

pub fn restore(
  handle: Handle,
  class: String,
  level: Int,
  slots_remaining: SlotTable,
  at_hand: Set(String),
) -> Session {
  process.call(
    handle.subject,
    100,
    Restore(class, level, slots_remaining, at_hand, _),
  )
}
