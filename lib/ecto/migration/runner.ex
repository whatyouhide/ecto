defmodule Ecto.Migration.Runner do
  @moduledoc """
  Runner is a gen server that's responsible for running migrations in either `:forward` or `:reverse` directions
  """
  use GenServer

  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  @doc """
  Starts the runner for the specified repo.
  """
  def start_link(repo) do
    GenServer.start_link(__MODULE__, %{direction: :forward, repo: repo}, [name: __MODULE__])
  end

  def handle_call({:direction, direction}, _from, state) do
    {:reply, :ok, %{state | direction: direction}}
  end

  def handle_call({:execute, command}, _from, state=%{direction: :forward, repo: repo}) do
    {:reply, repo.adapter.execute_migration(repo, command), state}
  end

  def handle_call({:execute, command}, _from, state=%{direction: :reverse, repo: repo}) do
    reversed = reverse(command)

    if reversed do
      {:reply, repo.adapter.execute_migration(repo, reversed), state}
    else
      {:reply, :irreversible, state}
    end
  end

  def handle_call({:exists, command}, _from, state=%{direction: direction, repo: repo}) do
    exists = repo.adapter.object_exists?(repo, command)
    response = if direction == :forward, do: exists, else: !exists

    {:reply, response, state}
  end

  @doc """
  Changes the direction to run commands.
  """
  def direction(direction) do
    call {:direction, direction}
  end

  @doc """
  Executes command tuples or strings.
  Ecto.MigrationError will be raised when the server is in `:reverse` direction and `command` is irreversible
  """
  def execute(command) do
    case call {:execute, command} do
      :irreversible -> raise Ecto.MigrationError, message: "Cannot reverse migration command: #{inspect command}"
      response      -> response
    end
  end

  @doc """
  Checks if a column, table or index exists
  """
  def exists?(type, object) do
    call {:exists, {type, object}}
  end

  defp call(message) do
    GenServer.call(__MODULE__, message)
  end

  defp reverse([]),   do: []
  defp reverse([h|t]) do
    if reversed = reverse(h) do
      [reversed|reverse(t)]
    end
  end

  defp reverse({:create, %Table{}=table, _columns}), do: {:drop, table}
  defp reverse({:create, %Index{}=index}),           do: {:drop, index}
  defp reverse({:add,    name, _type, _opts}),       do: {:remove, name}
  defp reverse({:rename, from, to}),                 do: {:rename, to, from}
  defp reverse({:alter,  %Table{}=table, changes}) do
    if reversed = reverse(changes) do
      {:alter, table, reversed}
    end
  end

  defp reverse(_), do: false
end
