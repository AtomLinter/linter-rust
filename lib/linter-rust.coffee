linterPath = atom.packages.getLoadedPackage("linter").path
Linter = require "#{linterPath}/lib/linter"

{exec} = require 'child_process'
{log, warn, findFile} = require "#{linterPath}/lib/utils"
fs = require 'fs'
path = require 'path'
tmp = require('tmp')


class LinterRust extends Linter
  @enabled: false
  @syntax: 'source.rust'
  rustcPath: ''
  linterName: 'rust'
  errorStream: 'stderr'
  regex: '(?<file>.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)|(?<info>note)):\\s+(?<message>.+)\n'
  cargoManifestFilename: ''
  dependencyDir: "target/debug/deps"
  tmpFile: null
  lintOnChange: false


  constructor: (@editor) ->
    super @editor
    atom.config.observe 'linter-rust.executablePath', =>
      rustcPath = atom.config.get 'linter-rust.executablePath'
      if rustcPath != @rustcPath
        @enabled = false
        @rustcPath = rustcPath
        exec "\"#{@rustcPath}\" --version", @executionCheckHandler
    atom.config.observe 'linter-rust.cargoManifestFilename', =>
      @cargoManifestFilename = atom.config.get 'linter-rust.cargoMainifestFilename'
    atom.config.observe 'linter-rust.lintOnChange', =>
      @lintOnChange = atom.config.get 'linter-rust.lintOnChange'


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
    @cmd = [@rustcPath, '-Z', 'no-trans', '--color', 'never']
    cargoPath = do @locateCargoManifest
    if cargoPath
      @cmd.push '-L'
      @cmd.push path.join cargoPath, @dependencyDir
    log 'Linter-Rust: initialization completed'


  lintFile: (filePath, callback) =>
    if @enabled
      fileName = path.basename do @editor.getPath
      if @lintOnChange
        cur_dir = path.dirname do @editor.getPath
        @tmpFile = tmp.fileSync {dir: cur_dir, postfix: "-#{fileName}"}
        fs.writeFileSync @tmpFile.name, @editor.getText()
        super @tmpFile.name, callback
      else
        super fileName, callback


  locateCargoManifest: ->
    cur_dir = path.resolve path.dirname do @editor.getPath
    return findFile(cur_dir, @cargoManifestFilename)


  processMessage: (message, callback) ->
    if @tmpFile
      @tmpFile.removeCallback()
      @tmpFile = null
    super message, callback


  formatMessage: (match) ->
    fileName = path.basename do @editor.getPath
    fileNameRE = RegExp "-#{fileName}$"
    type = if match.error then match.error else if match.warning then match.warning else match.info
    if fileNameRE.test(match.file) or fileName == match.file
      "#{type}: #{match.message}"
    else
      "#{type} in #{match.file}: #{match.message}"


module.exports = LinterRust
