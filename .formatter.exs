locals_without_parens = [
  assert_payload: 1,
  assert_state: 1,
  assert_transition: 5,
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
