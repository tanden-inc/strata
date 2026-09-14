///|
/// Runs the store contract against a real database when `STRATA_TEST_PG`
/// is set (for example `postgres://strata:strata@localhost:5432/strata`).
/// Skipped otherwise, so the suite stays runnable without a database.
async test "postgres passes the store contract" {
  match @env.get_env_var("STRATA_TEST_PG") {
    None => println("STRATA_TEST_PG not set; skipping the PostgreSQL contract")
    Some(url) =>
      @testing.contract(make=() => {
        let store = @pg.PgStore::connect(url)
        store.migrate()
        store
      })
  }
}
