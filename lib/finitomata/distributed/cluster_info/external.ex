defmodule Finitomata.ClusterInfo.External do
  @moduledoc false

  defmacro __using__(opts \\ []) do
    impl = Keyword.get(opts, :implementation, Finitomata.ClusterInfo.Naive)

    quote do
      @behaviour Finitomata.ClusterInfo

      @impl Finitomata.ClusterInfo
      def init(init_arg) do
        if Code.ensure_loaded?(unquote(impl)) and function_exported?(unquote(impl), :whois, 1),
          do: Finitomata.ClusterInfo.init(unquote(impl)),
          else: :error
      end

      @impl Finitomata.ClusterInfo
      def nodes, do: [node() | Node.list()]

      @impl Finitomata.ClusterInfo
      def whois(id) do
        unquote(impl).whois(id)
      end
    end
  end
end
