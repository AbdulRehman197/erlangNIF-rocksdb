defmodule RocksDB do
  @moduledoc """
  Convenient alias and delegator module for `Rocksdberlang`.

  Allows calling RocksDB using standard capitalization:

      {:ok, db} = RocksDB.open("data_dir")
      RocksDB.put(db, "key", "val")
      {:ok, "val"} = RocksDB.get(db, "key")
      RocksDB.close(db)
  """

  defdelegate open(path, opts \\ [create_if_missing: true]), to: Rocksdberlang
  defdelegate open!(path, opts \\ [create_if_missing: true]), to: Rocksdberlang
  defdelegate open_with_cf(path, db_opts, cf_descriptors), to: Rocksdberlang
  defdelegate close(db), to: Rocksdberlang
  defdelegate with_db(path, opts \\ [create_if_missing: true], fun), to: Rocksdberlang

  defdelegate get(db, key, opts \\ []), to: Rocksdberlang
  defdelegate get(db, cf, key, opts), to: Rocksdberlang
  defdelegate get!(db, key, default \\ nil, opts \\ []), to: Rocksdberlang

  defdelegate put(db, key, value, opts \\ []), to: Rocksdberlang
  defdelegate put(db, cf, key, value, opts), to: Rocksdberlang
  defdelegate put!(db, key, value, opts \\ []), to: Rocksdberlang

  defdelegate delete(db, key, opts \\ []), to: Rocksdberlang
  defdelegate delete(db, cf, key, opts), to: Rocksdberlang
  defdelegate delete!(db, key, opts \\ []), to: Rocksdberlang

  defdelegate has_key?(db, key, opts \\ []), to: Rocksdberlang

  defdelegate write_batch(db, operations, opts \\ []), to: Rocksdberlang
  defdelegate write_batch!(db, operations, opts \\ []), to: Rocksdberlang

  defdelegate stream(db, opts \\ []), to: Rocksdberlang
  defdelegate first(db, opts \\ []), to: Rocksdberlang
  defdelegate last(db, opts \\ []), to: Rocksdberlang
  defdelegate count(db), to: Rocksdberlang
  defdelegate is_empty?(db), to: Rocksdberlang

  defdelegate flush(db, opts \\ []), to: Rocksdberlang
  defdelegate sync_wal(db), to: Rocksdberlang
  defdelegate checkpoint(db, dir), to: Rocksdberlang
  defdelegate get_property(db, property), to: Rocksdberlang
  defdelegate destroy(path, opts \\ []), to: Rocksdberlang
  defdelegate repair(path, opts \\ []), to: Rocksdberlang

  defdelegate snapshot(db), to: Rocksdberlang
  defdelegate release_snapshot(snapshot), to: Rocksdberlang

  defdelegate create_column_family(db, name, opts \\ []), to: Rocksdberlang
  defdelegate drop_column_family(cf), to: Rocksdberlang
  defdelegate list_column_families(path, opts \\ []), to: Rocksdberlang
end
