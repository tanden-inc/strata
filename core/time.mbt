///|
/// A point in time as milliseconds since the Unix epoch (UTC).
///
/// Serialised as an ISO-8601 string (`2026-09-13T00:00:00.000Z`).
pub(all) struct Instant(Int64) derive (
  Eq,
  Compare,
  Hash,
  Debug,
  @quickcheck.Arbitrary,
)

///|
fn is_leap_year(year : Int64) -> Bool {
  year % 4L == 0 && (year % 100L != 0 || year % 400L == 0)
}

///|
fn days_from_civil(year : Int64, month : Int64, day : Int64) -> Int64 {
  let adj = if month <= 2L { 1L } else { 0L }
  let y = year - adj
  let era = if y >= 0L { y / 400L } else { (y - 399L) / 400L }
  let yoe = y - era * 400L
  let mp = if month > 2L { month - 3L } else { month + 9L }
  let doy = (153L * mp + 2L) / 5L + day - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}

///|
fn civil_from_days(z : Int64) -> (Int64, Int64, Int64) {
  let z = z + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  let year_adj = if m <= 2L { 1L } else { 0L }
  (y + year_adj, m, d)
}

///|
fn pad2(n : Int64) -> String {
  n.to_string().pad_start(2, '0')
}

///|
fn pad3(n : Int64) -> String {
  n.to_string().pad_start(3, '0')
}

///|
fn pad4(n : Int64) -> String {
  n.to_string().pad_start(4, '0')
}

///|
fn parse_nat(text : String, start : Int, end : Int) -> Int64? {
  if start >= end {
    return None
  }
  let mut n = 0L
  for i in start..<end {
    let c = text.get_char(i).unwrap()
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10L + (c.to_int() - '0'.to_int()).to_int64()
  }
  Some(n)
}

///|
fn days_in_month(year : Int64, month : Int64) -> Int64 {
  match month {
    1L | 3L | 5L | 7L | 8L | 10L | 12L => 31L
    4L | 6L | 9L | 11L => 30L
    2L => if is_leap_year(year) { 29L } else { 28L }
    _ => 0L
  }
}

///|
/// Parses an ISO-8601 UTC timestamp such as `2026-09-13T00:00:00Z`
/// (fractional seconds optional).
pub fn Instant::parse(text : String) -> Instant raise InvalidInstant {
  if text.length() < 20 || text.get_char(text.length() - 1).unwrap() != 'Z' {
    raise InvalidInstant(text)
  }
  if text.get_char(4).unwrap() != '-' ||
    text.get_char(7).unwrap() != '-' ||
    text.get_char(10).unwrap() != 'T' ||
    text.get_char(13).unwrap() != ':' ||
    text.get_char(16).unwrap() != ':' {
    raise InvalidInstant(text)
  }
  let year = parse_nat(text, 0, 4).unwrap_or(-1L)
  let month = parse_nat(text, 5, 7).unwrap_or(-1L)
  let day = parse_nat(text, 8, 10).unwrap_or(-1L)
  let hour = parse_nat(text, 11, 13).unwrap_or(-1L)
  let minute = parse_nat(text, 14, 16).unwrap_or(-1L)
  let second = parse_nat(text, 17, 19).unwrap_or(-1L)
  if year < 0L ||
    month < 1L ||
    month > 12L ||
    day < 1L ||
    day > days_in_month(year, month) ||
    hour < 0L ||
    hour > 23L ||
    minute < 0L ||
    minute > 59L ||
    second < 0L ||
    second > 59L {
    raise InvalidInstant(text)
  }
  let mut millis = 0L
  if text.length() == 20 {
    ()
  } else if text.get_char(19).unwrap() == '.' && text.length() > 21 {
    let frac = text[20:text.length() - 1]
    if frac.is_empty() || frac.all(c => c is ('0'..='9')) == false {
      raise InvalidInstant(text)
    }
    let padded = (frac.to_owned() + "000")[:3].to_owned()
    millis = parse_nat(padded, 0, 3).unwrap_or(0L)
  } else {
    raise InvalidInstant(text)
  }
  let days = days_from_civil(year, month, day)
  Instant(
    days * 86_400_000L +
    hour * 3_600_000L +
    minute * 60_000L +
    second * 1000L +
    millis,
  )
}

///|
/// Formats as `YYYY-MM-DDTHH:MM:SS.mmmZ`.
pub fn Instant::to_iso8601(self : Instant) -> String {
  let mut ms = self.0
  let mut extra_days = 0L
  if ms < 0L {
    extra_days = (ms - 86_399_999L) / 86_400_000L
    ms = ms - extra_days * 86_400_000L
  }
  let days = extra_days + ms / 86_400_000L
  let rem = ms % 86_400_000L
  let hour = rem / 3_600_000L
  let rem_min = rem % 3_600_000L
  let minute = rem_min / 60_000L
  let rem = rem_min % 60_000L
  let second = rem / 1000L
  let milli = rem % 1000L
  let (year, month, day) = civil_from_days(days)
  "\{pad4(year)}-\{pad2(month)}-\{pad2(day)}T\{pad2(hour)}:\{pad2(minute)}:\{pad2(second)}.\{pad3(milli)}Z"
}

///|
/// This instant plus a duration.
pub fn Instant::add(self : Instant, d : Duration) -> Instant {
  Instant(self.0 + d.0)
}

///|
/// The duration from `earlier` to this instant (negative if `earlier` is later).
pub fn Instant::since(self : Instant, earlier : Instant) -> Duration {
  Duration(self.0 - earlier.0)
}

///|
pub impl Show for Instant with fn to_string(self) {
  self.to_iso8601()
}

///|
pub impl ToJson for Instant with fn to_json(self) {
  Json::string(self.to_iso8601())
}

///|
pub impl @json.FromJson for Instant with fn from_json(json, path) {
  guard json is String(s) else {
    raise @json.JsonDecodeError((path, "Instant: expected an ISO-8601 string"))
  }
  Instant::parse(s) catch {
    InvalidInstant(msg) => raise @json.JsonDecodeError((path, msg))
  }
}

///|
/// A length of time in milliseconds. Serialised as a number.
pub(all) struct Duration(Int64) derive(Eq, Compare, Hash, Debug)

///|
/// `n` milliseconds.
pub fn Duration::millis(n : Int64) -> Duration {
  Duration(n)
}

///|
/// `n` seconds.
pub fn Duration::seconds(n : Int64) -> Duration {
  Duration(n * 1000)
}

///|
/// `n` minutes.
pub fn Duration::minutes(n : Int64) -> Duration {
  Duration(n * 60_000)
}

///|
/// `n` hours.
pub fn Duration::hours(n : Int64) -> Duration {
  Duration(n * 3_600_000)
}

///|
/// The duration in milliseconds.
pub fn Duration::to_millis(self : Duration) -> Int64 {
  self.0
}

///|
pub impl ToJson for Duration with fn to_json(self) {
  Json::number(self.0.to_double())
}

///|
pub impl @json.FromJson for Duration with fn from_json(json, path) {
  guard json is Number(n, ..) else {
    raise @json.JsonDecodeError((path, "Duration: expected a number"))
  }
  Duration(n.to_int64())
}
