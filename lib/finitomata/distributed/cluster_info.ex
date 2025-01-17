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

  @doc "
  Returns nodes available to select from for the given `Finitomata` instance.

  If the instance is `false`, should return all the nodes for all instances."
  @callback nodes(Finitomata.id()) :: [node()]

  @doc "Returns the node “selected” for this particular `id`"
  @callback whois(id :: term()) :: node() | nil

  @doc "Call this function to select an implementation of a cluster lookup"
  def init(impl),
    do: :persistent_term.put(Finitomata.ClusterInfo, %{implementation: impl})

  @doc "Delegates to the selected implementation of a cluster lookup"
  def nodes(id \\ false, self? \\ false)
  def nodes(true, false), do: [node() | nodes(false, false)]
  def nodes(id, false), do: impl().nodes(id)
  def nodes(id, true), do: [node() | nodes(id, false)]

  @doc "Delegates to the selected implementation of a cluster lookup"
  def whois(fini_id \\ false, id), do: impl().whois(fini_id, id)

  defp impl do
    Finitomata.ClusterInfo
    |> :persistent_term.get(%{implementation: Finitomata.ClusterInfo.Naive})
    |> Map.get(:implementation)
  end
end
