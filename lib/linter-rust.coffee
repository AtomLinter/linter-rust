linterPath = atom.packages.getLoadedPackage("linter").path
Linter = require "#{linterPath}/lib/linter"

{exec} = require 'child_process'
{log, warn, findFile} = require "#{linterPath}/lib/utils"
fs = require 'fs'
path = require 'path'

merge = (xs...) ->
  if xs?.length > 0
    tap {}, (m) -> m[k] = v for k, v of x for x in xs

tap = (o, fn) -> fn(o); o

sep = path.delimiter

class LinterRust extends Linter
  regex: '(?<file>.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)|(?<info>note)):\\s+(?<message>.+)\n'
  @syntax: 'source.rust'
  linterName: 'rust'
  errorStream: 'stderr'

  rustHomePath: ''
  rustcPath: ''
  cargoPath: ''
  cargoManifestFilename: ''
  cargoDependencyDir: "target/debug/deps"
  useCargo: true
  jobsNumber: 2

  baseOptions: []
  executionTimeout: 10000


  constructor: (@editor) ->
    super @editor
    atom.config.observe 'linter-rust.rustHome', =>
      @rustHomePath = atom.config.get 'linter-rust.rustHome'
      @rustcPath = @rustHomePath + '/bin/rustc'
      @cargoPath = @rustHomePath + '/bin/cargo'
      exec "\"#{@rustcPath}\" --version", {env: {PATH: @rustHomePath + sep + process.env.path}}, @executionCheckHandler
      exec "\"#{@cargoPath}\" --version", {env: {PATH: @rustHomePath + sep + process.env.path}}, @executionCheckHandler
    atom.config.observe 'linter-rust.cargoManifestFilename', =>
      @cargoManifestFilename = atom.config.get 'linter-rust.cargoManifestFilename'
    atom.config.observe 'linter-rust.useCargo', =>
      @useCargo = atom.config.get 'linter-rust.useCargo'
    atom.config.observe 'linter-rust.jobsNumber', =>
      @jobsNumber = atom.config.get 'jobsNumber'
    atom.config.observe 'linter-rust.executionTimeout', =>
      @executionTimeout = atom.config.get 'linter-rust.executionTimeout'


  executionCheckHandler: (error, stdout, stderr) =>
    executable = if /^rustc/.test stdout then ['rustc', @rustcPath] else ['cargo', @cargoPath]
    versionRegEx = /(rustc|cargo) ([\d\.]+)/
    if not versionRegEx.test stdout
      result = if error? then '#' + error.code + ': ' else ''
      result += 'stdout: ' + stdout if stdout.length > 0
      result += 'stderr: ' + stderr if stderr.length > 0
      console.error "Linter-Rust: \"#{executable[1]}\" was not executable: \
      \"#{result}\". Please, check executable path in the linter settings."
      if 'rustc' == executable[0] then @rustcPath='' else @cargoPath=''
    else
      log "Linter-Rust: found #{executable[0]}"


  initCmd: (editingFile) =>
    cargoManifestPath = do @locateCargoManifest
    if not @cargoPath or not @useCargo or not cargoManifestPath
      @cmd = [@rustcPath, '-Z', 'no-trans', '--color', 'never']
      if cargoManifestPath
        @cmd.push '-L'
        @cmd.push path.join path.dirname(cargoManifestPath), @cargoDependencyDir
      return editingFile
    else
      @cmd = [@cargoPath, 'build', '-j', 2, '--manifest-path']
      return cargoManifestPath


  lintFile: (filePath, callback) =>
    editingFile = @initCmd path.basename do @editor.getPath
    if @rustcPath or (@cargoPath and @useCargo)
      super editingFile, callback


  locateCargoManifest: ->
    cur_dir = path.resolve path.dirname do @editor.getPath
    findFile(cur_dir, @cargoManifestFilename)


  formatMessage: (match) =>
    type = if match.error then match.error else if match.warning then match.warning else match.info
    fileName = path.basename do @editor.getPath
    if match.file isnt fileName
      match.col = match.line = 0
      "#{type} in #{match.file}: #{match.message}"
    else
      "#{type}: #{match.message}"


  beforeSpawnProcess: (command, args, options) =>
    {command: command, args: args, options: merge options, {env: {PATH: @rustHomePath + sep + process.env.PATH}}}

module.exports = LinterRust
