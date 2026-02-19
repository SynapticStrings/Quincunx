defmodule Quincunx.Segment.DependencyAdapter do
  alias Quincunx.Segment, as: S

  @type dependency_field :: atom()
  # In Orchid, it's Orchid.Param.t()
  @type dependency_value :: any()
  @type snapshot :: %{dependency_field() => dependency_value()}

  @type dependency_identifier :: any()

  @callback build_blank_inputs(dependency_identifier()) :: any()

  @callback get_minimal_recipe(dependency_identifier(), snapshot(), S.Diff.t()) ::
              {:ok, any()} | {:error, term()}
end
