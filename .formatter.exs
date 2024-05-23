locals_without_parens = [
  assert_payload: 1,
  assert_state: 1,
  assert_state: 2,
  assert_transition: 3,
  defstate: 1,
  setup_finitomata: 1,
  shape: 1,
  test_path: 2,
  test_path: 3
]

[
  import_deps: [:stream_data, :nimble_parsec],
  inputs: ["mix.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
