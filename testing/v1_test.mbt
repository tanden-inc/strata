///|
test "advice_law accepts pure advice and rejects advice with hidden inputs" {
  @testing.advice_law(counter, histories=[[], [Added(9)]], commands=[
    Add(1),
    Boom,
  ])
  let calls : Ref[Int] = { val: 0, }
  let impure : @strata.Decider[Cmd, Ev, Int, String] = @strata.Decider(
    category="impure",
    initial=0,
    decide=(cmd, _s, _e) => {
      match cmd {
        Add(n) => [Added(n)]
        Boom => raise Kaboom
      }
    },
    evolve=(s, e) => {
      match e {
        Added(n) => s + n
      }
    },
    advise=(_c, _s, _e) => {
      calls.val += 1
      ["call \{calls.val}"]
    },
  )
  let failed = try {
    @testing.advice_law(impure, histories=[[]], commands=[Add(1)])
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}

///|
priv enum UndoEv {
  Entry(id~ : @strata.EventId, code~ : String)
  Undo(of~ : @strata.EventId, tags~ : Array[@strata.Tag])
} derive(Eq, Debug)

///|
let undo : @strata.DcbDecider[Unit, UndoEv, Int, Unit] = @strata.DcbDecider(
  category="undo",
  stream=_ => "x",
  scope=_ => @strata.Selection::all(),
  tags=e => {
    match e {
      Entry(code~, ..) => [@strata.Tag("code:\{code}")]
      Undo(tags~, ..) => tags
    }
  },
  initial=0,
  decide=(_c, _s, _e, _scope) => [],
  evolve=(s, _e, _scope) => s,
)

///|
test "dcb_reversal_law fails when the target is absent or its tags are not carried" {
  let reverses = (e : UndoEv) => {
    match e {
      Undo(of~, ..) => Some(of)
      _ => None
    }
  }
  let identity = (e : UndoEv) => {
    match e {
      Entry(id~, ..) => Some(id)
      _ => None
    }
  }
  // a lawful history passes
  @testing.dcb_reversal_law(undo, reverses~, identity~, histories=[
    [
      Entry(id=@strata.EventId("e1"), code="X"),
      Undo(of=@strata.EventId("e1"), tags=[@strata.Tag("code:X")]),
    ],
  ])
  let absent = try {
    @testing.dcb_reversal_law(undo, reverses~, identity~, histories=[
      [Undo(of=@strata.EventId("missing"), tags=[])],
    ])
    false
  } catch {
    _ => true
  }
  assert_true(absent)
  let leaked = try {
    @testing.dcb_reversal_law(undo, reverses~, identity~, histories=[
      [
        Entry(id=@strata.EventId("e1"), code="X"),
        Undo(of=@strata.EventId("e1"), tags=[@strata.Tag("code:Y")]),
      ],
    ])
    false
  } catch {
    _ => true
  }
  assert_true(leaked)
}

///|
test "generated selections normalise and round-trip" {
  let state = @splitmix.new(seed=7)
  let mut saw_stream = false
  for i in 0..<100 {
    let sel = @testing.arbitrary_selection(i % 20, state)
    assert_eq(@strata.Selection::any_of([sel]), sel)
    let back : @strata.Selection = @json.from_json(Json(sel))
    assert_eq(back, sel)
    if sel.single_stream() is Some(_) {
      saw_stream = true
    }
  }
  assert_true(saw_stream)
  for i in 0..<100 {
    assert_false(@testing.arbitrary_tag(i % 10, state).is_system())
  }
  let env = @testing.arbitrary_env(10, state)
  assert_true(env.ids.high_water() == -1)
}
