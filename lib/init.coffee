module.exports =
  config:
    executablePath:
      type: 'string'
      default: 'rustc'
      description: 'Path to rust compiler'
    executablePath2:
      type: 'string'
      default: 'cargo'
      description: 'Path to rust package manager'

  activate: ->
    console.log 'Linter-Rust: package loaded,
                 ready to get initialized by AtomLinter.'
