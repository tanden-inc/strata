///|
async test "destroyed keys stay destroyed" {
  let keys = @store.MemoryKeyStore()
  keys.key_for("acc-1") |> ignore
  keys.destroy("acc-1")
  let gone = try {
    keys.unseal("acc-1", capability="auditor") |> ignore
    false
  } catch {
    @store.KeyDestroyed(..) => true
    e => raise e
  }
  assert_true(gone)
  let gone_for_reads = try {
    keys.key_for("acc-1") |> ignore
    false
  } catch {
    @store.KeyDestroyed(..) => true
    e => raise e
  }
  assert_true(gone_for_reads)
}

///|
async test "sealed keys are withheld from ordinary reads and every unseal is recorded" {
  let keys = @store.MemoryKeyStore()
  let key = keys.key_for("s")
  keys.seal("s")
  let withheld = try {
    keys.key_for("s") |> ignore
    false
  } catch {
    @store.KeySealed(..) => true
    e => raise e
  }
  assert_true(withheld)
  assert_eq(keys.unseal("s", capability="auditor"), key)
  // unsealing once does not lift the seal
  let still_withheld = try {
    keys.key_for("s") |> ignore
    false
  } catch {
    @store.KeySealed(..) => true
    e => raise e
  }
  assert_true(still_withheld)
  debug_inspect(keys.unseals(), content="[(\"s\", \"auditor\")]")
}

///|
async test "closing a subscription releases a blocked reader" {
  let store = @store.MemoryStore()
  let sub = store.subscribe(@strata.Selection::all(), from=@strata.start)
  let released : Ref[Bool] = { val: false, }
  @async.with_task_group(g => {
    g.spawn_bg(() => {
      let batch = sub.next(timeout=@strata.Duration::seconds(30))
      assert_eq(batch.length(), 0)
      released.val = true
    })
    @async.sleep(10)
    sub.close()
  })
  assert_true(released.val)
}
