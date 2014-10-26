module.exports =
  config:
    executablePath:
      type: 'string'
      default: 'rustc'
      description: 'Path to rust compiller.'

  activate: ->
    console.log 'Linter-Rust: package loaded,
                 ready to get initialized by AtomLinter.'
