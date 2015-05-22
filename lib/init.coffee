module.exports =
  config:
    executablePath:
      type: 'string'
      default: 'rustc'
      description: 'Path to rust compiller'
    cargoExecutablePath:
      type: 'string'
      default: 'cargo'
      description: 'Path to Cargo package manager'
    useCargo:
      type: 'boolean'
      default: true
      description: 'Use Cargo if it\'s possible'
    cargoManifestFilename:
      type: 'string'
      default: 'Cargo.toml'
      description: 'Cargo manifest filename'
    jobsNumber:
      type: 'integer'
      default: 2
      description: 'Number of jobs to run Cargo in parallel'
    executionTimeout:
      type: 'integer'
      default: 10000
      description: 'Linting execution timeout'


  activate: ->
    console.log 'Linter-Rust: package loaded,
                 ready to get initialized by AtomLinter.'
