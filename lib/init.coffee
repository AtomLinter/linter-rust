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
    cargoPath:
      type: 'string'
      default: 'cargo'
      description: "Path to Rust's package manager `cargo`"
    cargoCommand:
      type: 'string'
      default: 'test all'
      enum: [
          'build'
          'check'
          'check all'
          'check tests'
          'test'
          'test all'
          'rustc'
          'clippy'
      ]
      description:
      """
      - Use `build` to simply compile the code.
      - Use `check` for fast linting.
      - Use `check all` for fast linting of all packages in the project.
      - Use `check tests` to also include `#[cfg(test)]` code in linting.
      - Use 'clippy' to increase amount of available lints (you need to install `clippy`).
      - Use 'test' to run tests (successful tests may lints from showing).
      - Use 'test all' run tests for all packages in the project.
      - Use 'rustc' for linting in Rust pre-1.23.
      """
    cargoManifestFilename:
      type: 'string'
      default: 'Cargo.toml'
      description: 'Cargo manifest filename'
    jobsNumber:
      type: 'integer'
      default: 2
      enum: [1, 2, 4, 6, 8, 10]
      description: 'Number of jobs to run Cargo in parallel'
    disabledWarnings:
      type: 'array'
      default: []
      items:
        type: 'string'
      description: 'Linting warnings to be ignored in editor, separated with commas.'
    specifiedFeatures:
      type: 'array'
      default: []
      items:
        type: 'string'
      description: 'Additional features to be passed, when linting (for example, `secure, html`)'
    rustcBuildTest:
      type: 'boolean'
      default: false
      description: "Lint test code, when using `rustc`"
    allowedToCacheVersions:
      type: 'boolean'
      default: true
      description: "Uncheck this if you need to change toolchains during one Atom session. Otherwise toolchains' versions are saved for an entire Atom session to increase performance."
    disableExecTimeout:
      title: "Disable Execution Timeout"
      type: 'boolean'
      default: false
      description: "By default processes running longer than 10 seconds will be automatically terminated. Enable this option if you are getting messages about process execution timing out."

  activate: ->
    require('atom-package-deps').install 'linter-rust'


  provideLinter: ->
    LinterRust = require('./linter-rust')
    @provider = new LinterRust()
    {
      name: 'Rust'
      grammarScopes: ['source.rust']
      scope: 'project'
      lint: @provider.lint
      lintOnFly: false
    }
