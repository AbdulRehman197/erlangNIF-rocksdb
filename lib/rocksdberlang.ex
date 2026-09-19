defmodule Rocksdberlang do
  @moduledoc """
  Idiomatic Elixir wrapper for RocksDB (`:rocksdb`).

  Provides key-value storage operations, atomic batch writes, streams,
  snapshots, checkpoints, and resource management.

  ## Examples

      # Open a database
      {:ok, db} = Rocksdberlang.open("my_db", create_if_missing: true)

      # Basic Put / Get / Delete
      :ok = Rocksdberlang.put(db, "user:1", "Alice")
      {:ok, "Alice"} = Rocksdberlang.get(db, "user:1")
      :ok = Rocksdberlang.delete(db, "user:1")
      :not_found = Rocksdberlang.get(db, "user:1")

      # Atomic batch write
      :ok = Rocksdberlang.write_batch(db, [
        {:put, "user:1", "Alice"},
        {:put, "user:2", "Bob"},
        {:delete, "user:old"}
      ])

      # Enumerable Stream with prefix scanning
      entries =
        Rocksdberlang.stream(db, prefix: "user:")
        |> Enum.to_list()

      # Automatic cleanup with with_db/3
      Rocksdberlang.with_db("my_db", fn db ->
        Rocksdberlang.put(db, "k", "v")
        Rocksdberlang.get(db, "k")
      end)

      # Close and destroy
      :ok = Rocksdberlang.close(db)
      :ok = Rocksdberlang.destroy("my_db")
  """

  @type db_handle :: reference()
  @type cf_handle :: reference()
  @type key :: binary()
  @type value :: binary()
  @type path :: Path.t() | charlist()
  @type open_opt ::
          {:create_if_missing, boolean()}
          | {:error_if_exists, boolean()}
          | {:paranoid_checks, boolean()}
          | {:max_open_files, integer()}
          | {:write_buffer_size, integer()}
          | {:max_write_buffer_number, integer()}
          | atom()
          | {atom(), any()}
  @type open_opts :: [open_opt()]
  @type read_opts :: keyword()
  @type write_opts :: keyword()
  @type batch_op ::
          {:put, key(), value()}
          | {:put, cf_handle(), key(), value()}
          | {:delete, key()}
          | {:delete, cf_handle(), key()}
          | {:single_delete, key()}
          | {:single_delete, cf_handle(), key()}

  ## Opening and Closing

  @doc """
  Opens a RocksDB database at the specified path.

  ## Options

    * `:create_if_missing` - If true, database will be created if it does not exist (default: `true`).
    * `:error_if_exists` - If true, an error will be returned if the database already exists (default: `false`).
    * `:max_open_files` - Maximum number of open files (default: `-1` which means always keep open).
    * `:write_buffer_size` - Size of a single memtable (in bytes).

  ## Examples

      {:ok, db} = Rocksdberlang.open("my_db")
      {:ok, db} = Rocksdberlang.open("my_db", create_if_missing: true, max_open_files: 1000)
  """
  @spec open(path(), open_opts()) :: {:ok, db_handle()} | {:error, any()}
  def open(path, opts \\ [create_if_missing: true]) do
    :rocksdb.open(to_charlist_path(path), opts)
  end

  @doc """
  Opens a RocksDB database, raising an `ArgumentError` on failure.
  """
  @spec open!(path(), open_opts()) :: db_handle()
  def open!(path, opts \\ [create_if_missing: true]) do
    case open(path, opts) do
      {:ok, db} -> db
      {:error, reason} -> raise "Failed to open RocksDB at #{inspect(path)}: #{inspect(reason)}"
    end
  end

  @doc """
  Opens a RocksDB database with column families.
  """
  @spec open_with_cf(path(), open_opts(), [{binary() | charlist(), open_opts()}]) ::
          {:ok, db_handle(), [cf_handle()]} | {:error, any()}
  def open_with_cf(path, db_opts, cf_descriptors) do
    cf_descriptors_charlist =
      Enum.map(cf_descriptors, fn {name, cf_opts} ->
        {to_charlist_path(name), cf_opts}
      end)

    :rocksdb.open_with_cf(to_charlist_path(path), db_opts, cf_descriptors_charlist)
  end

  @doc """
  Closes the open RocksDB database instance.
  """
  @spec close(db_handle()) :: :ok | {:error, any()}
  def close(db) when is_reference(db) do
    :rocksdb.close(db)
  end

  @doc """
  Safely executes `fun` with an opened database and guarantees it is closed when done.
  """
  @spec with_db(path(), open_opts(), (db_handle() -> result)) :: result when result: var
  def with_db(path, opts \\ [create_if_missing: true], fun) when is_function(fun, 1) do
    db = open!(path, opts)

    try do
      fun.(db)
    after
      close(db)
    end
  end

  ## Basic Operations

  @doc """
  Retrieves the value for the given key from the database.

  Returns `{:ok, value}` if found, `:not_found` if the key does not exist,
  or `{:error, reason}` on error.
  """
  @spec get(db_handle(), key(), read_opts()) :: {:ok, value()} | :not_found | {:error, any()}
  def get(db, key, opts \\ []) when is_reference(db) do
    :rocksdb.get(db, key, opts)
  end

  @doc """
  Retrieves the value for the given key in a specific column family.
  """
  @spec get(db_handle(), cf_handle(), key(), read_opts()) ::
          {:ok, value()} | :not_found | {:error, any()}
  def get(db, cf, key, opts) when is_reference(db) and is_reference(cf) do
    :rocksdb.get(db, cf, key, opts)
  end

  @doc """
  Retrieves the value for the given key, returning `default` if not found,
  or raising on error.
  """
  @spec get!(db_handle(), key(), value() | nil, read_opts()) :: value() | nil
  def get!(db, key, default \\ nil, opts \\ []) when is_reference(db) do
    case get(db, key, opts) do
      {:ok, val} -> val
      :not_found -> default
      {:error, reason} -> raise "RocksDB get error for key #{inspect(key)}: #{inspect(reason)}"
    end
  end

  @doc """
  Stores a key-value pair in the database.
  """
  @spec put(db_handle(), key(), value(), write_opts()) :: :ok | {:error, any()}
  def put(db, key, value, opts \\ []) when is_reference(db) do
    :rocksdb.put(db, key, value, opts)
  end

  @doc """
  Stores a key-value pair in a specific column family.
  """
  @spec put(db_handle(), cf_handle(), key(), value(), write_opts()) :: :ok | {:error, any()}
  def put(db, cf, key, value, opts) when is_reference(db) and is_reference(cf) do
    :rocksdb.put(db, cf, key, value, opts)
  end

  @doc """
  Stores a key-value pair, raising an error on failure.
  """
  @spec put!(db_handle(), key(), value(), write_opts()) :: :ok
  def put!(db, key, value, opts \\ []) when is_reference(db) do
    case put(db, key, value, opts) do
      :ok -> :ok
      {:error, reason} -> raise "RocksDB put error for key #{inspect(key)}: #{inspect(reason)}"
    end
  end

  @doc """
  Deletes a key-value pair from the database.
  """
  @spec delete(db_handle(), key(), write_opts()) :: :ok | {:error, any()}
  def delete(db, key, opts \\ []) when is_reference(db) do
    :rocksdb.delete(db, key, opts)
  end

  @doc """
  Deletes a key-value pair from a specific column family.
  """
  @spec delete(db_handle(), cf_handle(), key(), write_opts()) :: :ok | {:error, any()}
  def delete(db, cf, key, opts) when is_reference(db) and is_reference(cf) do
    :rocksdb.delete(db, cf, key, opts)
  end

  @doc """
  Deletes a key-value pair, raising an error on failure.
  """
  @spec delete!(db_handle(), key(), write_opts()) :: :ok
  def delete!(db, key, opts \\ []) when is_reference(db) do
    case delete(db, key, opts) do
      :ok -> :ok
      {:error, reason} -> raise "RocksDB delete error for key #{inspect(key)}: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if a key exists in the database.
  """
  @spec has_key?(db_handle(), key(), read_opts()) :: boolean()
  def has_key?(db, key, opts \\ []) when is_reference(db) do
    case get(db, key, opts) do
      {:ok, _} -> true
      _ -> false
    end
  end

  ## Batch Writes

  @doc """
  Applies a list of write actions atomically to the database.

  ## Supported Actions

    * `{:put, key, value}`
    * `{:put, cf_handle, key, value}`
    * `{:delete, key}`
    * `{:delete, cf_handle, key}`
    * `{:single_delete, key}`
    * `{:single_delete, cf_handle, key}`

  ## Examples

      :ok = Rocksdberlang.write_batch(db, [
        {:put, "key1", "val1"},
        {:put, "key2", "val2"},
        {:delete, "key3"}
      ])
  """
  @spec write_batch(db_handle(), [batch_op()], write_opts()) :: :ok | {:error, any()}
  def write_batch(db, operations, opts \\ []) when is_reference(db) and is_list(operations) do
    :rocksdb.write(db, operations, opts)
  end

  @doc """
  Applies a list of write actions atomically, raising an error on failure.
  """
  @spec write_batch!(db_handle(), [batch_op()], write_opts()) :: :ok
  def write_batch!(db, operations, opts \\ []) when is_reference(db) and is_list(operations) do
    case write_batch(db, operations, opts) do
      :ok -> :ok
      {:error, reason} -> raise "RocksDB write_batch error: #{inspect(reason)}"
    end
  end

  ## Iteration & Streaming

  @doc """
  Creates a lazy `Stream` of `{key, value}` pairs from the database.

  The stream automatically manages opening and closing of the underlying iterator.

  ## Options

    * `:prefix` - If specified, seeks to the prefix and stops streaming when keys no longer match the prefix.
    * `:start_key` - Key to seek to before starting enumeration.
    * `:direction` - `:forward` (default) or `:reverse`.
    * `:read_options` - Options passed to `:rocksdb.iterator/2`.

  ## Examples

      # Stream all entries
      Rocksdberlang.stream(db)
      |> Enum.take(10)

      # Stream all entries with a given prefix
      Rocksdberlang.stream(db, prefix: "user:")
      |> Enum.to_list()

      # Stream in reverse order
      Rocksdberlang.stream(db, direction: :reverse)
      |> Enum.take(5)
  """
  @spec stream(db_handle(), keyword()) :: Enumerable.t()
  def stream(db, opts \\ []) when is_reference(db) do
    read_opts = Keyword.get(opts, :read_options, [])
    direction = Keyword.get(opts, :direction, :forward)
    prefix = Keyword.get(opts, :prefix)
    start_key = Keyword.get(opts, :start_key)

    Stream.resource(
      fn ->
        case :rocksdb.iterator(db, read_opts) do
          {:ok, itr} ->
            start_action =
              cond do
                prefix != nil -> {:seek, prefix}
                start_key != nil -> {:seek, start_key}
                direction == :reverse -> :last
                true -> :first
              end

            {itr, start_action, direction, prefix}

          {:error, reason} ->
            raise "Failed to initialize RocksDB iterator: #{inspect(reason)}"
        end
      end,
      fn
        nil ->
          {:halt, nil}

        {itr, action, dir, pref} ->
          case :rocksdb.iterator_move(itr, action) do
            {:ok, key, value} ->
              next_action = if dir == :reverse, do: :prev, else: :next

              if pref != nil && !String.starts_with?(key, pref) do
                {:halt, {itr, nil, dir, pref}}
              else
                {[{key, value}], {itr, next_action, dir, pref}}
              end

            {:error, :invalid_iterator} ->
              {:halt, {itr, nil, dir, pref}}

            {:error, _reason} ->
              {:halt, {itr, nil, dir, pref}}
          end
      end,
      fn
        nil -> :ok
        {itr, _, _, _} -> :rocksdb.iterator_close(itr)
      end
    )
  end

  @doc """
  Returns the first `{key, value}` pair in the database, or `:empty` if database has no entries.
  """
  @spec first(db_handle(), read_opts()) :: {:ok, {key(), value()}} | :empty | {:error, any()}
  def first(db, opts \\ []) when is_reference(db) do
    with {:ok, itr} <- :rocksdb.iterator(db, opts) do
      try do
        case :rocksdb.iterator_move(itr, :first) do
          {:ok, k, v} -> {:ok, {k, v}}
          {:error, :invalid_iterator} -> :empty
          {:error, reason} -> {:error, reason}
        end
      after
        :rocksdb.iterator_close(itr)
      end
    end
  end

  @doc """
  Returns the last `{key, value}` pair in the database, or `:empty` if database has no entries.
  """
  @spec last(db_handle(), read_opts()) :: {:ok, {key(), value()}} | :empty | {:error, any()}
  def last(db, opts \\ []) when is_reference(db) do
    with {:ok, itr} <- :rocksdb.iterator(db, opts) do
      try do
        case :rocksdb.iterator_move(itr, :last) do
          {:ok, k, v} -> {:ok, {k, v}}
          {:error, :invalid_iterator} -> :empty
          {:error, reason} -> {:error, reason}
        end
      after
        :rocksdb.iterator_close(itr)
      end
    end
  end

  @doc """
  Returns the approximate count of keys in the database.
  """
  @spec count(db_handle()) :: {:ok, non_neg_integer()} | {:error, any()}
  def count(db) when is_reference(db) do
    :rocksdb.count(db)
  end

  @doc """
  Returns true if the database is empty.
  """
  @spec is_empty?(db_handle()) :: boolean()
  def is_empty?(db) when is_reference(db) do
    :rocksdb.is_empty(db)
  end

  ## Database Maintenance & Administration

  @doc """
  Flushes the database memtable to disk.
  """
  @spec flush(db_handle(), keyword()) :: :ok | {:error, any()}
  def flush(db, opts \\ []) when is_reference(db) do
    :rocksdb.flush(db, opts)
  end

  @doc """
  Syncs the Write-Ahead Log (WAL) to disk.
  """
  @spec sync_wal(db_handle()) :: :ok | {:error, any()}
  def sync_wal(db) when is_reference(db) do
    :rocksdb.sync_wal(db)
  end

  @doc """
  Creates a physical checkpoint of the database at the target directory.
  """
  @spec checkpoint(db_handle(), path()) :: :ok | {:error, any()}
  def checkpoint(db, dir) when is_reference(db) do
    :rocksdb.checkpoint(db, to_charlist_path(dir))
  end

  @doc """
  Retrieves a database property (e.g. `"rocksdb.estimate-num-keys"`, `"rocksdb.stats"`).
  """
  @spec get_property(db_handle(), binary() | charlist()) :: {:ok, binary()} | {:error, any()}
  def get_property(db, property) when is_reference(db) do
    :rocksdb.get_property(db, to_charlist_path(property))
  end

  @doc """
  Destroys the RocksDB database at the specified path.
  """
  @spec destroy(path(), keyword()) :: :ok | {:error, any()}
  def destroy(path, opts \\ []) do
    :rocksdb.destroy(to_charlist_path(path), opts)
  end

  @doc """
  Attempts to repair the RocksDB database at the specified path.
  """
  @spec repair(path(), keyword()) :: :ok | {:error, any()}
  def repair(path, opts \\ []) do
    :rocksdb.repair(to_charlist_path(path), opts)
  end

  ## Snapshots

  @doc """
  Takes a point-in-time snapshot of the database.
  """
  @spec snapshot(db_handle()) :: {:ok, reference()} | {:error, any()}
  def snapshot(db) when is_reference(db) do
    :rocksdb.snapshot(db)
  end

  @doc """
  Releases a previously created snapshot.
  """
  @spec release_snapshot(reference()) :: :ok | {:error, any()}
  def release_snapshot(snapshot) when is_reference(snapshot) do
    :rocksdb.release_snapshot(snapshot)
  end

  ## Column Families

  @doc """
  Creates a new column family in the database.
  """
  @spec create_column_family(db_handle(), binary() | charlist(), keyword()) ::
          {:ok, cf_handle()} | {:error, any()}
  def create_column_family(db, name, opts \\ []) when is_reference(db) do
    :rocksdb.create_column_family(db, to_charlist_path(name), opts)
  end

  @doc """
  Drops an existing column family.
  """
  @spec drop_column_family(cf_handle()) :: :ok | {:error, any()}
  def drop_column_family(cf) when is_reference(cf) do
    :rocksdb.drop_column_family(cf)
  end

  @doc """
  Lists the column families existing in the database at the specified path.
  """
  @spec list_column_families(path(), keyword()) :: {:ok, [binary()]} | {:error, any()}
  def list_column_families(path, opts \\ []) do
    case :rocksdb.list_column_families(to_charlist_path(path), opts) do
      {:ok, cfs} -> {:ok, Enum.map(cfs, &to_string/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Helpers

  defp to_charlist_path(path) when is_binary(path), do: String.to_charlist(path)
  defp to_charlist_path(path) when is_list(path), do: path
end
