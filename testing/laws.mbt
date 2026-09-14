///|
/// Replay equals snapshot plus tail: for every split point `k`,
/// `replay(events) == replay_from(replay(events[:k]), events[k:])`.
#callsite(autofill(loc))
pub fn[C, E, S : Eq + Debug, N] replay_law(
  decider : @strata.Decider[C, E, S, N],
  events : Array[E],
  loc~ : SourceLoc,
) -> Unit raise {
  let whole = decider.replay(events.iter())
  for k in 0..<=events.length() {
    let prefix = decider.replay(events[:k].iter())
    let split = decider.replay_from(prefix, events[k:].iter())
    assert_eq(whole, split, loc~)
  }
}

///|
/// Reversals stay inside their target's boundary: for every history and every
/// event that `reverses` names a target for, the reversal's tags include the
/// target's tags. When `restores` is given it is also checked against the
/// state before the target and the state after the reversal.
#callsite(autofill(loc))
#warnings("-unused_trait_bound")
pub fn[C, E : Eq + Debug, S, N] reversal_law(
  decider : @strata.Decider[C, E, S, N],
  reverses~ : (E) -> @strata.EventId?,
  identity~ : (E) -> @strata.EventId?,
  histories~ : Array[Array[E]],
  restores? : (S, S) -> Bool,
  loc~ : SourceLoc,
) -> Unit raise {
  for history in histories {
    check_reversals(
      tags_of=e => decider.tags_of(e),
      replay=(events, through, _around) => {
        let prefix = if through < 0 {
          []
        } else {
          events[:through + 1].to_owned()
        }
        decider.replay(prefix.iter())
      },
      reverses~,
      identity~,
      history~,
      restores?,
      loc~,
    )
  }
}

///|
/// `reversal_law` for a `DcbDecider`. A reversal whose target is not in the
/// history is a failure, not a pass. When `restores` is given, both states
/// are folded within the target's own boundary (a scope owning exactly the
/// target's tags), so a leak from outside that boundary cannot hide a
/// broken reversal.
#callsite(autofill(loc))
#warnings("-unused_trait_bound")
pub fn[C, E : Eq + Debug, S, N] dcb_reversal_law(
  decider : @strata.DcbDecider[C, E, S, N],
  reverses~ : (E) -> @strata.EventId?,
  identity~ : (E) -> @strata.EventId?,
  histories~ : Array[Array[E]],
  restores? : (S, S) -> Bool,
  loc~ : SourceLoc,
) -> Unit raise {
  for history in histories {
    check_reversals(
      tags_of=e => decider.tags_of(e),
      replay=(events, through, around) => {
        let prefix = if through < 0 {
          []
        } else {
          events[:through + 1].to_owned()
        }
        let tags = match around {
          Some(target) => decider.tags_of(target)
          None => {
            let tags : Array[@strata.Tag] = []
            for event in prefix {
              for tag in decider.tags_of(event) {
                if tags.contains(tag) == false {
                  tags.push(tag)
                }
              }
            }
            tags
          }
        }
        let scope = if tags.is_empty() {
          @strata.Scope::of(@strata.Selection::all())
        } else {
          @strata.Scope::of(@strata.Selection::tags(tags))
        }
        decider.replay(scope, prefix.iter())
      },
      reverses~,
      identity~,
      history~,
      restores?,
      require_target=true,
      loc~,
    )
  }
}

///|
fn[E, S] check_reversals(
  tags_of~ : (E) -> Array[@strata.Tag],
  replay~ : (Array[E], Int, E?) -> S,
  reverses~ : (E) -> @strata.EventId?,
  identity~ : (E) -> @strata.EventId?,
  history~ : Array[E],
  restores? : (S, S) -> Bool,
  require_target? : Bool = false,
  loc~ : SourceLoc,
) -> Unit raise {
  for i in 0..<history.length() {
    let event = history[i]
    match reverses(event) {
      None => ()
      Some(target_id) => {
        let mut target_idx : Int? = None
        for j in 0..<history.length() {
          if identity(history[j]) == Some(target_id) {
            target_idx = Some(j)
            break
          }
        }
        match target_idx {
          None =>
            if require_target {
              fail(
                "dcb_reversal_law: reversal names a target that is not in the history",
                loc~,
              )
            }
          Some(j) => {
            let target = history[j]
            let target_tags = tags_of(target)
            if require_target && target_tags.is_empty() {
              fail(
                "dcb_reversal_law: reversal names a target that has no boundary",
                loc~,
              )
            }
            let reversal_tags = tags_of(event)
            for tag in target_tags {
              assert_true(reversal_tags.contains(tag), loc~)
            }
            match restores {
              None => ()
              Some(restores) => {
                let before = replay(history, j - 1, Some(target))
                let after = replay(history, i, Some(target))
                assert_true(restores(before, after), loc~)
              }
            }
          }
        }
      }
    }
  }
}

///|
/// Advice is a pure function of the command and the state: calling `advise`
/// twice over the same history yields equal notices, the notices `run`
/// returns for an accepted command equal a direct `advise` call, and a
/// rejected command yields no notices. Catches advice that reads a clock,
/// a counter or any other hidden input.
#callsite(autofill(loc))
pub fn[C, E, S, N : Eq + Debug] advice_law(
  decider : @strata.Decider[C, E, S, N],
  histories~ : Array[Array[E]],
  commands~ : Array[C],
  loc~ : SourceLoc,
) -> Unit raise {
  for history in histories {
    let spec = spec(decider).given(history)
    for cmd in commands {
      let first = spec.advice(cmd)
      let second = spec.advice(cmd)
      assert_eq(
        first,
        second,
        msg="advice is not a pure function of (cmd, state)",
        loc~,
      )
      match spec.decision(cmd) {
        Ok(decision) => assert_eq(decision.notices, first, loc~)
        Err(_) => assert_eq(first, [], loc~)
      }
    }
  }
}
