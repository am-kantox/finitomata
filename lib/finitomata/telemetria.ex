case {Application.compile_env(:finitomata, :telemetria, false), Code.ensure_compiled(Telemetria)} do
  {false, _} ->
    defmodule Telemetria.Wrapper do
      @moduledoc false
      defmacro __using__(_opts \\ []) do
        quote do
          Module.register_attribute(__MODULE__, :telemetria, accumulate: true, persist: true)
        end
      end

      def telemetria?(_, _), do: false
    end

  {_, {:error, error}} ->
    IO.warn("""
      Telemetria has been requested, but it cannot be found (:#{error}).
      Please add `{:telemetria, "~> ..."}` to the `deps` section of `mix.exs`.
    """)

    raise CompileError, description: "Unavailable module: `Telemetria`"

  {settings, {:module, Telemetria}} ->
    defmodule Telemetria.Wrapper do
      @moduledoc false
      defmacro __using__(opts \\ []) do
        quote do
          use Telemetria, unquote(opts)
        end
      end

      @settings settings

      case settings do
        true ->
          def telemetria?(_module, _function), do: @settings

        list when is_list(list) ->
          def telemetria?(_module, function), do: function in @settings

        map when is_map(map) ->
          def telemetria?(module, function) do
            case Map.get(@settings, module, false) do
              true -> true
              list when is_list(list) -> function in list
              _ -> false
            end
          end
      end
    end
end
