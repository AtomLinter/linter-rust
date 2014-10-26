linterPath = atom.packages.getLoadedPackage("linter").path
Linter = require "#{linterPath}/lib/linter"

{exec} = require 'child_process'
{log, warn} = require "#{linterPath}/lib/utils"


class LinterRust extends Linter
  @enable: false
  @cfg: null
  @cmd: ''
  @syntax: 'source.rust'
  linterName: 'rust'
  errorStream: 'stderr'
  regex: '^(.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)):\\s+(?<message>.+)\n'

  constructor: (@editor) ->
    super @editor
    @cfg = atom.config.get('linter-rust')
    @cmd = @cfg['executablePath']
    exec "#{@cmd} --version", @executionCheckHandler

  executionCheckHandler: (error, stdout, stderr) =>
    versionRegEx = /rustc ([\d\.]+)/
    if not versionRegEx.test(stdout)
      result = if error? then '#' + error.code + ': ' else ''
      result += 'stdout: ' + stdout if stdout.length > 0
      result += 'stderr: ' + stderr if stderr.length > 0
      console.error "Linter-Rust: \"#{@cmd}\" was not executable: \
      \"#{result}\". Please, check executable path in the linter settings."
    else
      @enabled = true
      log "Linter-Rust: found rust " + versionRegEx.exec(stdout)[1]
      do @initCmd

  initCmd: =>
    @cmd = "#{@cmd} --no-trans --color never"
    log 'Linter-Rust: initialization completed'

  lintFile: (filePath, callback) =>
    if @enabled
      super filePath, callback
    else
      @processMessage "", callback

  formatMessage: (match) ->
    type = if match.error then match.error else match.warning
    "#{type} #{match.message}"

module.exports = LinterRust
