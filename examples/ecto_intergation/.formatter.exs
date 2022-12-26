# Used by "mix format"
[
  import_deps: [:ecto],
  inputs: ["priv/*/seeds.exs", "*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
