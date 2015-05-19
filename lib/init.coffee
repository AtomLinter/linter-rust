module.exports =
  config:
    executablePath:
      type: 'string'
      default: 'rustc'
      description: 'Path to rust compiller'
    cargoManifestFilename:
      type: 'string'
      default: 'Cargo.toml'
      description: 'Cargo manifest filename'
    lintOnChange:
      type: 'boolean'
      default: true
      description: 'Lint file on change (experimental)'

  activate: ->
    console.log 'Linter-Rust: package loaded,
                 ready to get initialized by AtomLinter.'
