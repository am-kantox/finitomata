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

alias Finitomata.Test.Flow.SubFlow1, as: SF
alias Finitomata.Test.Flow, as: F
Finitomata.start_link()
Finitomata.start_fsm(F, "F", %{})
Finitomata.transition("F", :to_s2)
Finitomata.transition({:fork, :s2, "F"}, :start)
# Finitomata.transition({:fork, :s2, "F"}, :finalize)
