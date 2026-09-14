///|
async test "unseal never creates a key" {
  let keys = @store.MemoryKeyStore()
  let missing = try {
    keys.unseal("never-seen", capability="auditor") |> ignore
    false
  } catch {
    @store.KeyMissing(..) => true
    e => raise e
  }
  assert_true(missing)
  debug_inspect(keys.unseals(), content="[]")
}

///|
async test "a standalone view store keeps the checkpoints it commits" {
  let views = @store.MemoryViewStore()
  views.commit(
    writes=[],
    checkpoint=@store.Checkpoint(name="p", position=@strata.Position(3)),
  )
  debug_inspect(views.checkpoint("p"), content="Some(Position(3))")
  debug_inspect(views.checkpoint("q"), content="None")
  let store = @store.MemoryStore()
  store
  .views()
  .commit(
    writes=[],
    checkpoint=@store.Checkpoint(name="p", position=@strata.Position(9)),
  )
  debug_inspect(store.load_checkpoint("p"), content="Some(Position(9))")
  debug_inspect(store.views().checkpoint("p"), content="Some(Position(9))")
}
