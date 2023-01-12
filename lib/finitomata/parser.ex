defmodule Finitomata.Parser do
  @moduledoc """
  The behaviour, defining the parser to produce _FSM_ out of textual representation.
  """

  alias Finitomata.Transition

  @typedoc """
  The type representing the parsing error which might be passed through to raised `CompileError`.
  """
  @type parse_error ::
          {:error, String.t(), binary(), map(), {pos_integer(), pos_integer()}, pos_integer()}

  @doc """
  Parse function, producing the _FSM_ definition as a list of `Transition` instances.
  """
  @callback parse(binary()) ::
              {:ok, [Transition.t()]} | {:error, Finitomata.validation_error()} | parse_error()

  @doc """
  Validation of the input.
  """
  @callback validate([{:transition, [binary()]}]) ::
              {:ok, [Transition.t()]} | {:error, Finitomata.validation_error()}

  @doc """
  Linter of the input, producing a well-formed representation of _FSM_ understood by JS/markdown parsers.
  """
  @callback lint(binary()) :: binary()
end
