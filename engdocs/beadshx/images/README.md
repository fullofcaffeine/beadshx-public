# bdhx terminal screenshots

These SVG files show real `bdhx` output for a small demo project. A script
makes them, so do not edit them by hand.

| File | Command | What it shows |
| --- | --- | --- |
| `bdhx-list.svg` | `bdhx list --all` | All issues, with the epic as a tree |
| `bdhx-ready.svg` | `bdhx ready` | The issues that have no open blockers |
| `bdhx-blocked.svg` | `bdhx blocked` | The blocked issue and its blockers |
| `bdhx-show.svg` | `bdhx show demo-8xk.2` | The details of one issue |
| `bdhx-dep-tree.svg` | `bdhx dep tree demo-8xk.4` | The dependencies of one issue |
| `bdhx-graph.svg` | `bdhx graph demo-8xk` | The dependency graph of the epic, in layers |

## Regenerate the images

Build `bdhx` first (`./scripts/beadshx/command.sh setup`, then `generate` and
`build`). Then run this command from the repository root:

```bash
python3 scripts/beadshx/render_screenshots.py
```

The script uses only the Python standard library. It makes a disposable
workspace in a new temporary directory and seeds it with the demo issues
through the upstream oracle, `build/bin/bd-upstream`. Then it runs each
command with colors on and an 80-column width, and converts the output to SVG.
At the end, it removes the temporary directory.

The demo issues have fixed IDs and dates, so the same `bdhx` binary gives
byte-identical images. Regenerate the images when the output of these commands
changes. The script stops and writes no image if an output contains a local
path, the user or host name, or a value from the local privacy policy.
