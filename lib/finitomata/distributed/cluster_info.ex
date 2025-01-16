defmodule Finitomata.ClusterInfo do
  @moduledoc """
  The behaviour to be implemented for locating the node across the cluster.

  `Infinitomata` comes with a default naïve implementation, which simply responds
    with a determined random value for `whois/1` and with all visible nodes list
    for `nodes/0`.

  The call to `Finitomata.ClusterInfo.init/1` passing the module implementing
    the desired behaviour is mandatory before any call to `Infinitomata.start_fsm/4`
    to preserve a determined consistency.
  """

  @doc "Returns nodes available to select from"
  @callback nodes :: [node()]

  @doc "Returns the node “selected” for this particular `id`"
  @callback whois(id :: term()) :: node() | nil

  @doc "Call this function to select an implementation of a cluster lookup"
  def init(impl),
    do: :persistent_term.put(Finitomata.ClusterInfo, %{implementation: impl})

  @doc "Delegates to the selected implementation of a cluster lookup"
  def nodes(self? \\ false)
  def nodes(false), do: impl().nodes()
  def nodes(true), do: [node() | nodes(false)]

  @doc "Delegates to the selected implementation of a cluster lookup"
  def whois(id), do: impl().whois(id)

  defp impl do
    Finitomata.ClusterInfo
    |> :persistent_term.get(%{implementation: Finitomata.ClusterInfo.Naive})
    |> Map.get(:implementation)
  end
end
