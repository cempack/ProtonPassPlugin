import QtQuick
import Quickshell.Io
import "Model.js" as Model

// One external command with a watchdog, optional stdin, bounded output and a single
// `finished` result. Starting a new run cancels the previous one; results from a
// cancelled or superseded run are dropped, so callers never see stale output.
Item {
  id: job
  visible: false

  property var environment: ({})
  property int timeoutMs: 45000
  property int maxOutput: 1048576
  // Emit `line` for each stdout line instead of collecting stdout.
  property bool streamLines: false
  // Keep stdin open for the whole run (the child exits when it closes).
  property bool holdStdin: false
  readonly property bool running: _active

  // result: { ok, kind, exitCode, stdout, stderr }
  // kind: "ok" | "timeout" | "launch" | "cancelled" | Model.classifyError(...)
  signal finished(var result)
  signal line(string text)

  property bool _active: false
  property int _generation: 0
  property int _runGeneration: -1
  property int _exitedGeneration: -1
  property string _stdin: ""
  property string _stdout: ""

  function run(command, stdinText) {
    stop()
    _generation += 1
    _runGeneration = _generation
    _stdin = String(stdinText || "")
    _stdout = ""
    _active = true
    proc.stdinEnabled = _stdin !== "" || holdStdin
    proc.command = command
    proc.running = true
    if (timeoutMs > 0) watchdog.restart()
  }

  // Ends the current run without emitting a result.
  function stop() {
    if (!_active) return
    _generation += 1
    _finishRun()
    if (proc.running) {
      proc.signal(15)
      proc.running = false
    }
  }

  function _finishRun() {
    watchdog.stop()
    _active = false
    _stdin = ""
    _stdout = ""
    proc.stdinEnabled = false
  }

  function _complete(gen, result) {
    if (gen !== _generation || !_active) return
    _finishRun()
    finished(result)
  }

  function _append(chunk) {
    var room = Math.max(0, maxOutput - _stdout.length)
    if (room > 0) _stdout += String(chunk || "").slice(0, room)
  }

  Timer {
    id: watchdog
    interval: job.timeoutMs
    repeat: false
    onTriggered: {
      var gen = job._generation
      if (proc.running) {
        proc.signal(9)
        proc.running = false
      }
      job._complete(gen, { ok: false, kind: "timeout", exitCode: 124, stdout: "", stderr: "" })
    }
  }

  Process {
    id: proc
    running: false
    command: []
    environment: job.environment
    stdinEnabled: false

    stdout: SplitParser {
      splitMarker: job.streamLines ? "\n" : ""
      onRead: function(data) {
        if (job.streamLines) job.line(String(data))
        else job._append(data)
      }
    }
    stderr: StdioCollector { id: errors; waitForEnd: true }

    onStarted: {
      if (job._stdin !== "") write(job._stdin)
      job._stdin = ""
      if (!job.holdStdin) stdinEnabled = false
    }
    onRunningChanged: {
      if (running) return
      var gen = job._generation
      // A process that never started exits without `exited`; report it once the
      // event loop settles so a normal exit gets the chance to land first.
      Qt.callLater(function() {
        if (job._exitedGeneration === gen) return
        job._complete(gen, { ok: false, kind: "launch", exitCode: -1, stdout: "", stderr: "" })
      })
    }
    onExited: function(exitCode) {
      var gen = job._generation
      job._exitedGeneration = gen
      Qt.callLater(function() {
        if (gen !== job._generation) return
        var stdout = job._stdout
        var stderr = String(errors.text || "")
        var ok = exitCode === 0
        var kind = ok ? "ok"
          : (exitCode === 124 || exitCode === 137) ? "timeout"
          : Model.classifyError(stderr || stdout, exitCode)
        job._complete(gen, { ok: ok, kind: kind, exitCode: exitCode, stdout: stdout, stderr: stderr })
      })
    }
  }
}
