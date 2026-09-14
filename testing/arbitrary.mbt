///|
fn arb_token(rs : @quickcheck.RandomState, prefix : String) -> String {
  prefix + rs.next_uint(limit=1000).to_string()
}

///|
/// A generator for `Selection` values (normalised, up to three items).
pub fn arbitrary_selection(
  size : Int,
  rs : @quickcheck.RandomState,
) -> @strata.Selection {
  let n = rs.next_uint(limit=6).reinterpret_as_int()
  if n == 0 {
    return @strata.Selection::all()
  }
  if n == 1 {
    return @strata.Selection::none()
  }
  if n == 2 {
    return @strata.Selection::stream(
      @strata.StreamId::of(
        category=arb_token(rs, "cat"),
        id=arb_token(rs, "id"),
      ),
    )
  }
  if n == 3 {
    let tenant = if rs.next_uint(limit=2) == 0 {
      None
    } else {
      Some(arb_token(rs, "t"))
    }
    return match tenant {
      Some(t) => @strata.Selection::category(arb_token(rs, "cat"), tenant=t)
      None => @strata.Selection::category(arb_token(rs, "cat"))
    }
  }
  let parts : Array[@strata.Selection] = []
  let count = 1 + rs.next_uint(limit=3).reinterpret_as_int()
  for _ in 0..<count {
    if rs.next_uint(limit=2) == 0 {
      parts.push(@strata.Selection::tags([arbitrary_tag(size, rs)]))
    } else {
      parts.push(@strata.Selection::types([arb_token(rs, "T")]))
    }
  }
  @strata.Selection::any_of(parts)
}

///|
/// A generator for `Env` values.
pub fn arbitrary_env(size : Int, rs : @quickcheck.RandomState) -> @strata.Env {
  ignore(size)
  let tenant = if rs.next_uint(limit=2) == 0 {
    None
  } else {
    Some(arb_token(rs, "t"))
  }
  let actor = @strata.Actor(arb_token(rs, "user:"))
  let now = @strata.Instant(rs.next_uint(limit=1_000_000).to_int64())
  match tenant {
    Some(t) => @strata.Env(actor~, now~, tenant=t, extra=Json::null())
    None => @strata.Env(actor~, now~, extra=Json::null())
  }
}

///|
/// A generator for user tags (never system tags).
pub fn arbitrary_tag(size : Int, rs : @quickcheck.RandomState) -> @strata.Tag {
  ignore(size)
  @strata.Tag::kv(key=arb_token(rs, "k"), value=arb_token(rs, "v"))
}
