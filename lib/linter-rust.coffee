fs = require 'fs'
path = require 'path'
{BufferedProcess} = require 'atom'
XRegExp = require 'xregexp'
spawn = require ('child_process')


class LinterRust
  cargoDependencyDir: "target/debug/deps"
  lintProcess: null
  pattern: XRegExp('(?<file>[^\n\r]+):(?<from_line>\\d+):(?<from_col>\\d+):\\s*\
    (?<to_line>\\d+):(?<to_col>\\d+)\\s+\
    ((?<error>error|fatal error)|(?<warning>warning)|(?<info>note|help)):\\s+\
    (?<message>.+?)[\n\r]+($|(?=[^\n\r]+:\\d+))', 's')

  lint: (textEditor) =>
    return new Promise (resolve, reject) =>
      results = []
      file = @initCmd do textEditor.getPath
      curDir = path.dirname file
      PATH = path.dirname @cmd[0]
      options = JSON.parse JSON.stringify process.env
      options.PATH = PATH + path.delimiter + options.PATH
      options.cwd = curDir
      @cmd.push file
      command = @cmd[0]
      args = @cmd.slice 1

      stdout = (data) ->
        console.log data if do atom.inDevMode
      stderr = (err) ->
        results.push err

      exit = (code) =>
        if code is 101 or code is 0
          messages = @parse results.join('')
          messages.forEach (message) ->
            if !(path.isAbsolute message.filePath)
              message.filePath = path.join curDir, message.filePath
          resolve messages
        else
          resolve []

      @lintProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})
      @lintProcess.onWillThrowError ({error, handle}) ->
        atom.notifications.addError "Failed to run #{command}",
          detail: "#{error.message}"
          dismissable: true
        handle()
        resolve []

  parse: (output) =>
    messages = []
    lastMessage = null
    # An additional flag to show, that the last message was suppressed
    lastMessageDisabled = false
    disabledWarnings = @config 'disabledWarnings'
    # A pointer to this.constructMessage, as it is not available from closure
    constructMessage = @constructMessage
    XRegExp.forEach output, @pattern, (match) ->
      if match.from_col == match.to_col
        match.to_col = parseInt(match.to_col) + 1
      range = [
        [match.from_line - 1, match.from_col - 1],
        [match.to_line - 1, match.to_col - 1]
      ]

      if match.info and (lastMessage or lastMessageDisabled)
        # An additional check to suppress notes/info after suppressed warning
        if not lastMessageDisabled
          lastMessage.trace or= []
          lastMessage.trace.push
            type: "Trace"
            text: match.message
            filePath: match.file
            range: range
      else
        if match.warning and disabledWarnings
          for disabledWarning in disabledWarnings
            # Find a disabled lint in warning message
            if match.message.indexOf(disabledWarning) > 0
              lastMessageDisabled = true
              break
          if not lastMessageDisabled
            messages.push constructMessage match, range
        else
          messages.push constructMessage match, range
          lastMessageDisabled = false

    return messages


  constructMessage: (match, range) ->
    message =
      type: if match.error then "Error" else "Warning"
      text: match.message
      filePath: match.file
      range: range
    message


  config: (key) ->
    atom.config.get "linter-rust.#{key}"


  initCmd: (editingFile) =>
    cargoManifestPath = @locateCargo path.dirname editingFile
    rustcPath = (@config 'rustcPath').trim()
    rustcArgs = switch @config 'rustcBuildTest'
      when true then ['--cfg', 'test', '-Z', 'no-trans', '--color', 'never']
      else ['-Z', 'no-trans', '--color', 'never']
    cargoPath = (@config 'cargoPath').trim()
    cargoArgs = switch @config 'cargoCommand'
      when 'check' then ['check']
      when 'test' then ['test', '--no-run']
      when 'rustc' then ['rustc', '-Zno-trans', '--color', 'never']
      when 'clippy' then ['clippy']
      else ['build']

    if not @config('useCargo') or not cargoManifestPath
      @cmd = [rustcPath]
        .concat rustcArgs
      if cargoManifestPath
        @cmd.push '-L'
        @cmd.push path.join path.dirname(cargoManifestPath), @cargoDependencyDir
      return editingFile
    else
      @cmd = @buildCargoPath cargoPath
        .concat cargoArgs
        .concat ['-j', @config('jobsNumber'), '--manifest-path']
      return cargoManifestPath


  locateCargo: (curDir) =>
    root_dir = if /^win/.test process.platform then /^.:\\$/ else /^\/$/
    cargoManifestFilename = @config 'cargoManifestFilename'
    directory = path.resolve curDir
    loop
      return path.join directory, cargoManifestFilename if fs.existsSync path.join directory, cargoManifestFilename
      break if root_dir.test directory
      directory = path.resolve path.join(directory, '..')
    return false


   buildCargoPath: (cargoPath) =>
     if (@config 'cargoCommand') == 'clippy' and @usingMultirustForClippy()
       return ['multirust','run', 'nightly', 'cargo']
     else
       return [cargoPath]

   usingMultirustForClippy: () =>
     try
       result = spawn.execSync 'multirust --version'
       return result.status == 0
     catch
       return false

module.exports = LinterRust
