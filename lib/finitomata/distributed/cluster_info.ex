defmodule Finitomata.ClusterInfo do
  @moduledoc false
  @callback nodes :: [node()]
  @callback whois([node()]) :: node()
end
