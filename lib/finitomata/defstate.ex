defmodule Finitomata.Defstate do
  @moduledoc false
  defmacro defstate({:%{}, _, _} = definition) do
    quote do
      use Estructura.Nested

      shape(unquote(definition))
    end
  end
end
