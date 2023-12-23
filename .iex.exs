global_settings = Path.expand("~/.iex.exs")
if File.exists?(global_settings), do: Code.require_file(global_settings)

IEx.configure(inspect: [limit: :infinity])

alias Finitomata.{Manager, Supervisor, Transition}
alias Finitomata.Test.Log, as: L
require L
alias Finitomata.Test.Sequenced, as: S
require S
alias Finitomata.Test.Transition, as: T
require T
