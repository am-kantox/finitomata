global_settings = "~/.iex.exs"
if File.exists?(global_settings), do: Code.require_file(global_settings)

alias Finitomata.{Manager, Supervisor}
