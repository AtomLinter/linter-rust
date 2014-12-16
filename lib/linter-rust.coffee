linterPath = atom.packages.getLoadedPackage("linter").path
Linter = require "#{linterPath}/lib/linter"

{exec} = require 'child_process'
{log, warn, findFile} = require "#{linterPath}/lib/utils"
path = require 'path'


class LinterRust extends Linter
  @enable: false
  @syntax: 'source.rust'
  linterName: 'rust'
  errorStream: 'stderr'
  regex: '^(.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)):\\s+(?<message>.+)\n'

  constructor: (@editor) ->
    super @editor
    atom.config.observe 'linter-rust.executablePath', =>
      @executablePath = atom.config.get 'linter-rust.executablePath'
      exec "#{@executablePath} --version", @executionCheckHandler

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
      # log "Linter-Rust: found rust " + versionRegEx.exec(stdout)[1]
      log "Linter-Rust: found " + stdout
      log 'Linter-Rust: initialization completed'

  initCmd: (editing_file) =>
    # @cmd = "#{@executablePath} --no-trans --color never"
    # @cmd = "#{@executablePath} build --manifest-path"
    dir = path.dirname editing_file
    cargofile = findFile(dir, "Cargo.toml")
    log("find cargofile: ", cargofile)
    if cargofile
      @cwd = path.dirname cargofile
      @cmd = "cargo build --verbose"
    else
      @cwd = path.dirname editing_file
      @cmd = "rustc --no-trans --color never"

  lintFile: (filePath, callback) =>
    if not @enabled
      return
    # filePath is in tmp dir, not the real one user is editing
    editing_file = @editor.getPath()
    log("lintFile", editing_file)
    @initCmd editing_file
    super(editing_file, callback)

  beforeSpawnProcess: (command, args, options) =>
    {
      command: "cargo",  # will be configable as executablePath2?
      args: args[0..-2], # remove the last .rs file, we only need Cargo.toml
      options: options   # keep it as is
    }

  formatMessage: (match) ->
    type = if match.error then match.error else match.warning
    "#{type} #{match.message}"

module.exports = LinterRust
