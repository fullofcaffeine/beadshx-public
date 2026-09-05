# Schema migration graph

BeadsHX treats the pinned migration files as graph nodes. It does not copy
their names, SQL, or hashes into a second catalog. The local graph command
reads those frozen files from the pinned Git commit and derives each numbered
node, edge, content hash, and adjacent-version test pair.

[`plan.json`](plan.json) adds the facts that SQL files cannot express alone:

- the production order around the main and ignored migration lanes;
- repair, retry, remote-gate, cursor, and commit nodes;
- schema observers for tables, columns, indexes, constraints, views, cursor
  hashes, ignored status, and row invariants;
- historical, repair, mixed-cursor, remote, SQLite, and skew test pairs; and
- semantic irreversible or conditionally reversible transitions.

A down file is evidence only. It does not prove that a transition preserves
identity or information. The graph therefore gives destructive rekeys, plane
moves, normalization, and cleanup their own semantic classifications.

## Local commands

Run the graph check:

```sh
npm run test:schema-migrations
```

Generate the complete pair list:

```sh
npm run schema:migration-pairs
```

Both commands read the local Git object database. They do not migrate a live
database and do not require `gh`, GitHub Actions, Docker, or network access.
