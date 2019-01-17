errorModes = require '../lib/mode'
LinterRust = require '../lib/linter-rust'

linter = new LinterRust()

describe "errorModes::OLD_RUSTC::parse", ->
  it "should return 0 messages for an empty string", ->
    expect(errorModes.OLD_RUSTC.parse('', {})).toEqual([])

  it "should properly parse one line error message", ->
    expect(errorModes.OLD_RUSTC.parse('my/awesome file.rs:1:2: 3:4 error: my awesome text\n', {}))
      .toEqual([{
        severity: 'error'
        excerpt: 'my awesome text'
        location:
          file: 'my/awesome file.rs'
          position: [[0, 1], [2, 3]]
      }])

  it "should properly parse one line warning message", ->
    expect(errorModes.OLD_RUSTC.parse('foo:33:44: 22:33 warning: äüö<>\n', {}))
      .toEqual([{
        severity: 'warning',
        excerpt: 'äüö<>'
        location:
          file: 'foo'
          position: [[32, 43], [21, 32]]
      }])

  it "should return messages with a range of at least one character", ->
    editor = atom.workspace.buildTextEditor()
    editor.setText 'fn main() {\nprintln!("Hi test");}\n'
        # expect(editor.getPath()).toContain 'c.coffee'
    expect(errorModes.OLD_RUSTC.parse('foo:1:1: 1:1 error: text\n', {textEditor: editor}))
      .toEqual([{
        severity: 'error'
        excerpt: 'text'
        location:
          file: 'foo'
          position: [[0, 0], [0, 2]]
      }])
    expect(errorModes.OLD_RUSTC.parse('foo:2:1: 2:1 error: text\n', {textEditor: editor}))
      .toEqual([{
        severity: 'error'
        excerpt: 'text'
        location:
          file: 'foo'
          position: [[1, 0], [1, 7]]
      }])

  it "should properly parse multiline messages", ->
    expect(errorModes.OLD_RUSTC.parse('bar:1:2: 3:4 error: line one\n\
                         two\n', {}))
      .toEqual([
        {
          severity: 'error',
          excerpt: 'line one\ntwo',
          location: {
            file: 'bar',
            position: [[0, 1], [2, 3]]
          }
        }
      ])
    expect(errorModes.OLD_RUSTC.parse('bar:1:2: 3:4 error: line one\n\
                         two\n\
                         foo:1:1: 1:2 warning: simple line\n', {}))
      .toEqual([
        {
          severity: 'error',
          excerpt: 'line one\ntwo',
          location: {
            file: 'bar',
            position: [[0, 1], [2, 3]]
          }
        },
        {
          severity: 'warning',
          excerpt: 'simple line',
          location: {
            file: 'foo',
            position: [[0, 0], [0, 1]]
          }
        }
      ])
    expect(errorModes.OLD_RUSTC.parse('bar:1:2: 3:4 error: line one\n\
                         two\n\
                         three\n\
                         foo:1   shouldnt match', {}))
      .toEqual([
        {
          severity: 'error',
          excerpt: 'line one\ntwo\nthree',
          location: {
            file: 'bar',
            position: [[0, 1], [2, 3]]
          }
        }
      ])

  it "should also cope with windows line breaks", ->
    expect(errorModes.OLD_RUSTC.parse('a:1:2: 3:4 error: a\r\nb\n', {})[0].excerpt)
      .toEqual('a\r\nb')

    multi = errorModes.OLD_RUSTC.parse('a:1:2: 3:4 error: a\n\rb\n\rx:1:2: 3:4 error: asd\r\n', {})
    expect(multi[0].excerpt).toEqual('a\n\rb')
    expect(multi[1].excerpt).toEqual('asd')

  it "should not throw an error with extra whitespace in paths", ->
    buildLinterWithWhitespacePath = () ->
      atom.config.set "linter-rust.rustc", "rustc\n"
      atom.config.set "linter-rust.cargo", "cargo\n"
      new LinterRust()

    resetPath = () ->
      atom.config.set "linter-rust.rustc", "rustc"
      atom.config.set "linter-rust.cargo", "cargo"

    expect(buildLinterWithWhitespacePath).not.toThrow()
    resetPath()
