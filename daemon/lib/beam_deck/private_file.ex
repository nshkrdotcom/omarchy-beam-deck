defmodule BeamDeck.PrivateFile do
  @moduledoc "Private atomic writes with exclusive temporary files and symlink refusal."
  def directory(path) do
    with :ok <- File.mkdir_p(path), {:ok, %{type: :directory}} <- File.lstat(path),
         :ok <- File.chmod(path, 0o700), do: :ok
  end
  def write(path, bytes) when is_binary(bytes) do
    tmp = path <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
    with :ok <- directory(Path.dirname(path)), :ok <- regular_or_missing(path) do
      owner = self()
      guard = spawn(fn ->
        ref = Process.monitor(owner)
        receive do
          :finished -> Process.demonitor(ref, [:flush])
          {:DOWN, ^ref, :process, ^owner, _} ->
            File.rm(tmp)
            Process.sleep(50)
            File.rm(tmp)
        end
      end)
      result = with {:ok, io} <- File.open(tmp, [:write, :binary, :exclusive]) do
        try do
          with :ok <- File.chmod(tmp, 0o600), :ok <- IO.binwrite(io, bytes),
               :ok <- :file.sync(io), :ok <- File.close(io),
               :ok <- regular_or_missing(path), :ok <- File.rename(tmp, path), do: :ok
        after
          File.close(io)
        end
      end
      File.rm(tmp)
      send(guard, :finished)
      result
    end
  end
  defp regular_or_missing(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} -> :ok
      {:error, :enoent} -> :ok
      _ -> {:error, :unsafe_file}
    end
  end
end
