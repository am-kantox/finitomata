locals_without_parens = []

[
  import_deps: [:stream_data, :nimble_parsec],
  inputs: ["mix.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
