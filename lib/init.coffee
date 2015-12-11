{CompositeDisposable} = require 'atom'

module.exports =
  config:
    useCargo:
      type: 'boolean'
      default: true
      description: "Use Cargo if it's possible"
    rustcPath:
      type: 'string'
      default: 'rustc'
      description: "Path to Rust's compiler `rustc`"
    rustcBuildTest:
      type: 'boolean'
      default: false
      description: "Lint test code, when using `rustc`"
    cargoPath:
      type: 'string'
      default: 'cargo'
      description: "Path to Rust's package manager `cargo`"
    cargoCommand:
      type: 'string'
      default: 'build'
      enum: ['build', 'check', 'test', 'rustc']
      description: "Use 'check' for fast linting (you need to install
        `cargo-check`). Use 'test' to lint test code, too.
        Use 'rustc' for fast linting (note: does not build
        the project)."
    cargoManifestFilename:
      type: 'string'
      default: 'Cargo.toml'
      description: 'Cargo manifest filename'
    jobsNumber:
      type: 'integer'
      default: 2
      enum: [1, 2, 4, 6, 8, 10]
      description: 'Number of jobs to run Cargo in parallel'

  activate: ->
    console.log 'Linter-Rust: package loaded,
                ready to get initialized by AtomLinter.'

    if not atom.packages.getLoadedPackage 'linter'
      atom.notifications.addError 'Linter package not found',
      detail: '[linter-rust] `linter` package not found. \
      Please install https://github.com/AtomLinter/Linter'

    if not atom.packages.getLoadedPackage 'language-rust'
      atom.notifications.addError 'Language-rust package not found',
      detail: '[linter-rust] `language-rust` package not found. \
      Please install https://github.com/zargony/atom-language-rust'

    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'linter-rust.rustcPath', (rustcPath) =>
      @rustcPath = rustcPath

    @subscriptions.add atom.config.observe 'linter-rust.rustcBuildTest', (rustcBuildTest) =>
      @rustcBuildTest = rustcBuildTest

    @subscriptions.add atom.config.observe 'linter-rust.cargoPath', (cargoPath) =>
      @cargoPath = cargoPath

    @subscriptions.add atom.config.observe 'linter-rust.cargoPath', (cargoCommand) =>
      @cargoCommand = cargoCommand

    @subscriptions.add atom.config.observe 'linter-rust.useCargo', (useCargo) =>
      @useCargo = useCargo

    @subscriptions.add atom.config.observe 'linter-rust.cargoManifestFilename', (cargoManifestFilename) =>
      @cargoManifestFilename = cargoManifestFilename

    @subscriptions.add atom.config.observe 'linter-rust.jobsNumber', (jobsNumber) =>
      @jobsNumber = jobsNumber

  deactivate: ->
    @subscriptions.dispose()


  provideLinter: ->
    LinterRust = require('./linter-rust')
    @provider = new LinterRust()
    return {
      name: 'Rust'
      grammarScopes: ['source.rust']
      scope: 'project'
      lint: @provider.lint
      lintOnFly: false
    }
