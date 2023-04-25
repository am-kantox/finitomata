locals_without_parens = [
  assert_payload: 1,
  assert_state: 1,
  assert_transition: 3,
  assert_transition: 4,
  assert_transition: 5,
  defstate: 1,
  init_finitomata: 3,
  init_finitomata: 4,
  init_finitomata: 5,
  setup_finitomata: 1,
  test_path: 2,
  test_path: 3,
  test_path: 5,
  test_path: 6,
  test_path: 7
]

[
  import_deps: [:stream_data, :nimble_parsec],
  inputs: ["mix.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
