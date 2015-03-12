linterPath = atom.packages.getLoadedPackage("linter").path
Linter = require "#{linterPath}/lib/linter"

{exec} = require 'child_process'
{log, warn, findFile} = require "#{linterPath}/lib/utils"
path = require 'path'


class LinterRust extends Linter
  @enable: false
  @syntax: 'source.rust'
  @cargoPath: 'cargo'
  @cargoManifestPath: null
  linterName: 'rust'
  errorStream: 'stderr'
  regex: '^(?<file>.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)):\\s+(?<message>.+)\n'

  constructor: (@editor) ->
    super @editor
    atom.config.observe 'linter-rust.executablePath', =>
      @executablePath = atom.config.get 'linter-rust.executablePath'
      exec "#{@executablePath} --version", @executionCheckHandler
    atom.config.observe 'linter-rust.executablePath2', =>
      @cargoPath = atom.config.get 'linter-rust.executablePath2'

  executionCheckHandler: (error, stdout, stderr) =>
    versionRegEx = /(rustc|cargo) ([\d\.]+)/
    if not versionRegEx.test(stdout)
      result = if error? then '#' + error.code + ': ' else ''
      result += 'stdout: ' + stdout if stdout.length > 0
      result += 'stderr: ' + stderr if stderr.length > 0
      console.error "Linter-Rust: \"#{@executablePath}\" was invalid: \
      \"#{result}\". Please, check executable path in the linter settings."
    else
      @enabled = true
      log "Linter-Rust: found " + stdout
      log 'Linter-Rust: initialization completed'

  initCmd: (editing_file) =>
    # search for Cargo.toml in container directoies
    dir = path.dirname editing_file
    @cargoManifestPath = findFile(dir, "Cargo.toml")
    if @cargoManifestPath
      log "found Cargo.toml: #{@cargoManifestPath}"
      @cmd = "cargo build"
      @cwd = path.dirname @cargoManifestPath
    else
      @cmd = "rustc -Z no-trans --color never"
      @cwd = path.dirname editing_file

  lintFile: (filePath, callback) =>
    if not @enabled
      return
    # filePath is in tmp dir, not the real one that user is editing
    editing_file = @editor.getPath()
    @initCmd editing_file
    if @cargoManifestPath
      super(editing_file, callback)
    else
      super(filePath, callback)

  beforeSpawnProcess: (command, args, options) =>
    # is there a Cargo.toml file?
    if @cargoManifestPath
      return {
        command: @cargoPath, # we build package using cargo
        args: args[0..-2],   # remove the last .rs file that Linter always appends
        options: options     # keep it as is
      }
    else
      # we compile .rs file using rustc
      return { command: command, args: args, options:options }

  formatMessage: (match) ->
    type = if match.error then match.error else match.warning
    "#{type}: #{match.message}"

module.exports = LinterRust
