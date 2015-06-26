{CompositeDisposable} = require 'atom'

module.exports =
  config:
    rustHome:
      type: 'string'
      default: '/usr/local'
      description: 'Path to Rust\'s home directory. rustc should exist in /bin/rustc from here.'
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
    @subscriptions.add atom.config.observe 'linter-rust.rustHome',
    (rustHome) =>
      @rustHome = rustHome

    @subscriptions.add atom.config.observe 'linter-rust.useCargo',
    (useCargo) =>
      @useCargo = useCargo

    @subscriptions.add atom.config.observe 'linter-rust.cargoManifestFilename',
    (cargoManifestFilename) =>
      @cargoManifestFilename = cargoManifestFilename

    @subscriptions.add atom.config.observe 'linter-rust.jobsNumber',
    (jobsNumber) =>
      @jobsNumber = jobsNumber

  deactivate: ->
    @subscriptions.dispose()


  provideLinter: ->
      LinterRust = require('./linter-rust')
      @provider = new LinterRust()
      return {
        grammarScopes: ['source.rust']
        scope: 'project'
        lint: @provider.lint
        lintOnFly: false
      }
