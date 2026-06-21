import cantrip
import cantrip/dotenv
import cantrip/query
import cantrip/session
import cantrip/slots
import cantrip/spell
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import gleeunit
import gleeunit/should
import wisp/simulate

pub fn main() -> Nil {
  gleeunit.main()
}

// ── test helpers ──────────────────────────────────────────────────────────────

fn test_spell(
  name: String,
  slug: String,
  level: Int,
  classes: List(String),
) -> spell.Spell {
  spell.Spell(
    name:,
    slug:,
    level:,
    school: "Evocação",
    classes:,
    casting_time: "Ação",
    range: "9 metros",
    components: "V, S",
    duration: "Instantânea",
    ritual: False,
    concentration: False,
    description: "Descrição.",
  )
}

fn test_ctx() -> cantrip.Context {
  let assert Ok(sessions) = session.start()
  cantrip.Context(
    spells: [
      test_spell("Luz", "luz", 0, ["Clérigo", "Mago"]),
      test_spell("Míssil Mágico", "missil-magico", 1, ["Mago"]),
      test_spell("Bola de Fogo", "bola-de-fogo", 3, ["Mago", "Feiticeiro"]),
    ],
    sessions:,
    priv_dir: "",
  )
}

// ── slots ─────────────────────────────────────────────────────────────────────

pub fn slots_empty_all_zero_test() {
  let table = slots.empty()
  [1, 2, 3, 4, 5, 6, 7, 8, 9]
  |> list.each(fn(lvl) { slots.count_at(table, lvl) |> should.equal(0) })
}

pub fn slots_count_at_out_of_range_test() {
  let table = slots.empty()
  slots.count_at(table, 0) |> should.equal(0)
  slots.count_at(table, 10) |> should.equal(0)
}

pub fn slots_unknown_class_test() {
  slots.max_slots("cavaleiro", 5) |> should.be_error()
}

pub fn slots_level_out_of_range_test() {
  slots.max_slots("mago", 0) |> should.be_error()
  slots.max_slots("mago", 21) |> should.be_error()
}

pub fn full_caster_level1_test() {
  let assert Ok(t) = slots.max_slots("mago", 1)
  slots.count_at(t, 1) |> should.equal(2)
  slots.count_at(t, 2) |> should.equal(0)
}

pub fn full_caster_level5_test() {
  let assert Ok(t) = slots.max_slots("mago", 5)
  slots.count_at(t, 1) |> should.equal(4)
  slots.count_at(t, 2) |> should.equal(3)
  slots.count_at(t, 3) |> should.equal(2)
  slots.count_at(t, 4) |> should.equal(0)
}

pub fn full_caster_level17_ninth_slot_test() {
  let assert Ok(t) = slots.max_slots("clerigo", 17)
  slots.count_at(t, 9) |> should.equal(1)
}

pub fn full_caster_level20_test() {
  let assert Ok(t) = slots.max_slots("mago", 20)
  slots.count_at(t, 6) |> should.equal(2)
  slots.count_at(t, 9) |> should.equal(1)
}

pub fn full_caster_classes_same_slots_test() {
  let classes = ["bardo", "clerigo", "druida", "feiticeiro", "mago"]
  let assert Ok(ref) = slots.max_slots("mago", 10)
  list.each(classes, fn(c) {
    let assert Ok(t) = slots.max_slots(c, 10)
    [1, 2, 3, 4, 5, 6, 7, 8, 9]
    |> list.each(fn(lvl) {
      slots.count_at(t, lvl) |> should.equal(slots.count_at(ref, lvl))
    })
  })
}

pub fn half_caster_level1_no_slots_test() {
  let assert Ok(t) = slots.max_slots("paladino", 1)
  slots.count_at(t, 1) |> should.equal(0)
}

pub fn half_caster_level2_first_slots_test() {
  let assert Ok(t) = slots.max_slots("guardiao", 2)
  slots.count_at(t, 1) |> should.equal(2)
}

pub fn half_caster_level5_second_level_slots_test() {
  let assert Ok(t) = slots.max_slots("paladino", 5)
  slots.count_at(t, 2) |> should.equal(2)
}

pub fn half_casters_identical_at_all_levels_test() {
  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
  |> list.each(fn(level) {
    let assert Ok(g) = slots.max_slots("guardiao", level)
    let assert Ok(p) = slots.max_slots("paladino", level)
    [1, 2, 3, 4, 5, 6, 7, 8, 9]
    |> list.each(fn(sl) {
      slots.count_at(g, sl) |> should.equal(slots.count_at(p, sl))
    })
  })
}

pub fn warlock_level1_one_first_level_slot_test() {
  let assert Ok(t) = slots.max_slots("bruxo", 1)
  slots.count_at(t, 1) |> should.equal(1)
  slots.count_at(t, 2) |> should.equal(0)
}

pub fn warlock_level5_pact_slot_level_test() {
  let assert Ok(t) = slots.max_slots("bruxo", 5)
  slots.count_at(t, 3) |> should.equal(2)
  slots.count_at(t, 1) |> should.equal(0)
  slots.count_at(t, 2) |> should.equal(0)
}

pub fn warlock_level11_three_slots_test() {
  let assert Ok(t) = slots.max_slots("bruxo", 11)
  slots.count_at(t, 5) |> should.equal(3)
}

pub fn warlock_level17_four_slots_test() {
  let assert Ok(t) = slots.max_slots("bruxo", 17)
  slots.count_at(t, 5) |> should.equal(4)
}

pub fn recovers_on_short_rest_only_bruxo_test() {
  slots.recovers_on_short_rest("bruxo") |> should.be_true()
  slots.recovers_on_short_rest("mago") |> should.be_false()
  slots.recovers_on_short_rest("clerigo") |> should.be_false()
  slots.recovers_on_short_rest("paladino") |> should.be_false()
}

pub fn consume_decrements_slot_test() {
  let assert Ok(t) = slots.max_slots("mago", 3)
  let assert Ok(after) = slots.consume(t, 1)
  slots.count_at(after, 1) |> should.equal(3)
}

pub fn consume_other_levels_unchanged_test() {
  let assert Ok(t) = slots.max_slots("mago", 5)
  let assert Ok(after) = slots.consume(t, 1)
  slots.count_at(after, 2) |> should.equal(slots.count_at(t, 2))
  slots.count_at(after, 3) |> should.equal(slots.count_at(t, 3))
}

pub fn consume_depletes_all_slots_test() {
  let assert Ok(t) = slots.max_slots("mago", 1)
  let assert Ok(t1) = slots.consume(t, 1)
  let assert Ok(t2) = slots.consume(t1, 1)
  slots.count_at(t2, 1) |> should.equal(0)
  slots.consume(t2, 1) |> should.be_error()
}

pub fn consume_empty_table_errors_test() {
  slots.consume(slots.empty(), 1) |> should.be_error()
}

pub fn consume_level_zero_errors_test() {
  let assert Ok(t) = slots.max_slots("mago", 5)
  slots.consume(t, 0) |> should.be_error()
}

pub fn consume_level_ten_errors_test() {
  let assert Ok(t) = slots.max_slots("mago", 20)
  slots.consume(t, 10) |> should.be_error()
}

// ── spell ─────────────────────────────────────────────────────────────────────

pub fn class_slug_mago_test() {
  spell.class_slug("Mago") |> should.equal("mago")
}

pub fn class_slug_clerigo_test() {
  spell.class_slug("Clérigo") |> should.equal("clerigo")
}

pub fn class_slug_guardiao_test() {
  spell.class_slug("Guardião") |> should.equal("guardiao")
}

pub fn class_slug_feiticeiro_test() {
  spell.class_slug("Feiticeiro") |> should.equal("feiticeiro")
}

pub fn class_slug_bruxo_test() {
  spell.class_slug("Bruxo") |> should.equal("bruxo")
}

pub fn class_slug_druida_test() {
  spell.class_slug("Druida") |> should.equal("druida")
}

pub fn class_slug_bardo_test() {
  spell.class_slug("Bardo") |> should.equal("bardo")
}

pub fn class_slug_paladino_test() {
  spell.class_slug("Paladino") |> should.equal("paladino")
}

pub fn class_slug_already_lowercase_test() {
  spell.class_slug("mago") |> should.equal("mago")
}

pub fn class_slug_all_vowel_accents_test() {
  spell.class_slug("áéíóúàèìòùâêîôûãõäëïöü")
  |> should.equal("aeiouaeiouaeiouaoaeiou")
}

pub fn class_slug_cedilla_test() {
  spell.class_slug("ç") |> should.equal("c")
}

pub fn spell_json_roundtrip_test() {
  let original =
    test_spell("Bola de Fogo", "bola-de-fogo", 3, ["Feiticeiro", "Mago"])
  let encoded = json.to_string(spell.to_json(original))
  let assert Ok(decoded) = json.parse(encoded, spell.decoder())
  decoded.name |> should.equal(original.name)
  decoded.slug |> should.equal(original.slug)
  decoded.level |> should.equal(original.level)
  decoded.school |> should.equal(original.school)
  decoded.classes |> should.equal(original.classes)
  decoded.casting_time |> should.equal(original.casting_time)
  decoded.range |> should.equal(original.range)
  decoded.components |> should.equal(original.components)
  decoded.duration |> should.equal(original.duration)
  decoded.ritual |> should.equal(original.ritual)
  decoded.concentration |> should.equal(original.concentration)
  decoded.description |> should.equal(original.description)
}

pub fn spell_decoder_rejects_missing_field_test() {
  let bad_json = "{\"name\":\"Teste\",\"slug\":\"teste\"}"
  json.parse(bad_json, spell.decoder()) |> should.be_error()
}

// ── session ───────────────────────────────────────────────────────────────────

pub fn session_get_returns_empty_for_new_class_test() {
  let assert Ok(handle) = session.start()
  let s = session.get(handle, "mago")
  s.level |> should.equal(None)
}

pub fn session_set_level_stores_level_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(s) = session.set_level(handle, "mago", 5)
  s.level |> should.equal(Some(5))
}

pub fn session_set_level_loads_correct_slots_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(s) = session.set_level(handle, "mago", 5)
  slots.count_at(s.max_slots, 1) |> should.equal(4)
  slots.count_at(s.max_slots, 3) |> should.equal(2)
}

pub fn session_set_level_resets_slots_remaining_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  let assert Ok(_) = session.cast(handle, "mago", 1)
  let assert Ok(s) = session.set_level(handle, "mago", 5)
  slots.count_at(s.slots_remaining, 1) |> should.equal(4)
}

pub fn session_set_level_downgrade_resets_slots_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 10)
  let assert Ok(s) = session.set_level(handle, "mago", 3)
  s.level |> should.equal(Some(3))
  slots.count_at(s.max_slots, 3) |> should.equal(0)
  slots.count_at(s.slots_remaining, 3) |> should.equal(0)
}

pub fn session_set_level_unknown_class_errors_test() {
  let assert Ok(handle) = session.start()
  session.set_level(handle, "cavaleiro", 5) |> should.be_error()
}

pub fn session_set_level_zero_errors_test() {
  let assert Ok(handle) = session.start()
  session.set_level(handle, "mago", 0) |> should.be_error()
}

pub fn session_set_level_21_errors_test() {
  let assert Ok(handle) = session.start()
  session.set_level(handle, "mago", 21) |> should.be_error()
}

pub fn session_cast_decrements_slot_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  let assert Ok(s) = session.cast(handle, "mago", 1)
  slots.count_at(s.slots_remaining, 1) |> should.equal(3)
}

pub fn session_cast_without_level_errors_test() {
  let assert Ok(handle) = session.start()
  session.cast(handle, "mago", 1) |> should.be_error()
}

pub fn session_cast_invalid_slot_level_errors_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  session.cast(handle, "mago", 0) |> should.be_error()
  session.cast(handle, "mago", 10) |> should.be_error()
}

pub fn session_cast_no_slots_available_errors_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 1)
  let assert Ok(_) = session.cast(handle, "mago", 1)
  let assert Ok(_) = session.cast(handle, "mago", 1)
  session.cast(handle, "mago", 1) |> should.be_error()
}

pub fn session_long_rest_restores_slots_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  let assert Ok(_) = session.cast(handle, "mago", 1)
  let assert Ok(_) = session.cast(handle, "mago", 1)
  let assert Ok(s) = session.long_rest(handle, "mago")
  slots.count_at(s.slots_remaining, 1) |> should.equal(4)
}

pub fn session_long_rest_without_level_errors_test() {
  let assert Ok(handle) = session.start()
  session.long_rest(handle, "mago") |> should.be_error()
}

pub fn session_long_rest_bruxo_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "bruxo", 5)
  let assert Ok(_) = session.cast(handle, "bruxo", 3)
  let assert Ok(s) = session.long_rest(handle, "bruxo")
  slots.count_at(s.slots_remaining, 3) |> should.equal(2)
}

pub fn session_short_rest_bruxo_restores_slots_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "bruxo", 5)
  let assert Ok(_) = session.cast(handle, "bruxo", 3)
  let assert Ok(s) = session.short_rest(handle, "bruxo")
  slots.count_at(s.slots_remaining, 3) |> should.equal(2)
}

pub fn session_short_rest_non_bruxo_does_not_restore_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  let assert Ok(_) = session.cast(handle, "mago", 1)
  let assert Ok(s) = session.short_rest(handle, "mago")
  slots.count_at(s.slots_remaining, 1) |> should.equal(3)
}

pub fn session_short_rest_without_level_errors_test() {
  let assert Ok(handle) = session.start()
  session.short_rest(handle, "mago") |> should.be_error()
}

pub fn session_long_rest_clears_concentration_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  let _ = session.set_concentration(handle, "mago", Some("bola-de-fogo"))
  let assert Ok(s) = session.long_rest(handle, "mago")
  s.concentrating |> should.equal(None)
}

pub fn session_short_rest_clears_concentration_bruxo_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "bruxo", 5)
  let _ = session.set_concentration(handle, "bruxo", Some("bola-de-fogo"))
  let assert Ok(s) = session.short_rest(handle, "bruxo")
  s.concentrating |> should.equal(None)
}

pub fn session_short_rest_clears_concentration_non_bruxo_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 5)
  let _ = session.set_concentration(handle, "mago", Some("bola-de-fogo"))
  let assert Ok(s) = session.short_rest(handle, "mago")
  s.concentrating |> should.equal(None)
}

pub fn session_add_at_hand_test() {
  let assert Ok(handle) = session.start()
  let s = session.add_at_hand(handle, "mago", "bola-de-fogo")
  set.contains(s.at_hand, "bola-de-fogo") |> should.be_true()
}

pub fn session_remove_at_hand_test() {
  let assert Ok(handle) = session.start()
  let _ = session.add_at_hand(handle, "mago", "bola-de-fogo")
  let s = session.remove_at_hand(handle, "mago", "bola-de-fogo")
  set.contains(s.at_hand, "bola-de-fogo") |> should.be_false()
}

pub fn session_clear_at_hand_test() {
  let assert Ok(handle) = session.start()
  let _ = session.add_at_hand(handle, "mago", "bola-de-fogo")
  let _ = session.add_at_hand(handle, "mago", "missil-magico")
  let s = session.clear_at_hand(handle, "mago")
  set.is_empty(s.at_hand) |> should.be_true()
}

pub fn session_at_hand_idempotent_add_test() {
  let assert Ok(handle) = session.start()
  let _ = session.add_at_hand(handle, "mago", "bola-de-fogo")
  let s = session.add_at_hand(handle, "mago", "bola-de-fogo")
  set.size(s.at_hand) |> should.equal(1)
}

pub fn session_at_hand_remove_nonexistent_test() {
  let assert Ok(handle) = session.start()
  let s = session.remove_at_hand(handle, "mago", "bola-de-fogo")
  set.is_empty(s.at_hand) |> should.be_true()
}

pub fn session_at_hand_persists_across_level_change_test() {
  let assert Ok(handle) = session.start()
  let _ = session.add_at_hand(handle, "mago", "bola-de-fogo")
  let assert Ok(s) = session.set_level(handle, "mago", 10)
  set.contains(s.at_hand, "bola-de-fogo") |> should.be_true()
}

pub fn session_classes_are_isolated_test() {
  let assert Ok(handle) = session.start()
  let assert Ok(_) = session.set_level(handle, "mago", 10)
  let clerigo = session.get(handle, "clerigo")
  clerigo.level |> should.equal(None)
}

// ── query ─────────────────────────────────────────────────────────────────────

pub fn query_parse_level_valid_test() {
  query.parse_level([#("level", "3")]) |> should.equal(Ok(3))
}

pub fn query_parse_level_zero_cantrips_test() {
  query.parse_level([#("level", "0")]) |> should.equal(Ok(0))
}

pub fn query_parse_level_non_int_errors_test() {
  query.parse_level([#("level", "abc")]) |> should.be_error()
}

pub fn query_parse_level_empty_string_errors_test() {
  query.parse_level([#("level", "")]) |> should.be_error()
}

pub fn query_parse_level_missing_key_errors_test() {
  query.parse_level([]) |> should.be_error()
}

pub fn query_parse_level_different_key_errors_test() {
  query.parse_level([#("school", "evocacao")]) |> should.be_error()
}

pub fn query_parse_level_ignores_extra_params_test() {
  query.parse_level([#("school", "evocacao"), #("level", "5")])
  |> should.equal(Ok(5))
}

// ── dotenv ────────────────────────────────────────────────────────────────────

pub fn strip_quotes_double_quoted_test() {
  dotenv.strip_quotes("\"hello\"") |> should.equal("hello")
}

pub fn strip_quotes_single_quoted_test() {
  dotenv.strip_quotes("'hello'") |> should.equal("hello")
}

pub fn strip_quotes_bare_value_test() {
  dotenv.strip_quotes("hello") |> should.equal("hello")
}

pub fn strip_quotes_empty_string_test() {
  dotenv.strip_quotes("") |> should.equal("")
}

pub fn strip_quotes_mismatched_quotes_unchanged_test() {
  dotenv.strip_quotes("\"mismatched'") |> should.equal("\"mismatched'")
}

pub fn strip_quotes_only_open_quote_unchanged_test() {
  dotenv.strip_quotes("\"hello") |> should.equal("\"hello")
}

pub fn strip_quotes_empty_double_quotes_test() {
  dotenv.strip_quotes("\"\"") |> should.equal("")
}

// ── HTTP integration ──────────────────────────────────────────────────────────

pub fn http_health_test() {
  let resp =
    simulate.request(http.Get, "/api/health")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  simulate.read_body(resp) |> string.contains("cantrip online") |> should.be_true()
}

pub fn http_list_classes_test() {
  let resp =
    simulate.request(http.Get, "/classes")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  let body = simulate.read_body(resp)
  body |> string.contains("mago") |> should.be_true()
  body |> string.contains("feiticeiro") |> should.be_true()
  body |> string.contains("clerigo") |> should.be_true()
}

pub fn http_list_class_spells_test() {
  let resp =
    simulate.request(http.Get, "/classes/mago/spells")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  simulate.read_body(resp)
  |> string.contains("missil-magico")
  |> should.be_true()
}

pub fn http_list_class_spells_level_filter_test() {
  let resp =
    simulate.request(http.Get, "/classes/mago/spells?level=1")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  let body = simulate.read_body(resp)
  body |> string.contains("missil-magico") |> should.be_true()
  body |> string.contains("bola-de-fogo") |> should.be_false()
}

pub fn http_list_class_spells_cantrip_filter_test() {
  let resp =
    simulate.request(http.Get, "/classes/mago/spells?level=0")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  simulate.read_body(resp) |> string.contains("luz") |> should.be_true()
}

pub fn http_list_class_spells_no_match_404_test() {
  let resp =
    simulate.request(http.Get, "/classes/mago/spells?level=9")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(404)
}

pub fn http_list_unknown_class_spells_404_test() {
  let resp =
    simulate.request(http.Get, "/classes/cavaleiro/spells")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(404)
}

pub fn http_get_spell_test() {
  let resp =
    simulate.request(http.Get, "/spells/bola-de-fogo")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  simulate.read_body(resp)
  |> string.contains("Bola de Fogo")
  |> should.be_true()
}

pub fn http_get_spell_not_found_test() {
  let resp =
    simulate.request(http.Get, "/spells/nao-existe")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(404)
}

pub fn http_get_session_test() {
  let resp =
    simulate.request(http.Get, "/classes/mago/session")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(200)
  simulate.read_body(resp) |> string.contains("\"level\":null") |> should.be_true()
}

pub fn http_set_level_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Put, "/classes/mago/session")
    |> simulate.json_body(json.object([#("level", json.int(5))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
  simulate.read_body(resp) |> string.contains("\"level\":5") |> should.be_true()
}

pub fn http_set_level_invalid_body_400_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Put, "/classes/mago/session")
    |> simulate.json_body(json.object([#("nome", json.string("errado"))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(400)
}

pub fn http_set_level_unknown_class_404_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Put, "/classes/cavaleiro/session")
    |> simulate.json_body(json.object([#("level", json.int(5))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(404)
}

pub fn http_set_level_out_of_range_400_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Put, "/classes/mago/session")
    |> simulate.json_body(json.object([#("level", json.int(0))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(400)
}

pub fn http_session_wrong_method_405_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/session")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(405)
}

pub fn http_cast_without_level_409_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/cast")
    |> simulate.json_body(json.object([#("spell_level", json.int(1))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(409)
}

pub fn http_cast_test() {
  let ctx = test_ctx()
  let _ =
    simulate.request(http.Put, "/classes/mago/session")
    |> simulate.json_body(json.object([#("level", json.int(5))]))
    |> cantrip.handle_request(ctx)
  let resp =
    simulate.request(http.Post, "/classes/mago/cast")
    |> simulate.json_body(json.object([#("spell_level", json.int(1))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
}

pub fn http_cast_wrong_method_405_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Get, "/classes/mago/cast")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(405)
}

pub fn http_long_rest_without_level_409_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/long-rest")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(409)
}

pub fn http_long_rest_test() {
  let ctx = test_ctx()
  let _ =
    simulate.request(http.Put, "/classes/mago/session")
    |> simulate.json_body(json.object([#("level", json.int(5))]))
    |> cantrip.handle_request(ctx)
  let _ =
    simulate.request(http.Post, "/classes/mago/cast")
    |> simulate.json_body(json.object([#("spell_level", json.int(1))]))
    |> cantrip.handle_request(ctx)
  let resp =
    simulate.request(http.Post, "/classes/mago/long-rest")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
}

pub fn http_short_rest_bruxo_test() {
  let ctx = test_ctx()
  let _ =
    simulate.request(http.Put, "/classes/bruxo/session")
    |> simulate.json_body(json.object([#("level", json.int(5))]))
    |> cantrip.handle_request(ctx)
  let _ =
    simulate.request(http.Post, "/classes/bruxo/cast")
    |> simulate.json_body(json.object([#("spell_level", json.int(3))]))
    |> cantrip.handle_request(ctx)
  let resp =
    simulate.request(http.Post, "/classes/bruxo/short-rest")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
}

pub fn http_at_hand_add_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/at-hand")
    |> simulate.json_body(
      json.object([#("spell_slug", json.string("missil-magico"))]),
    )
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
  simulate.read_body(resp)
  |> string.contains("missil-magico")
  |> should.be_true()
}

pub fn http_at_hand_delete_test() {
  let ctx = test_ctx()
  let _ =
    simulate.request(http.Post, "/classes/mago/at-hand")
    |> simulate.json_body(
      json.object([#("spell_slug", json.string("missil-magico"))]),
    )
    |> cantrip.handle_request(ctx)
  let resp =
    simulate.request(http.Delete, "/classes/mago/at-hand/missil-magico")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
}

pub fn http_at_hand_clear_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/at-hand/clear")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
}

pub fn http_concentration_set_and_drop_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/concentration")
    |> simulate.json_body(
      json.object([#("spell_slug", json.string("missil-magico"))]),
    )
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
  simulate.read_body(resp)
  |> string.contains("\"concentrating\":\"missil-magico\"")
  |> should.be_true()

  let resp =
    simulate.request(http.Post, "/classes/mago/concentration")
    |> simulate.json_body(json.object([#("spell_slug", json.null())]))
    |> cantrip.handle_request(ctx)
  simulate.read_body(resp)
  |> string.contains("\"concentrating\":null")
  |> should.be_true()
}

pub fn http_unknown_route_404_test() {
  let resp =
    simulate.request(http.Get, "/rota/inexistente")
    |> cantrip.handle_request(test_ctx())
  resp.status |> should.equal(404)
}

// ── session.restore ───────────────────────────────────────────────────────────

pub fn session_restore_sets_level_test() {
  let assert Ok(handle) = session.start()
  let s =
    session.restore(
      handle,
      "mago",
      5,
      slots.SlotTable([2, 1, 0, 0, 0, 0, 0, 0, 0]),
      set.new(),
      None,
    )
  s.level |> should.equal(Some(5))
}

pub fn session_restore_preserves_slots_remaining_test() {
  let assert Ok(handle) = session.start()
  let remaining = slots.SlotTable([2, 1, 0, 0, 0, 0, 0, 0, 0])
  let s = session.restore(handle, "mago", 5, remaining, set.new(), None)
  slots.count_at(s.slots_remaining, 1) |> should.equal(2)
  slots.count_at(s.slots_remaining, 2) |> should.equal(1)
  slots.count_at(s.slots_remaining, 3) |> should.equal(0)
}

pub fn session_restore_max_slots_from_level_not_remaining_test() {
  let assert Ok(handle) = session.start()
  let partial = slots.SlotTable([1, 0, 0, 0, 0, 0, 0, 0, 0])
  let s = session.restore(handle, "mago", 5, partial, set.new(), None)
  slots.count_at(s.max_slots, 1) |> should.equal(4)
  slots.count_at(s.max_slots, 2) |> should.equal(3)
  slots.count_at(s.max_slots, 3) |> should.equal(2)
}

pub fn session_restore_preserves_at_hand_test() {
  let assert Ok(handle) = session.start()
  let at_hand = set.from_list(["bola-de-fogo", "escudo"])
  let s = session.restore(handle, "mago", 5, slots.empty(), at_hand, None)
  set.contains(s.at_hand, "bola-de-fogo") |> should.be_true()
  set.contains(s.at_hand, "escudo") |> should.be_true()
}

pub fn session_restore_unknown_class_returns_empty_test() {
  let assert Ok(handle) = session.start()
  let s =
    session.restore(handle, "cavaleiro", 5, slots.empty(), set.new(), None)
  s.level |> should.equal(None)
}

pub fn session_restore_persists_across_calls_test() {
  let assert Ok(handle) = session.start()
  let remaining = slots.SlotTable([1, 1, 0, 0, 0, 0, 0, 0, 0])
  let _ = session.restore(handle, "mago", 5, remaining, set.new(), None)
  let s = session.get(handle, "mago")
  slots.count_at(s.slots_remaining, 1) |> should.equal(1)
}

pub fn session_restore_then_cast_works_test() {
  let assert Ok(handle) = session.start()
  let remaining = slots.SlotTable([3, 2, 0, 0, 0, 0, 0, 0, 0])
  let _ = session.restore(handle, "mago", 5, remaining, set.new(), None)
  let assert Ok(s) = session.cast(handle, "mago", 1)
  slots.count_at(s.slots_remaining, 1) |> should.equal(2)
}

pub fn session_restore_then_long_rest_resets_to_max_test() {
  let assert Ok(handle) = session.start()
  let partial = slots.SlotTable([1, 0, 0, 0, 0, 0, 0, 0, 0])
  let _ = session.restore(handle, "mago", 5, partial, set.new(), None)
  let assert Ok(s) = session.long_rest(handle, "mago")
  slots.count_at(s.slots_remaining, 1) |> should.equal(4)
}

pub fn session_restore_preserves_concentrating_test() {
  let assert Ok(handle) = session.start()
  let s =
    session.restore(
      handle,
      "mago",
      5,
      slots.empty(),
      set.new(),
      Some("bola-de-fogo"),
    )
  s.concentrating |> should.equal(Some("bola-de-fogo"))
}

// ── session.set_concentration ───────────────────────────────────────────────

pub fn session_set_concentration_test() {
  let assert Ok(handle) = session.start()
  let s = session.set_concentration(handle, "mago", Some("bola-de-fogo"))
  s.concentrating |> should.equal(Some("bola-de-fogo"))
}

pub fn session_drop_concentration_test() {
  let assert Ok(handle) = session.start()
  let _ = session.set_concentration(handle, "mago", Some("bola-de-fogo"))
  let s = session.set_concentration(handle, "mago", None)
  s.concentrating |> should.equal(None)
}

pub fn session_set_concentration_replaces_previous_test() {
  let assert Ok(handle) = session.start()
  let _ = session.set_concentration(handle, "mago", Some("bola-de-fogo"))
  let s = session.set_concentration(handle, "mago", Some("escudo"))
  s.concentrating |> should.equal(Some("escudo"))
}

// ── HTTP restore endpoint ─────────────────────────────────────────────────────

pub fn http_restore_session_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/session/restore")
    |> simulate.json_body(
      json.object([
        #("level", json.int(5)),
        #(
          "slots_remaining",
          json.array([2, 1, 0, 0, 0, 0, 0, 0, 0], json.int),
        ),
        #("at_hand", json.array(["bola-de-fogo"], json.string)),
      ]),
    )
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
  let body = simulate.read_body(resp)
  body |> string.contains("\"level\":5") |> should.be_true()
  body |> string.contains("bola-de-fogo") |> should.be_true()
}

pub fn http_restore_session_preserves_slots_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/session/restore")
    |> simulate.json_body(
      json.object([
        #("level", json.int(5)),
        #(
          "slots_remaining",
          json.array([2, 1, 0, 0, 0, 0, 0, 0, 0], json.int),
        ),
        #("at_hand", json.array([], json.string)),
      ]),
    )
    |> cantrip.handle_request(ctx)
  let body = simulate.read_body(resp)
  body
  |> string.contains("\"slots_remaining\":[2,1,0,0,0,0,0,0,0]")
  |> should.be_true()
}

pub fn http_restore_session_missing_field_400_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/mago/session/restore")
    |> simulate.json_body(json.object([#("level", json.int(5))]))
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(400)
}

pub fn http_restore_session_wrong_method_405_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Get, "/classes/mago/session/restore")
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(405)
}

pub fn http_restore_session_unknown_class_returns_empty_test() {
  let ctx = test_ctx()
  let resp =
    simulate.request(http.Post, "/classes/cavaleiro/session/restore")
    |> simulate.json_body(
      json.object([
        #("level", json.int(5)),
        #("slots_remaining", json.array([], json.int)),
        #("at_hand", json.array([], json.string)),
      ]),
    )
    |> cantrip.handle_request(ctx)
  resp.status |> should.equal(200)
  simulate.read_body(resp)
  |> string.contains("\"level\":null")
  |> should.be_true()
}
