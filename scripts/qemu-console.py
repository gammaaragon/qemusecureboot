#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Console driver for run-qemu.sh.

Spawns a command (qemu-system-arm) attached to a pty, so terminal
semantics work exactly as if it had been exec'd directly against a real
terminal -- raw keystrokes, QEMU's Ctrl-A monitor escape, no local line
buffering. Every byte the child produces is written to the log file AND
mirrored to real stdout unconditionally, interactive or not (matching the
old `qemu | tee log` behaviour). Real stdin is forwarded to the child only
when running interactively against a real tty, so a human can keep typing
after auto-login the same way they could before this wrapper existed.

If autologin is enabled, watches the child's output for OpenBMC's
"login:" / "Password:" prompts (which have no trailing newline, so this
scans a rolling byte buffer rather than reading lines) and sends the
lab's default credentials (root / 0penBmc) the first time each appears,
then gets out of the way for good -- it never re-sends after reaching the
logged-in stage, so a human is free to log out and back in by hand.

timeout_secs > 0 kills the child itself after that many seconds. This is
enforced here rather than by wrapping the caller in the external `timeout`
command specifically so the pty child (qemu) can never be left orphaned:
`timeout` only signals its direct child, and that direct child would have
been this process's pty-forked qemu grandchild-equivalent, not qemu
itself, once qemu is reparented onto the pty.
"""
import os
import pty
import re
import select
import signal
import sys
import time

LOGIN_PROMPT = re.compile(rb"login:\s*$")
PASSWORD_PROMPT = re.compile(rb"[Pp]assword:\s*$")
CRED_USER = b"root\r"
CRED_PASS = b"0penBmc\r"
SCAN_WINDOW = 256


def main() -> int:
    log_path = sys.argv[1]
    interactive = sys.argv[2] == "1"
    timeout_secs = float(sys.argv[3])
    autologin = sys.argv[4] == "1"
    argv = sys.argv[5:]

    pid, master_fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
        os._exit(127)  # pragma: no cover - only reached if execvp fails

    stdin_fd = sys.stdin.fileno()
    stdin_is_tty = interactive and os.isatty(stdin_fd)
    old_attr = None
    if stdin_is_tty:
        import termios
        import tty

        old_attr = termios.tcgetattr(stdin_fd)
        tty.setraw(stdin_fd)

    def restore_tty() -> None:
        if old_attr is not None:
            import termios

            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_attr)

    deadline = time.monotonic() + timeout_secs if timeout_secs > 0 else None
    stage = "login" if autologin else "done"
    scan_buf = b""
    timed_out = False
    child_status = 0

    log_f = open(log_path, "ab", buffering=0)
    try:
        while True:
            read_fds = [master_fd]
            if stdin_is_tty:
                read_fds.append(stdin_fd)

            wait = None
            if deadline is not None:
                wait = deadline - time.monotonic()
                if wait <= 0:
                    timed_out = True
                    break

            try:
                ready, _, _ = select.select(read_fds, [], [], wait)
            except InterruptedError:
                continue

            if master_fd in ready:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    data = b""
                if not data:
                    break  # child closed its end - it has exited
                log_f.write(data)
                os.write(sys.stdout.fileno(), data)

                if stage != "done":
                    scan_buf = (scan_buf + data)[-SCAN_WINDOW:]
                    if stage == "login" and LOGIN_PROMPT.search(scan_buf):
                        os.write(master_fd, CRED_USER)
                        stage = "password"
                        scan_buf = b""
                    elif stage == "password" and PASSWORD_PROMPT.search(scan_buf):
                        os.write(master_fd, CRED_PASS)
                        stage = "done"
                        scan_buf = b""

            if stdin_is_tty and stdin_fd in ready:
                data = os.read(stdin_fd, 4096)
                if data:
                    os.write(master_fd, data)
    finally:
        restore_tty()
        if timed_out:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            _, status = os.waitpid(pid, 0)
            child_status = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
        except ChildProcessError:
            pass
        log_f.close()

    # A timeout is the expected, designed outcome for a bounded observation
    # run, not a failure -- report success. If the child exited on its own
    # before the deadline, propagate its real exit status so a crash is
    # still visible.
    return 0 if timed_out else child_status


if __name__ == "__main__":
    sys.exit(main())
