#!/usr/bin/env python3
"""Render reproducible terminal screenshots of bdhx as SVG files.

Regenerate every image with one command from the repository root, after
`./scripts/beadshx/command.sh setup`, `generate` and `build`:

    python3 scripts/beadshx/render_screenshots.py

The script uses the Python standard library only. It makes a disposable
workspace in a new temporary directory, seeds it with neutral demo issues
through the pinned upstream oracle (`build/bin/bd-upstream`), runs read-only
`bdhx` commands with colors forced on, and converts their ANSI output to SVG
files in `engdocs/beadshx/images/`. It removes the temporary directory at the
end, and it never touches another Beads workspace.

The demo issues have fixed IDs and timestamps, the clock zone is UTC, and every
command gets a clean environment (its own HOME, no agent mode, no telemetry).
So the images are byte-identical between runs of the same `bdhx` binary. The
captured views print absolute dates only. If a later `bdhx` adds relative time
text, such as "2 days ago", to these views, a later run can change those lines.

Before it writes an image, the script fails if any command output has a
machine-local path, the temporary directory, the home directory, the user
name, the host name, or a value from Git's local private-content policy
(`info/private-content-patterns.json`). It never prints the matched value.
"""

from __future__ import annotations

import argparse
import functools
import getpass
import html
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
from typing import Iterator
import unicodedata


REPOSITORY = Path(__file__).resolve().parents[2]
DEFAULT_BDHX = REPOSITORY / "build/bin/bdhx"
DEFAULT_ORACLE = REPOSITORY / "build/bin/bd-upstream"
DEFAULT_OUTPUT = REPOSITORY / "engdocs/beadshx/images"
# Upstream and bdhx wrap at 80 columns when stdout is not a terminal.
COLUMNS = 80
ACTOR = "demo"

# Each image: the output file name and the bdhx arguments that the title bar shows.
SCREENSHOTS = [
    ("bdhx-list.svg", ["list", "--all"]),
    ("bdhx-ready.svg", ["ready"]),
    ("bdhx-blocked.svg", ["blocked"]),
    ("bdhx-show.svg", ["show", "demo-8xk.2"]),
    ("bdhx-dep-tree.svg", ["dep", "tree", "demo-8xk.4"]),
    ("bdhx-graph.svg", ["graph", "demo-8xk"]),
]

# Substrings that no captured output may contain.
FORBIDDEN_MARKERS = ("/Users/", "/home/", "/private/", "/tmp/", "/var/folders/", "\\Users\\")


def demo_issues() -> list[dict[str, object]]:
    """Return a small product backlog with an epic, children and one blocked task."""

    def stamp(day: int, hour: int) -> str:
        return f"2026-11-{day:02d}T{hour:02d}:00:00Z"

    def issue(identifier: str, title: str, issue_type: str, priority: int, day: int,
              **fields: object) -> dict[str, object]:
        record: dict[str, object] = {
            "id": identifier,
            "title": title,
            "status": "open",
            "priority": priority,
            "issue_type": issue_type,
            "created_at": stamp(day, 9),
            "created_by": ACTOR,
            "updated_at": stamp(day, 9),
        }
        record.update(fields)
        return record

    def link(child: str, parent: str, kind: str, day: int) -> dict[str, object]:
        return {
            "issue_id": child,
            "depends_on_id": parent,
            "type": kind,
            "created_at": stamp(day, 10),
            "created_by": ACTOR,
        }

    epic = "demo-8xk"
    return [
        issue(epic, "Launch the public beta", "epic", 1, 2,
              description="Ship the first public beta of the mobile app."),
        issue("demo-q3m", "App crashes when the session expires", "bug", 0, 3,
              labels=["auth", "mobile"],
              description="Opening the app after a long pause crashes it."),
        issue(f"{epic}.1", "Write the onboarding guide", "task", 2, 3,
              labels=["docs"],
              dependencies=[link(f"{epic}.1", epic, "parent-child", 3)]),
        issue(f"{epic}.2", "Add sign-in with email links", "feature", 1, 3,
              status="in_progress", assignee=ACTOR, labels=["auth"],
              updated_at=stamp(5, 14), started_at=stamp(5, 14),
              description=(
                  "Let people sign in with a one-time link sent by email, so "
                  "that they do not need a password."
              ),
              acceptance_criteria=(
                  "- A sign-in link works once and expires after 15 minutes.\n"
                  "- An expired link shows a clear message."
              ),
              dependencies=[link(f"{epic}.2", epic, "parent-child", 3)]),
        issue(f"{epic}.3", "Set up error reporting", "task", 2, 3,
              status="closed", closed_at=stamp(4, 16), updated_at=stamp(4, 16),
              close_reason="Done",
              dependencies=[link(f"{epic}.3", epic, "parent-child", 3)]),
        issue(f"{epic}.4", "Publish the release notes", "task", 3, 4,
              labels=["docs"],
              dependencies=[
                  link(f"{epic}.4", epic, "parent-child", 4),
                  link(f"{epic}.4", f"{epic}.2", "blocks", 4),
                  link(f"{epic}.4", "demo-q3m", "blocks", 4),
              ]),
        issue("demo-r7t", "Cache the search results", "task", 2, 4,
              labels=["performance"]),
        issue("demo-w2c", "Dark theme for the settings page", "feature", 3, 5,
              labels=["ui"]),
        issue("demo-m5n", "Upgrade the database driver", "chore", 4, 5),
    ]


def base_environment(root: Path) -> dict[str, str]:
    """Build each command's environment from nothing, so no local setting leaks in."""
    home = root / "home"
    return {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "TMPDIR": str(root / "tmp"),
        "LANG": "C.UTF-8",
        "TZ": "UTC",
        "BD_ACTOR": ACTOR,
        "BEADS_ACTOR": ACTOR,
        "GIT_AUTHOR_NAME": ACTOR,
        "GIT_AUTHOR_EMAIL": f"{ACTOR}@example.invalid",
        "GIT_COMMITTER_NAME": ACTOR,
        "GIT_COMMITTER_EMAIL": f"{ACTOR}@example.invalid",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "BD_DISABLE_METRICS": "1",
        "DO_NOT_TRACK": "1",
        "BEADS_TELEMETRY_DISABLED": "1",
        "BEADS_NO_AUTO_FLUSH": "1",
        "BD_DISABLE_EVENT_FLUSH": "1",
    }


def run(arguments: list[str], *, cwd: Path, env: dict[str, str],
        input_text: str | None = None, quiet: bool = True) -> str:
    """Run one command and return its stdout; with quiet, stderr must stay empty."""
    completed = subprocess.run(
        arguments,
        cwd=cwd,
        env=env,
        input=input_text.encode("utf-8") if input_text is not None else None,
        stdin=subprocess.DEVNULL if input_text is None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0 or (quiet and completed.stderr):
        detail = completed.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(
            f"{Path(arguments[0]).name} {' '.join(arguments[1:])} failed "
            f"(exit {completed.returncode}): {detail}"
        )
    return completed.stdout.decode("utf-8")


def redact(text: str, workspace: Path) -> str:
    """Hide local paths in an error message before the script prints it."""
    values = {str(workspace), str(workspace.resolve()), str(Path.home())}
    for value in sorted(values, key=len, reverse=True):
        text = text.replace(value, "<local>")
    return text


@functools.lru_cache(maxsize=None)
def private_patterns() -> tuple[str, ...]:
    """Read the same local-only privacy policy that the pre-commit guard uses."""
    completed = subprocess.run(
        ["git", "-C", str(REPOSITORY), "rev-parse", "--git-common-dir"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if completed.returncode != 0:
        return ()
    common = Path(completed.stdout.decode("utf-8").strip())
    if not common.is_absolute():
        common = REPOSITORY / common
    policy_path = common / "info/private-content-patterns.json"
    if not policy_path.exists():
        return ()
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    patterns = policy.get("patterns") if isinstance(policy, dict) else None
    if not isinstance(patterns, list) or not all(isinstance(value, str) for value in patterns):
        raise ValueError("invalid local private-content policy")
    return tuple(value.casefold() for value in patterns if value.strip())


def privacy_findings(text: str, workspace: Path) -> list[str]:
    """Name each kind of private value in the text, without the value itself."""
    findings = [f"machine-local path marker {marker!r}" for marker in FORBIDDEN_MARKERS
                if marker in text]
    local_values = {
        "temporary directory": {str(workspace), str(workspace.resolve())},
        "home directory": {str(Path.home()), str(Path.home().resolve())},
        "repository path": {str(REPOSITORY)},
    }
    for kind, values in local_values.items():
        if any(value in text for value in values):
            findings.append(kind)
    names = {"user name": getpass.getuser(), "host name": socket.gethostname()}
    names["short host name"] = names["host name"].split(".", 1)[0]
    for kind, value in names.items():
        if value and re.search(rf"(?<![\w-]){re.escape(value)}(?![\w-])", text, re.IGNORECASE):
            findings.append(kind)
    folded = text.casefold()
    if any(pattern in folded for pattern in private_patterns()):
        findings.append("value from the local private-content policy")
    return findings


# ANSI parsing -----------------------------------------------------------------

# A CSI sequence (SGR when it ends in "m"), an OSC sequence, or a two-byte escape.
ESCAPE = re.compile(r"\x1b(?:\[([0-9;:?]*)([@-~])|\][^\x07\x1b]*(?:\x07|\x1b\\)|[@-_])")
BACKGROUND = "#0d1017"
FOREGROUND = "#bfbdb6"
# Ayu dark terminal colors for the 16 basic SGR colors.
BASIC_COLORS = [
    "#01060e", "#ea6c73", "#91b362", "#f9af4f", "#53bdfa", "#fae994", "#90e1c6", "#c7c7c7",
    "#686868", "#f07178", "#c2d94c", "#ffb454", "#59c2ff", "#ffee99", "#95e6cb", "#ffffff",
]

# A style key: foreground, background, bold, faint, italic, underline, strike, reverse.
StyleKey = tuple[object, ...]
# A terminal cell: its column, its character and its style key.
Cell = tuple[int, str, StyleKey]


def xterm_color(index: int) -> str:
    if index < 16:
        return BASIC_COLORS[index]
    if index < 232:
        index -= 16
        steps = [0, 95, 135, 175, 215, 255]
        red, green, blue = steps[index // 36], steps[index // 6 % 6], steps[index % 6]
        return f"#{red:02x}{green:02x}{blue:02x}"
    level = 8 + (index - 232) * 10
    return f"#{level:02x}{level:02x}{level:02x}"


class Style:
    """The SGR state of the terminal while the parser reads the output."""

    __slots__ = ("foreground", "background", "bold", "faint", "italic", "underline",
                 "strike", "reverse")

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.foreground: str | None = None
        self.background: str | None = None
        self.bold = self.faint = self.italic = self.underline = False
        self.strike = self.reverse = False

    def key(self) -> StyleKey:
        return tuple(getattr(self, name) for name in self.__slots__)

    def apply(self, parameters: str) -> None:
        codes = [int(part) if part else 0 for part in re.split(r"[;:]", parameters or "0")]
        index = 0
        while index < len(codes):
            code = codes[index]
            index += 1
            if code == 0:
                self.reset()
            elif code == 1:
                self.bold = True
            elif code == 2:
                self.faint = True
            elif code == 3:
                self.italic = True
            elif code == 4:
                self.underline = True
            elif code == 7:
                self.reverse = True
            elif code == 9:
                self.strike = True
            elif code == 22:
                self.bold = self.faint = False
            elif code == 23:
                self.italic = False
            elif code == 24:
                self.underline = False
            elif code == 27:
                self.reverse = False
            elif code == 29:
                self.strike = False
            elif 30 <= code <= 37 or 90 <= code <= 97:
                self.foreground = BASIC_COLORS[code - 30 if code < 90 else code - 82]
            elif 40 <= code <= 47 or 100 <= code <= 107:
                self.background = BASIC_COLORS[code - 40 if code < 100 else code - 92]
            elif code == 39:
                self.foreground = None
            elif code == 49:
                self.background = None
            elif code in (38, 48) and index < len(codes):
                mode = codes[index]
                if mode == 5 and index + 1 < len(codes):
                    color = xterm_color(codes[index + 1])
                    index += 2
                elif mode == 2 and index + 3 < len(codes):
                    red, green, blue = codes[index + 1:index + 4]
                    color = f"#{red:02x}{green:02x}{blue:02x}"
                    index += 4
                else:
                    raise ValueError(f"unsupported extended color: {parameters!r}")
                if code == 38:
                    self.foreground = color
                else:
                    self.background = color
            else:
                raise ValueError(f"unsupported SGR code {code} in {parameters!r}")


def cell_width(character: str) -> int:
    if unicodedata.combining(character):
        return 0
    return 2 if unicodedata.east_asian_width(character) in ("W", "F") else 1


def is_blank(cell: Cell) -> bool:
    """Tell whether a cell shows nothing: a space without a background or reverse video."""
    _, character, key = cell
    background, reverse = key[1], key[7]
    return not character.strip() and background is None and not reverse


def add_text(cells: list[Cell], text: str, column: int, style: Style) -> int:
    key = style.key()
    for character in text:
        if character == "\t":
            column += 8 - column % 8
        elif character == "\r":
            column = 0
        elif unicodedata.category(character) == "Cc":
            raise ValueError(f"unexpected control character {character!r}")
        else:
            cells.append((column, character, key))
            column += cell_width(character)
    return column


def parse_ansi(text: str) -> list[list[Cell]]:
    """Turn ANSI text into lines of cells, without blank lines at either end."""
    style = Style()
    lines: list[list[Cell]] = []
    for raw_line in text.split("\n"):
        cells: list[Cell] = []
        column = 0
        position = 0
        for match in ESCAPE.finditer(raw_line):
            column = add_text(cells, raw_line[position:match.start()], column, style)
            if match.group(2) == "m":
                style.apply(match.group(1))
            position = match.end()
        add_text(cells, raw_line[position:], column, style)
        while cells and is_blank(cells[-1]):
            cells.pop()
        lines.append(cells)
    while lines and not lines[-1]:
        lines.pop()
    while lines and not lines[0]:
        lines.pop(0)
    return lines


# SVG rendering ----------------------------------------------------------------

FONT_SIZE = 14
CHARACTER_WIDTH = 8.4
LINE_HEIGHT = 17
PADDING = 16
TITLE_HEIGHT = 36
# These fonts all draw box-drawing characters; SF Mono, for example, does not.
FONT_FAMILY = "Menlo, Consolas, 'DejaVu Sans Mono', 'Liberation Mono', monospace"


def number(value: float) -> str:
    return f"{value:.1f}".rstrip("0").rstrip(".")


def css_rules(key: StyleKey) -> tuple[str, str | None]:
    """Return the text rule and the background color for one style key."""
    foreground, background, bold, faint, italic, underline, strike, reverse = key
    fill = foreground or FOREGROUND
    if reverse:
        fill, background = background or BACKGROUND, fill
    rules = [f"fill:{fill}"]
    if bold:
        rules.append("font-weight:bold")
    if faint:
        rules.append("opacity:0.6")
    if italic:
        rules.append("font-style:italic")
    decorations = [name for name, enabled in (("underline", underline),
                                               ("line-through", strike)) if enabled]
    if decorations:
        rules.append("text-decoration:" + " ".join(decorations))
    return ";".join(rules), background


def fits_grid(character: str) -> bool:
    """Tell whether the listed fonts all draw this character in one cell."""
    return character.isascii() or "\u2500" <= character <= "\u257f"


def runs(cells: list[Cell]) -> Iterator[list[Cell]]:
    """Group cells into runs that share a style and that a monospace font can place.

    A run ends after each character that the listed fonts may not have, so that
    a fallback font with another glyph width cannot move the text after it.
    """
    current: list[Cell] = []
    for cell in cells:
        if current and (
            cell[2] != current[-1][2]
            or cell[0] != current[-1][0] + cell_width(current[-1][1])
            or not fits_grid(current[-1][1])
        ):
            yield current
            current = []
        current.append(cell)
    if current:
        yield current


def render_svg(command: str, text: str) -> str:
    """Draw the ANSI text in a terminal window whose title bar shows the command."""
    lines = parse_ansi(text)
    used = max((cells[-1][0] + cell_width(cells[-1][1]) for cells in lines if cells), default=0)
    width = round(max(COLUMNS, used) * CHARACTER_WIDTH + 2 * PADDING)
    height = TITLE_HEIGHT + PADDING + len(lines) * LINE_HEIGHT + PADDING
    classes: dict[str, str] = {}
    backgrounds: list[str] = []
    body: list[str] = []
    for row, cells in enumerate(lines):
        baseline = TITLE_HEIGHT + PADDING + row * LINE_HEIGHT + FONT_SIZE
        spans: list[str] = []
        for run_cells in runs(cells):
            rule, background = css_rules(run_cells[0][2])
            x = number(PADDING + run_cells[0][0] * CHARACTER_WIDTH)
            run_width = number(sum(cell_width(cell[1]) for cell in run_cells) * CHARACTER_WIDTH)
            if background:
                backgrounds.append(
                    f'<rect x="{x}" y="{baseline - FONT_SIZE - 1}" width="{run_width}" '
                    f'height="{LINE_HEIGHT}" fill="{background}"/>'
                )
            content = "".join(cell[1] for cell in run_cells)
            if not content.strip() and "decoration" not in rule:
                continue
            name = classes.setdefault(rule, f"c{len(classes)}")
            # textLength keeps each run on the cell grid in any monospace font.
            spans.append(
                f'<tspan x="{x}" textLength="{run_width}" lengthAdjust="spacingAndGlyphs" '
                f'class="{name}">{html.escape(content, False)}</tspan>'
            )
        if spans:
            body.append(f'<text y="{baseline}">{"".join(spans)}</text>')
    style = "".join(f".{name}{{{rule}}}" for rule, name in classes.items())
    title = html.escape(f"$ {command}")
    dots = "".join(
        f'<circle cx="{PADDING + 4 + index * 20}" cy="{TITLE_HEIGHT // 2}" r="6" fill="{color}"/>'
        for index, color in enumerate(("#ff5f57", "#febc2e", "#28c840"))
    )
    title_bar = (f"M0 8a8 8 0 0 1 8-8h{width - 16}a8 8 0 0 1 8 8v{TITLE_HEIGHT - 8}"
                 f"h-{width}z")
    return "\n".join([
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" xml:space="preserve" role="img" '
        f'aria-label="{title}">',
        f"<title>{title}</title>",
        f"<style>text{{font-family:{FONT_FAMILY};font-size:{FONT_SIZE}px;white-space:pre}}"
        f"{style}</style>",
        f'<rect width="{width}" height="{height}" rx="8" fill="{BACKGROUND}"/>',
        f'<path d="{title_bar}" fill="#1a1f29"/>',
        dots,
        f'<text x="{width // 2}" y="{TITLE_HEIGHT // 2 + 5}" text-anchor="middle" '
        f'fill="#8a9199">{title}</text>',
        *backgrounds,
        *body,
        f'<rect x="0.5" y="0.5" width="{width - 1}" height="{height - 1}" rx="7.5" '
        f'fill="none" stroke="#2d3340"/>',
        "</svg>",
        "",
    ])


# Workflow ---------------------------------------------------------------------

def seed_workspace(oracle: Path, work: Path, env: dict[str, str]) -> None:
    seed_env = dict(env, NO_COLOR="1")
    run([str(oracle), "init", "--prefix", "demo", "--non-interactive", "--skip-agents",
         "--skip-hooks", "--quiet"], cwd=work, env=seed_env)
    records = "".join(json.dumps(record, sort_keys=True) + "\n" for record in demo_issues())
    # import reports its count on stderr.
    run([str(oracle), "import", "-"], cwd=work, env=seed_env, input_text=records, quiet=False)


def capture(bdhx: Path, oracle: Path, root: Path) -> dict[str, tuple[str, str]]:
    """Seed a workspace under root and return each image's command and ANSI output."""
    work = root / "work"
    for directory in (work, root / "home" / ".config", root / "tmp"):
        directory.mkdir(parents=True)
    env = base_environment(root)
    # The repository's disposable-fixture marker and check, as the parity tests use.
    (work / ".beadshx-disposable-fixture").touch()
    run([str(REPOSITORY / "scripts/beadshx/assert-disposable-workspace.sh"), str(work)],
        cwd=work, env=env)
    seed_workspace(oracle, work, env)
    color_env = dict(env, CLICOLOR_FORCE="1", TERM="xterm-256color", COLUMNS=str(COLUMNS))
    outputs: dict[str, tuple[str, str]] = {}
    for name, arguments in SCREENSHOTS:
        command = " ".join(["bdhx", *arguments])
        text = run([str(bdhx), *arguments], cwd=work, env=color_env)
        findings = privacy_findings(text, root)
        if findings:
            raise RuntimeError(f"{command} output has private content: {', '.join(findings)}")
        outputs[name] = (command, text)
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--bdhx", type=Path, default=DEFAULT_BDHX)
    parser.add_argument("--oracle", type=Path, default=DEFAULT_ORACLE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    arguments = parser.parse_args()
    for label, binary in (("bdhx", arguments.bdhx), ("upstream oracle", arguments.oracle)):
        if not os.access(binary, os.X_OK):
            print(f"render_screenshots: {label} binary is missing: {binary}", file=sys.stderr)
            return 1
    with tempfile.TemporaryDirectory(prefix="bdhx-screenshots-") as temporary:
        root = Path(temporary).resolve()
        try:
            outputs = capture(arguments.bdhx.resolve(), arguments.oracle.resolve(), root)
            images = {name: render_svg(command, text)
                      for name, (command, text) in outputs.items()}
            for name, image in images.items():
                findings = privacy_findings(image, root)
                if findings:
                    raise RuntimeError(f"{name} has private content: {', '.join(findings)}")
        except (RuntimeError, ValueError, OSError) as error:
            print(f"render_screenshots: {redact(str(error), root)}", file=sys.stderr)
            return 1
    arguments.output.mkdir(parents=True, exist_ok=True)
    for name, image in images.items():
        (arguments.output / name).write_text(image, encoding="utf-8")
        print(f"wrote {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
