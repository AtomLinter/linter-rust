fs = require 'fs'
path = require 'path'
spawn = require ('child_process')
semver = require 'semver'
{BufferedProcess, CompositeDisposable} = require 'atom'
XRegExp = require 'xregexp'


pattern = XRegExp(
  '(?<file>[^\n\r]+):(?<from_line>\\d+):(?<from_col>\\d+):\\s*\
  (?<to_line>\\d+):(?<to_col>\\d+)\\s+\
  ((?<error>error|fatal error)|(?<warning>warning)|(?<info>note|help)):\\s+\
  (?<message>.+?)[\n\r]+($|(?=[^\n\r]+:\\d+))', 's'
)
patternRustcVersion = XRegExp(
  'rustc (?<version>1.\\d+.\\d+)(?:(?:-(?<nightly>nightly)|(?:[^\\s]+))? \
  \\((?:[^\\s]+) (?<date>\\d{4}-\\d{2}-\\d{2})\\))?'
)


class LinterRust
  cargoDependencyDir: "target/debug/deps"
  lintProcess: null
  cachedAbleToJsonErrors: null


  constructor: ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'linter-rust.rustcPath',
    (rustcPath) =>
      rustcPath = do rustcPath.trim if rustcPath
      @rustcPath = rustcPath

    @subscriptions.add atom.config.observe 'linter-rust.cargoPath',
    (cargoPath) =>
      @cargoPath = cargoPath

    @subscriptions.add atom.config.observe 'linter-rust.useCargo',
    (useCargo) =>
      @useCargo = useCargo

    @subscriptions.add atom.config.observe 'linter-rust.cargoCommand',
    (cargoCommand) =>
      @cargoCommand = cargoCommand

    @subscriptions.add atom.config.observe 'linter-rust.rustcBuildTest',
    (rustcBuildTest) =>
      @rustcBuildTest = rustcBuildTest

    @subscriptions.add atom.config.observe 'linter-rust.cargoManifestFilename',
    (cargoManifestFilename) =>
      @cargoManifestFilename = cargoManifestFilename

    @subscriptions.add atom.config.observe 'linter-rust.jobsNumber',
    (jobsNumber) =>
      @jobsNumber = jobsNumber

    @subscriptions.add atom.config.observe 'linter-rust.disabledWarnings',
    (disabledWarnings) =>
      @disabledWarnings = disabledWarnings

    @subscriptions.add atom.config.observe 'linter-rust.specifiedFeatures',
    (specifiedFeatures) =>
      @specifiedFeatures = specifiedFeatures


  destroy: ->
    do @subscriptions.dispose


  lint: (textEditor) =>
    return new Promise (resolve, reject) =>
      results = []
      file = @initCmd do textEditor.getPath
      curDir = path.dirname file
      PATH = path.dirname @cmd[0]
      options =
        env: JSON.parse JSON.stringify process.env
      options.env.PATH = PATH + path.delimiter + options.env.PATH
      options.cwd = curDir
      command = @cmd[0]
      args = @cmd.slice 1
      @cachedAbleToJsonErrors = null
      @cachedAbleToJsonErrors = do @ableToJSONErrors

      stdout = (data) ->
        console.log data if do atom.inDevMode
      stderr = (err) ->
        if err.indexOf('does not have these features') >= 0
          atom.notifications.addError "Invalid specified features",
            detail: "#{err}"
            dismissable: true
        else
          if do atom.inDevMode
            atom.notifications.addWarning "Output from stderr while linting",
              detail: "#{err}"
              description: "This is shown because Atom is running in dev-mode and probably not an actual error"
              dismissable: true
        results.push err

      exit = (code) =>
        if code is 101 or code is 0
          unless do @ableToJSONErrors
            messages = @parse results.join('')
          else
            messages = @parseJSON results
          messages.forEach (message) ->
            if !(path.isAbsolute message.filePath)
              message.filePath = path.join curDir, message.filePath
          resolve messages
        else
          resolve []

      if do @ableToJSONErrors
        additional = if options.env.RUSTFLAGS? then ' ' + options.env.RUSTFLAGS else ''
        options.env.RUSTFLAGS = '--error-format=json' + additional
      @lintProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})
      @lintProcess.onWillThrowError ({error, handle}) ->
        atom.notifications.addError "Failed to run #{command}",
          detail: "#{error.message}"
          dismissable: true
        handle()
        resolve []


  parseJSON: (results) =>
    elements = []
    for result in results
      subresults = result.split '\n'
      for result in subresults
        if result.startsWith '{'
          input = JSON.parse result
          continue unless input.spans
          primary_span = input.spans.find (span) -> span.is_primary
          continue unless primary_span
          range = [
            [primary_span.line_start - 1, primary_span.column_start - 1],
            [primary_span.line_end - 1, primary_span.column_end - 1]
          ]
          input.level = 'error' if input == 'fatal error'
          element =
            type: input.level
            message: input.message
            file: primary_span.file_name
            range: range
            children: input.children
          for span in input.spans
            unless span.is_primary
              element.children.push
                message: span.label
                range: [
                  [span.line_start - 1, span.column_start - 1],
                  [span.line_end - 1, span.column_end - 1]
                ]
          elements.push element
    @buildMessages(elements)


  parse: (output) =>
    elements = []
    XRegExp.forEach output, pattern, (match) ->
      if match.from_col == match.to_col
        match.to_col = parseInt(match.to_col) + 1
      range = [
        [match.from_line - 1, match.from_col - 1],
        [match.to_line - 1, match.to_col - 1]
      ]
      level = if match.error then 'error'
      else if match.warning then 'warning'
      else if match.info then 'info'
      else if match.trace then 'trace'
      else if match.note then 'note'
      element =
        type: level
        message: match.message
        file: match.file
        range: range
      elements.push element
    @buildMessages elements


  buildMessages: (elements) =>
    messages = []
    lastMessage = null
    for element in elements
      switch element.type
        when 'info', 'trace', 'note'
          # Add only if there is a last message
          if lastMessage
            lastMessage.trace or= []
            lastMessage.trace.push
              type: "Trace"
              text: element.message
              filePath: element.file
              range: element.range
        when 'warning'
          # If the message is warning and user enabled disabling warnings
          # Check if this warning is disabled
          if @disabledWarnings and @disabledWarnings.length > 0
            messageIsDisabledLint = false
            for disabledWarning in @disabledWarnings
              # Find a disabled lint in warning message
              if element.message.indexOf(disabledWarning) >= 0
                messageIsDisabledLint = true
                lastMessage = null
                break
            if not messageIsDisabledLint
              lastMessage = @constructMessage "Warning", element
              messages.push lastMessage
          else
            lastMessage = @constructMessage "Warning" , element
            messages.push lastMessage
        when 'error', 'fatal error'
          lastMessage = @constructMessage "Error", element
          messages.push lastMessage
    return messages


  constructMessage: (type, element) ->
    message =
      type: type
      text: element.message
      filePath: element.file
      range: element.range
    # children exists only in JSON messages
    if element.children
      message.trace = []
      for children in element.children
        message.trace.push
          type: "Trace"
          text: children.message
          filePath: element.file
          range: children.range or element.range
    message


  initCmd: (editingFile) =>
    rustcArgs = switch @rustcBuildTest
      when true then ['--cfg', 'test', '-Z', 'no-trans', '--color', 'never']
      else ['-Z', 'no-trans', '--color', 'never']
    cargoArgs = switch @cargoCommand
      when 'check' then ['check']
      when 'test' then ['test', '--no-run']
      when 'rustc' then ['rustc', '-Zno-trans', '--color', 'never']
      when 'clippy' then ['clippy']
      else ['build']

    cargoManifestPath = @locateCargo path.dirname editingFile
    if not @useCargo or not cargoManifestPath
      @cmd = [@rustcPath]
        .concat rustcArgs
      if cargoManifestPath
        @cmd.push '-L'
        @cmd.push path.join path.dirname(cargoManifestPath), @cargoDependencyDir
      @cmd = @cmd.concat @compilationFeatures(false)
      @cmd = @cmd.concat [editingFile]
      @cmd = @cmd.concat ['--error-format=json'] if do @ableToJSONErrors
      return editingFile
    else
      @cmd = @buildCargoPath @cargoPath
        .concat cargoArgs
        .concat ['-j', @jobsNumber]
      @cmd = @cmd.concat @compilationFeatures(true)
      @cmd = @cmd.concat ['--manifest-path', cargoManifestPath]
      return cargoManifestPath


  compilationFeatures: (cargo) =>
    if @specifiedFeatures
      if cargo
        ['--features', @specifiedFeatures.join(' ')]
      else
        result = []
        cfgs = for f in @specifiedFeatures
          result.push ['--cfg', "feature=\"#{f}\""]
        result


  ableToJSONErrors: () =>
    return @cachedAbleToJsonErrors if @cachedAbleToJsonErrors?
    result = spawn.execSync @rustcPath + ' --version', {stdio: 'pipe' }
    match = XRegExp.exec result, patternRustcVersion
    if match and match.nightly and match.date > '2016-08-08'
      true
    else if match and not match.nightly and semver.gte(match.version, '1.12.0')
      true
    else
      false


  locateCargo: (curDir) =>
    root_dir = if /^win/.test process.platform then /^.:\\$/ else /^\/$/
    directory = path.resolve curDir
    loop
      return path.join directory, @cargoManifestFilename if fs.existsSync path.join directory, @cargoManifestFilename
      break if root_dir.test directory
      directory = path.resolve path.join(directory, '..')
    return false


   buildCargoPath: (cargoPath) =>
     if @cargoCommand == 'clippy' and @usingMultirustForClippy()
       return ['multirust','run', 'nightly', 'cargo']
     else
       return [cargoPath]


   usingMultirustForClippy: () =>
     try
       result = spawn.execSync 'multirust --version'
       true
     catch
       false

module.exports = LinterRust
