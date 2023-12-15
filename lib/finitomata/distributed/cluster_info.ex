defmodule Finitomata.ClusterInfo do
  @moduledoc false
  @callback init(init_arg :: term()) :: :ok | :error
  @callback nodes :: [node()]
  @callback whois(id :: term(), sticky :: boolean()) :: node()

  def init(impl), do: :persistent_term.put(Finitomata.ClusterInfo, %{implementation: impl})
  def nodes, do: [node() | Node.list()]

  def whois(id, sticky \\ true) do
    impl =
      Finitomata.ClusterInfo
      |> :persistent_term.get(%{implementation: Finitomata.ClusterInfo.Naive})
      |> Map.get(:implementation)

    impl.whois(id, sticky)
  end
end
