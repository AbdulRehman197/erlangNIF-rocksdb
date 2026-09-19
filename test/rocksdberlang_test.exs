defmodule RocksdberlangTest do
  use ExUnit.Case

  @temp_db_path "test_tmp_rocksdb"

  setup do
    on_exit(fn ->
      Rocksdberlang.destroy(@temp_db_path)
    end)
    :ok
  end

  test "basic put, get, has_key?, delete operations" do
    {:ok, db} = Rocksdberlang.open(@temp_db_path, create_if_missing: true)

    assert Rocksdberlang.is_empty?(db) == true
    assert Rocksdberlang.has_key?(db, "user:1") == false

    assert :ok = Rocksdberlang.put(db, "user:1", "Alice")
    assert Rocksdberlang.has_key?(db, "user:1") == true
    assert {:ok, "Alice"} = Rocksdberlang.get(db, "user:1")
    assert Rocksdberlang.get!(db, "user:1") == "Alice"

    assert :not_found = Rocksdberlang.get(db, "nonexistent")
    assert Rocksdberlang.get!(db, "nonexistent", "fallback") == "fallback"

    assert :ok = Rocksdberlang.delete(db, "user:1")
    assert Rocksdberlang.has_key?(db, "user:1") == false
    assert :not_found = Rocksdberlang.get(db, "user:1")

    assert :ok = Rocksdberlang.close(db)
  end

  test "atomic write_batch" do
    {:ok, db} = Rocksdberlang.open(@temp_db_path)

    ops = [
      {:put, "k1", "v1"},
      {:put, "k2", "v2"},
      {:put, "k3", "v3"}
    ]
    assert :ok = Rocksdberlang.write_batch(db, ops)

    assert Rocksdberlang.get!(db, "k1") == "v1"
    assert Rocksdberlang.get!(db, "k2") == "v2"
    assert Rocksdberlang.get!(db, "k3") == "v3"

    assert :ok = Rocksdberlang.write_batch(db, [{:delete, "k2"}, {:put, "k1", "v1_updated"}])
    assert Rocksdberlang.get!(db, "k1") == "v1_updated"
    assert Rocksdberlang.get(db, "k2") == :not_found

    assert :ok = Rocksdberlang.close(db)
  end

  test "streaming, first, last, and prefix scans" do
    {:ok, db} = Rocksdberlang.open(@temp_db_path)

    for i <- 1..10 do
      key = "item:" <> String.pad_leading("#{i}", 2, "0")
      val = "Value #{i}"
      :ok = Rocksdberlang.put!(db, key, val)
    end
    :ok = Rocksdberlang.put!(db, "other:key", "Other")

    # first and last
    assert {:ok, {"item:01", "Value 1"}} = Rocksdberlang.first(db)
    assert {:ok, {"other:key", "Other"}} = Rocksdberlang.last(db)

    # stream all
    all_items = Rocksdberlang.stream(db) |> Enum.to_list()
    assert length(all_items) == 11

    # prefix stream
    prefix_items = Rocksdberlang.stream(db, prefix: "item:") |> Enum.to_list()
    assert length(prefix_items) == 10
    assert {"item:01", "Value 1"} = hd(prefix_items)

    # reverse stream
    reverse_items = Rocksdberlang.stream(db, direction: :reverse) |> Enum.take(2)
    assert [{"other:key", "Other"}, {"item:10", "Value 10"}] = reverse_items

    assert :ok = Rocksdberlang.close(db)
  end

  test "with_db automatic resource cleanup" do
    result =
      Rocksdberlang.with_db(@temp_db_path, fn db ->
        Rocksdberlang.put!(db, "safe_key", "safe_val")
        Rocksdberlang.get!(db, "safe_key")
      end)

    assert result == "safe_val"

    # Verify db was closed by opening it again
    {:ok, db} = Rocksdberlang.open(@temp_db_path)
    assert Rocksdberlang.get!(db, "safe_key") == "safe_val"
    assert :ok = Rocksdberlang.close(db)
  end

  test "RocksDB module alias works identically" do
    {:ok, db} = RocksDB.open(@temp_db_path)
    assert :ok = RocksDB.put(db, "alias_key", "alias_val")
    assert {:ok, "alias_val"} = RocksDB.get(db, "alias_key")
    assert :ok = RocksDB.close(db)
  end
end
