locals_without_parens = [
  attached: 1,
  attached: 2
]

[
  import_deps: [:ecto, :ecto_sql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 150,
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
