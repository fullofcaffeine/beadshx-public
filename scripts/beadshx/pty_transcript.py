#!/usr/bin/env python3
"""Run one command on a new pseudo-terminal and print what it wrote there.

Usage:

    python3 -I scripts/beadshx/pty_transcript.py [--answer none|dark|light]
        [--timeout SECONDS] -- BINARY [ARGUMENT...]

Why: with colors on, upstream bd asks the terminal for its background color
once per process (an OSC 11 query and a DA1 request, from internal/ui's
package init). The parity harness must see those query bytes, where they fall
among the other output, and how often a binary sends them. A pipe never shows
them, because lipgloss sends them only when stdin and stdout are terminals.

What: the command runs with stdin, stdout and stderr on one pseudo-terminal,
which is also its controlling terminal. The script prints every byte that the
command wrote to that terminal, in the order written, stdout and stderr
together. It undoes only the terminal driver's line-feed translation: each
"\\r\\n" becomes "\\n". The command's exit code is the script's exit code.

How: `--answer none` (the default) is a terminal that never answers, so each
query waits for lipgloss's own timeout. `--answer dark` and `--answer light`
answer each query at once with a black or a white background and a DA1 reply.
The answer is written while lipgloss holds the terminal in raw mode, so the
terminal does not echo it. The window size stays unset, so the terminal
reports 0 columns, as the `script`-based runners do. The terminal runs at
4800 baud, which no command here reads. At the default 9600 baud, the macOS
driver lets a write fill its 1024-byte output queue, and when the queue fills
right after the CR of a line feed, the driver sends that CR twice. That CR is
no byte that the command wrote, and whether it comes depends on how soon this
script reads, so it changed from run to run, for upstream bd too
(beadshx-m06.6). At 4800 baud a write waits for the reader once more than
768 bytes are queued, before the queue can fill. A command that runs longer
than `--timeout` seconds is killed with its process group, and the script then
exits 124. The script uses the Python standard library only.
"""

from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import sys
import termios
import time

QUERY = b"\x1b]11;?\x07\x1b[c"
ANSWERS = {
    "dark": b"\x1b]11;rgb:0000/0000/0000\x1b\\\x1b[?62;22c",
    "light": b"\x1b]11;rgb:ffff/ffff/ffff\x1b\\\x1b[?62;22c",
}


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--answer", choices=["none", *ANSWERS], default="none")
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if arguments.command[:1] == ["--"]:
        arguments.command = arguments.command[1:]
    if not arguments.command:
        parser.error("a command is required after --")
    return arguments


def exit_code(status: int) -> int:
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return 128 + os.WTERMSIG(status)
    return 1


def main() -> int:
    arguments = parse_arguments()
    pid, master = pty.fork()
    if pid == 0:
        attributes = termios.tcgetattr(0)
        attributes[4] = attributes[5] = termios.B4800
        termios.tcsetattr(0, termios.TCSANOW, attributes)
        try:
            os.execvp(arguments.command[0], arguments.command)
        except OSError as error:
            os.write(2, f"cannot run {arguments.command[0]}: {error.strerror}\n".encode())
        os._exit(127)

    deadline = time.monotonic() + arguments.timeout
    answer = ANSWERS.get(arguments.answer)
    transcript = bytearray()
    answered = 0
    status: int | None = None
    while True:
        if status is None:
            finished, child_status = os.waitpid(pid, os.WNOHANG)
            if finished:
                status = child_status
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            if status is None:
                try:
                    os.killpg(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.waitpid(pid, 0)
            sys.stdout.buffer.write(bytes(transcript).replace(b"\r\n", b"\n"))
            sys.stderr.write(f"pty_transcript: timed out after {arguments.timeout:g} seconds\n")
            return 124
        # After the command exits, read what is left; a process that it left behind holding the
        # terminal open must not keep the script waiting.
        ready, _, _ = select.select([master], [], [], min(remaining, 0.05 if status is not None else 0.2))
        if not ready:
            if status is not None:
                break
            continue
        try:
            chunk = os.read(master, 65536)
        except OSError:
            chunk = b""
        if not chunk:
            if status is None:
                status = os.waitpid(pid, 0)[1]
            break
        transcript += chunk
        if answer is not None:
            while transcript.count(QUERY) > answered:
                os.write(master, answer)
                answered += 1
    os.close(master)
    sys.stdout.buffer.write(bytes(transcript).replace(b"\r\n", b"\n"))
    return exit_code(status)


if __name__ == "__main__":
    sys.exit(main())
