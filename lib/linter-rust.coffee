fs = require 'fs'
path = require 'path'

{CompositeDisposable} = require 'atom'
atom_linter = require 'atom-linter'
semver = require 'semver'
XRegExp = require 'xregexp'

errorModes = require './mode'

class LinterRust
  patternRustcVersion: XRegExp('rustc (?<version>1.\\d+.\\d+)(?:(?:-(?:(?<nightly>nightly)|(?<beta>beta.*?))|(?:[^\s]+))? \
                                \\((?:[^\\s]+) (?<date>\\d{4}-\\d{2}-\\d{2})\\))?')
  cargoDependencyDir: "target/debug/deps"

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
      @useWorkspaceManifest = cargoCommand.endsWith('all')

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

    @subscriptions.add atom.config.observe 'linter-rust.allowedToCacheVersions',
    (allowedToCacheVersions) =>
      @allowedToCacheVersions = allowedToCacheVersions

    @subscriptions.add atom.config.observe 'linter-rust.disableExecTimeout',
    (value) =>
      @disableExecTimeout = value

  destroy: ->
    do @subscriptions.dispose

  lint: (textEditor) =>
    @initCmd(textEditor.getPath()).then (result) =>
      [cmd_res, errorMode] = result
      [file, cmd] = cmd_res
      env = JSON.parse JSON.stringify process.env
      curDir = if file? then path.dirname file else __dirname
      cwd = curDir
      command = cmd[0]
      cmdPath = if cmd[0]? then path.dirname cmd[0] else __dirname
      args = cmd.slice 1
      env.PATH = cmdPath + path.delimiter + env.PATH
      editingDir = path.dirname textEditor.getPath()
      cargoWorkspaceManifestFile = @locateCargoWorkspace editingDir
      cargoCrateManifestFile = @locateCargoCrate editingDir

      # we set flags only for intermediate json support
      if errorMode == errorModes.FLAGS_JSON_CARGO
        if !env.RUSTFLAGS? or !(env.RUSTFLAGS.indexOf('--error-format=json') >= 0)
          additional = if env.RUSTFLAGS? then ' ' + env.RUSTFLAGS else ''
          env.RUSTFLAGS = '--error-format=json' + additional

      execOpts =
        env: env
        cwd: cwd
        stream: 'both'
      execOpts.timeout = Infinity if @disableExecTimeout

      Promise.all [atom_linter.exec(command, args, execOpts), cargoWorkspaceManifestFile]
        .then (promiseReturns)  ->
          result = promiseReturns[0]
          cargoWorkspaceManifestFile = promiseReturns[1]

          cargoCrateManifestDir = path.dirname cargoCrateManifestFile
          cargoWorkspaceManifestDir = path.dirname cargoWorkspaceManifestFile

          {stdout, stderr, exitCode} = result
          # first, check if an output says specified features are invalid
          if stderr.indexOf('does not have these features') >= 0
            atom.notifications.addError "Invalid specified features",
              detail: "#{stderr}"
              dismissable: true
            []
          # then, if exit code looks okay, process an output
          else if exitCode is 101 or exitCode is 0
            # in dev mode show message boxes with output
            showDevModeWarning = (stream, message) ->
              atom.notifications.addWarning "Output from #{stream} while linting",
                detail: "#{message}"
                description: "This is shown because Atom is running in dev-mode and probably not an actual error"
                dismissable: true
            if do atom.inDevMode
              showDevModeWarning('stderr', stderr) if stderr
              showDevModeWarning('stdout', stdout) if stdout

            # call a needed parser
            output = errorMode.neededOutput(stdout, stderr)
            messages = errorMode.parse output, {@disabledWarnings, textEditor}

            # correct file paths
            messages.forEach (message) ->
              if !(path.isAbsolute message.location.file)
                message.location.file = path.join curDir, message.location.file if fs.existsSync path.join curDir, message.location.file
                message.location.file = path.join cargoCrateManifestDir, message.location.file if fs.existsSync path.join cargoCrateManifestDir, message.location.file
                message.location.file = path.join cargoWorkspaceManifestDir, message.location.file if fs.existsSync path.join cargoWorkspaceManifestDir, message.location.file
            messages
          else
            # whoops, we're in trouble -- let's output as much as we can
            atom.notifications.addError "Failed to run #{command} with exit code #{exitCode}",
              detail: "with args:\n #{args.join(' ')}\nSee console for more information"
              dismissable: true
            console.log "stdout:"
            console.log stdout
            console.log "stderr:"
            console.log stderr
            []
        .catch (error) ->
          console.log error
          atom.notifications.addError "Failed to run #{command}",
            detail: "#{error.message}"
            dismissable: true
          []

  initCmd: (editingFile) =>
    curDir = if editingFile? then path.dirname editingFile else __dirname
    @locateCargo(curDir).then (cargoManifestPath) =>
      if not @useCargo or not cargoManifestPath
        @decideErrorMode(curDir, 'rustc').then (mode) =>
          mode.buildArguments(this, [editingFile, cargoManifestPath]).then (cmd) ->
            [cmd, mode]
      else
        @decideErrorMode(curDir, 'cargo').then (mode) =>
          mode.buildArguments(this, cargoManifestPath).then (cmd) ->
            [cmd, mode]

  compilationFeatures: (cargo) =>
    if @specifiedFeatures.length > 0
      if cargo
        ['--features', @specifiedFeatures.join(' ')]
      else
        result = []
        cfgs = for f in @specifiedFeatures
          result.push ['--cfg', "feature=\"#{f}\""]
        result

  decideErrorMode: (curDir, commandMode) =>
    # error mode is cached to avoid delays
    if @cachedErrorMode? and @allowedToCacheVersions
      Promise.resolve().then () =>
        @cachedErrorMode
    else
      # current dir is set to handle overrides
      execOpts =
        cwd: curDir
      execOpts.timeout = Infinity if @disableExecTimeout
      atom_linter.exec(@rustcPath, ['--version'], execOpts).then (stdout) =>
        try
          match = XRegExp.exec(stdout, @patternRustcVersion)
          if match
            nightlyWithJSON = match.nightly and match.date > '2016-08-08'
            stableWithJSON = not match.nightly and semver.gte(match.version, '1.12.0')
            canUseIntermediateJSON = nightlyWithJSON or stableWithJSON
            switch commandMode
              when 'cargo'
                canUseProperCargoJSON = (match.nightly and match.date >= '2016-10-10') or
                  (match.beta or not match.nightly and semver.gte(match.version, '1.13.0'))
                if canUseProperCargoJSON
                  errorModes.JSON_CARGO
                # this mode is used only through August till October, 2016
                else if canUseIntermediateJSON
                  errorModes.FLAGS_JSON_CARGO
                else
                  errorModes.OLD_CARGO
              when 'rustc'
                if canUseIntermediateJSON
                  errorModes.JSON_RUSTC
                else
                  errorModes.OLD_RUSTC
          else
            throw Error('rustc returned unexpected result: ' + stdout)
      .then (result) =>
        @cachedErrorMode = result
        result

  locateCargoCrate: (curDir) =>
    root_dir = if /^win/.test process.platform then /^.:\\$/ else /^\/$/
    directory = path.resolve curDir
    loop
      return path.join directory , @cargoManifestFilename if fs.existsSync path.join directory, @cargoManifestFilename
      break if root_dir.test directory
      directory = path.resolve path.join(directory, '..')
    return false

  locateCargoWorkspace: (curDir) =>
    crate_level_manifest = @locateCargoCrate(curDir)
    if @useWorkspaceManifest and @useCargo
      execOpts =
        env: JSON.parse JSON.stringify process.env
        cwd: curDir
        stream: 'both'

      return atom_linter.exec('cargo', ['locate-project', '--workspace', '--manifest-path=' + crate_level_manifest], execOpts)
        .then (result) =>
          {stdout, stderr, exitCode} = result
          json = JSON.parse stdout
          return  json.root
        .catch (error) ->
          return crate_level_manifest
    else
      return crate_level_manifest

  locateCargo: (curDir) =>
    return @locateCargoWorkspace curDir

module.exports = LinterRust
