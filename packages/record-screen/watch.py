"""Stream recording transitions using inotify and pidfds, without polling."""
import ctypes
import os
from pathlib import Path
import select
import struct
import sys


def recording_pid(directory):
    try:
        if not (directory / "active").is_file():
            return None
        pid = int((directory / "pid").read_text())
        if pid > 0 and Path(os.readlink(f"/proc/{pid}/exe")).name == "gpu-screen-recorder":
            return pid
    except (OSError, ValueError):
        pass
    return None


def state_changed(events):
    relevant = False
    while True:
        try:
            data = os.read(events, 65536)
        except BlockingIOError:
            return relevant
        offset = 0
        while offset < len(data):
            _, flags, _, length = struct.unpack_from("iIII", data, offset)
            name = data[offset + 16:offset + 16 + length].rstrip(b"\0")
            offset += 16 + length
            if flags & (0x400 | 0x800 | 0x8000):
                raise OSError("recording state directory was removed")
            relevant |= name in (b"active", b"pid") or bool(flags & 0x4000)


def watch(directory):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    events = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
    if events < 0:
        raise OSError(ctypes.get_errno(), "inotify_init1")
    pidfd, observed_pid, previous = None, None, None
    try:
        # close-write, move-to, create/delete, and deletion/move of the directory.
        mask = 0x8 | 0x80 | 0x100 | 0x200 | 0x400 | 0x800
        if libc.inotify_add_watch(events, os.fsencode(directory), mask) < 0:
            raise OSError(ctypes.get_errno(), "inotify_add_watch")
        while True:
            pid = recording_pid(directory)
            if pid != observed_pid:
                if pidfd is not None:
                    os.close(pidfd)
                pidfd, observed_pid = None, pid
                if pid is not None:
                    try:
                        pidfd = os.pidfd_open(pid)
                    except ProcessLookupError:
                        pass
            # A pidfd becomes readable on exit, including an unreaped zombie.
            if pidfd is not None and select.select([pidfd], [], [], 0)[0]:
                os.close(pidfd)
                pidfd = None
            state = "active" if pidfd is not None else "inactive"
            if state != previous:
                print(state, flush=True)
                previous = state
            while True:
                readable, _, _ = select.select([events] + ([pidfd] if pidfd is not None else []), [], [])
                if pidfd in readable or (events in readable and state_changed(events)):
                    break
    finally:
        if pidfd is not None:
            os.close(pidfd)
        os.close(events)


if __name__ == "__main__":
    watch(Path(sys.argv[1]))
