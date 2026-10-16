"""Exercise the public CLI against real files/processes and fake capture tools."""
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

COMMAND, RECORDER, STRACE = sys.argv[1:4]
sys.argv[1:] = []


class RecordingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.state = self.runtime / "record-screen"
        self.env = dict(os.environ, HOME=str(self.root), XDG_RUNTIME_DIR=str(self.runtime),
                        RECORD_SCREEN_DIR=str(self.root / "videos"),
                        FAKE_RECORDER_LOG=str(self.root / "launched"))
        self.children = []

    def tearDown(self):
        if (self.root / "launched").exists():
            for raw in (self.root / "launched").read_text().splitlines():
                try:
                    os.kill(int(raw), signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for process in self.children:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=3)
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()
        self.tmp.cleanup()

    def run_cli(self, *args):
        process = self.spawn(*args)
        stdout, stderr = process.communicate(timeout=12)
        return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)

    def spawn(self, *args, prefix=()):
        process = subprocess.Popen([*prefix, COMMAND, *args], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   start_new_session=True)
        self.children.append(process)
        return process

    def wait_file(self, path):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if path.exists():
                return
            time.sleep(0.02)
        self.fail(f"not created: {path}")

    def read_event(self, process):
        self.assertTrue(select.select([process.stdout], [], [], 5)[0], "state stream did not respond")
        return process.stdout.readline().strip()

    def test_status_is_read_only_even_with_stale_state(self):
        self.state.mkdir(mode=0o700)
        marker = self.state / "active"
        marker.write_text("stale")
        result = self.run_cli("status")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), "stale", "status must not race a start by deleting its files")

    def test_live_recorder_without_output_is_not_ready(self):
        self.env["FAKE_RECORDER_MODE"] = "hang"
        result = self.run_cli("start", "not-ready")
        self.assertNotEqual(result.returncode, 0, "a live process alone is not a recording")
        self.assertNotEqual(self.run_cli("status").returncode, 0)

    def test_second_toggle_cancels_a_pending_picker(self):
        gate = self.root / "picker"
        self.env["FAKE_PICKER_GATE"] = str(gate)
        first = self.spawn("toggle", "cancelled")
        self.wait_file(Path(str(gate) + ".entered"))
        result = self.run_cli("toggle")
        self.assertEqual(result.returncode, 0, result.stderr)
        gate.touch()
        first.communicate(timeout=5)
        self.assertNotEqual(first.returncode, 0)
        self.assertFalse((self.root / "launched").exists(), "cancellation must not launch either recorder")

    def test_watch_reports_start_and_crash_without_idle_children(self):
        trace = self.root / "process-trace"
        watch = self.spawn("watch", prefix=(STRACE, "-f", "-e", "trace=process", "-o", str(trace)))
        self.assertEqual(self.read_event(watch), "inactive")
        # An idle subscription must not start shells/status commands or emit
        # repeated identical states, including short-lived children between
        # samples. Trace process creation while no recording is running.
        baseline = trace.read_text()
        self.assertFalse(select.select([watch.stdout], [], [], 1.2)[0])
        self.assertEqual(trace.read_text(), baseline, "idle budget: no forks, execs or repeated state emissions")
        result = self.run_cli("start", "--portal", "watched")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.read_event(watch), "active")
        pid = int((self.root / "launched").read_text().strip())
        os.kill(pid, signal.SIGKILL)
        self.assertEqual(self.read_event(watch), "inactive", "crashes must clear REC without a polling timer")

    def test_concurrent_starts_launch_one_recorder(self):
        first = self.spawn("start", "--portal", "one")
        second = self.spawn("start", "--portal", "two")
        first.communicate(timeout=5)
        second.communicate(timeout=5)
        self.assertEqual(sorted([first.returncode, second.returncode]), [0, 1])
        self.assertEqual(len((self.root / "launched").read_text().splitlines()), 1)
        self.assertEqual(self.run_cli("status").returncode, 0)

    def test_stop_preserves_an_unrelated_recorder(self):
        external = subprocess.Popen([RECORDER], env=self.env, start_new_session=True)
        self.children.append(external)
        self.assertEqual(self.run_cli("start", "--portal", "owned").returncode, 0)
        result = self.run_cli("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(external.poll(), "stop may only signal the PID it started")
        self.assertNotEqual(self.run_cli("status").returncode, 0)

    def test_stop_does_not_kill_a_reused_pid(self):
        self.assertEqual(self.run_cli("start", "--portal", "reused").returncode, 0)
        # Stand in for the OS reusing the stopped PID for a different executable.
        # Fake only signal/proc observation; never churn the real PID namespace
        # or send a destructive signal to an unrelated process.
        boundary = self.root / "reused-pid.sh"
        boundary.write_text(r'''
kill() {
  local pid="${@: -1}"
  if [[ $1 == -SIGINT ]]; then
    builtin kill "$@" || return
    printf '%s\n' "$pid" > "$HOME/reused-pid"
    return 0
  fi
  if [[ -r $HOME/reused-pid && $pid == "$(<"$HOME/reused-pid")" ]]; then
    case $1 in
      -0) return 0 ;;
      -KILL) touch "$HOME/unsafe-signal"; return 0 ;;
    esac
  fi
  builtin kill "$@"
}
readlink() {
  if [[ -r $HOME/reused-pid && ${@: -1} == "/proc/$(<"$HOME/reused-pid")/exe" ]]; then
    printf '/bin/unrelated-application\n'
  else
    command readlink "$@"
  fi
}
sleep() {
  if [[ ! -r $HOME/reused-pid ]]; then command sleep "$@"; fi
}
''')
        self.env["BASH_ENV"] = str(boundary)
        result = self.run_cli("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "unsafe-signal").exists(), "the stopped PID now belongs to another executable")

    def test_runtime_fallback_is_private_and_symlinks_are_refused(self):
        del self.env["XDG_RUNTIME_DIR"]
        self.env["XDG_STATE_HOME"] = str(self.root / "state")
        result = self.run_cli("start", "--portal", "private")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.root / "state" / "record-screen"
        self.assertEqual(state.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.run_cli("stop").returncode, 0)
        state.rename(state.with_name("saved"))
        state.symlink_to(state.with_name("saved"), target_is_directory=True)
        self.assertNotEqual(self.run_cli("start", "--portal", "unsafe").returncode, 0)


if __name__ == "__main__":
    unittest.main()
