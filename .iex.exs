"~/.iex.code/*.ex" |> Path.expand() |> Path.wildcard() |> Enum.each(&Code.require_file/1)
global_settings = Path.expand("~/.iex.exs")
if File.exists?(global_settings), do: Code.eval_file(global_settings)

# IEx.configure(inspect: [limit: :infinity])

alias Finitomata.{Manager, Supervisor, Transition}
alias Finitomata.Test.Log, as: L
require L
alias Finitomata.Test.Sequenced, as: S
require S
alias Finitomata.Test.Transition, as: T
require T
