defmodule Finitomata.ClusterInfo.Naive do
  @moduledoc false
  @behaviour Finitomata.ClusterInfo

  @impl Finitomata.ClusterInfo
  def nodes, do: Node.list()

  @impl Finitomata.ClusterInfo
  def whois(id) do
    {%{next: _next_fun, type: :exsss}, _} = :rand.seed(:exsss, term_to_seed(id))
    Enum.random([node() | nodes()])
  end

  @spec term_to_seed(term(), integer()) :: integer()
  defp term_to_seed(term, default \\ 42)

  defp term_to_seed(term, default) when is_binary(term) do
    term
    |> :binary.encode_hex()
    |> Integer.parse(16)
    |> case do
      {result, _tail} -> result
      :error -> default
    end
  end

  defp term_to_seed({nil, term}, default) when is_binary(term) do
    term_to_seed(term, default)
  end

  defp term_to_seed({id, term}, default) when is_atom(id) and is_binary(term) do
    term_to_seed("#{id}-#{term}", default)
  end

  defp term_to_seed(term, default) do
    :md5
    |> :crypto.hash(:erlang.term_to_binary(term))
    |> term_to_seed(default)
  end
end
