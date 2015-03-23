linterPath = atom.packages.getLoadedPackage("linter").path
Linter = require "#{linterPath}/lib/linter"

{exec} = require 'child_process'
{log, warn} = require "#{linterPath}/lib/utils"
fs = require 'fs'
path = require 'path'


class LinterRust extends Linter
  @enabled: false
  @syntax: 'source.rust'
  @rustcPath: ''
  linterName: 'rust'
  errorStream: 'stderr'
  regex: '(.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)|(?<info>note)):\\s+(?<message>.+)\n'

  constructor: (@editor) ->
    super @editor
    atom.config.observe 'linter-rust.executablePath', =>
      rustcPath = atom.config.get 'linter-rust.executablePath'
      if rustcPath != @rustcPath
        @enabled = false
        @rustcPath = rustcPath
        exec "#{@rustcPath} --version", @executionCheckHandler

  executionCheckHandler: (error, stdout, stderr) =>
    versionRegEx = /rustc ([\d\.]+)/
    if not versionRegEx.test(stdout)
      result = if error? then '#' + error.code + ': ' else ''
      result += 'stdout: ' + stdout if stdout.length > 0
      result += 'stderr: ' + stderr if stderr.length > 0
      console.error "Linter-Rust: \"#{@rustcPath}\" was not executable: \
      \"#{result}\". Please, check executable path in the linter settings."
    else
      @enabled = true
      log "Linter-Rust: found rust " + versionRegEx.exec(stdout)[1]
      do @initCmd

  initCmd: =>
    @cmd = "#{@rustcPath} -Z no-trans --color never"
    log 'Linter-Rust: initialization completed'

  lintFile: (filePath, callback) =>
    if @enabled
      origin_file = path.basename do @editor.getPath
      super origin_file, callback

  formatMessage: (match) ->
    type = if match.error then match.error else if match.warning then match.warning else match.info
    "#{type}: #{match.message}"

module.exports = LinterRust
