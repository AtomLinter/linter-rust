linterPath = atom.packages.getLoadedPackage("linter").path

{BufferedProcess} = require 'atom'
{findFile} = require "#{linterPath}/lib/utils"
path = require 'path'
XRegExp = require('xregexp').XRegExp


class LinterRust
  cargoDependencyDir: "target/debug/deps"
  lint_process: null

  lint: (textEditor) =>
    return new Promise (resolve, reject) =>
      results = []
      file = @initCmd do textEditor.getPath
      curDir = path.dirname file
      @cmd.push file
      command = @cmd[0]
      options = {cwd: curDir}
      args = @cmd.slice 1

      stdout = (data) ->
        console.log data if do atom.inDevMode
      stderr = (err) ->
        results.push err
      exit = (code) ->
        return resolve [] unless code is 101
        messages = []
        regex = XRegExp('(?<file>.+):(?<line>\\d+):(?<col>\\d+):\\s*(\\d+):(\\d+)\\s+((?<error>error|fatal error)|(?<warning>warning)|(?<info>note)):\\s+(?<message>.+)\n', '')
        XRegExp.forEach results.join(''), regex, (match) =>
          type = if match.error
            "Error"
          else if match.warning
            "Warning"
          messages.push {
            type: type or 'Warning'
            text: match.message
            filePath: if path.isAbsolute match.file then match.file else path.join curDir, match.file
            range: [
              [match.line - 1, 0],
              [match.line - 1, 0]
            ]
          }
        resolve(messages)

      @lint_process = new BufferedProcess({command, args, options, stdout, stderr, exit})
      @lint_process.onWillThrowError ({error, handle}) ->
        atom.notifications.addError "Failed to run #{command}",
          detail: "#{error.message}"
          dismissable: true
        handle()
        resolve []


  config: (key) ->
      atom.config.get "linter-rust.#{key}"


  initCmd: (editingFile) =>
    cargoManifestPath = findFile editingFile, @config 'cargoManifestFilename'
    rustHome = @config 'rustHome'
    rustcPath = path.join rustHome, 'bin', 'rustc'
    cargoPath = path.join rustHome, 'bin', 'cargo'
    if not cargoPath or not @config('useCargo') or not cargoManifestPath
      @cmd = [rustcPath, '-Z', 'no-trans', '--color', 'never']
      if cargoManifestPath
        @cmd.push '-L'
        @cmd.push path.join path.dirname(cargoManifestPath), @cargoDependencyDir
      return editingFile
    else
      @cmd = [cargoPath, 'build', '-j', @config('jobsNumber'), '--manifest-path']
      return cargoManifestPath


module.exports = LinterRust
