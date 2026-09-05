#!/usr/bin/env node

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const repositoryRoot = resolve(import.meta.dirname, "../..");
const backlogPath = resolve(repositoryRoot, "beadshx-complete-backlog.json");
const planPath = resolve(repositoryRoot, "build/program/beads-import-plan.json");
const write = process.argv.includes("--write");
const backlog = JSON.parse(readFileSync(backlogPath, "utf8"));

function issueId(sourceId) {
  return `beadshx-${sourceId.toLowerCase().replace(/^bhx-/, "")}`;
}

function unique(values) {
  return [...new Set(values)].sort();
}

const nodes = [
  {
    key: "program",
    id: "beadshx-program",
    title: `${backlog.program} complete port and production qualification`,
    type: "epic",
    priority: 0,
    description:
      "Port the pinned Beads compatibility target so Haxe owns application semantics while typed Go islands retain native integration mechanics.",
    acceptance_criteria:
      "Every milestone gate in the owner-directed PRD is either satisfied by reproducible evidence or remains visibly open with its exact blocker or approved divergence.",
    spec_id: backlog.document,
    external_ref: "BHX-PROGRAM",
    labels: ["beadshx", "program", "compatibility"],
    metadata: {
      source_document: backlog.document,
      source_schema_version: backlog.schemaVersion,
      compatibility_commit: backlog.compatibilityTarget.commit,
      compiler_reference_commit: backlog.compilerReference.commit,
    },
  },
];

const edges = [];

for (const milestone of backlog.milestones) {
  const milestoneKey = milestone.id.toLowerCase();
  nodes.push({
    key: milestoneKey,
    id: issueId(milestone.id),
    title: `${milestone.id}: ${milestone.title}`,
    type: "epic",
    priority: milestone.tasks.some((task) => task.priority === 0) ? 0 : 1,
    description: milestone.objective,
    acceptance_criteria: milestone.exit_gate.join("\n"),
    notes: `Forbidden in this milestone:\n${milestone.forbidden.join("\n")}`,
    parent_key: "program",
    spec_id: backlog.document,
    external_ref: `BHX-${milestone.id}`,
    labels: ["beadshx", "milestone", `milestone:${milestone.id.toLowerCase()}`],
    metadata: {
      source_document: backlog.document,
      prd_milestone_id: milestone.id,
    },
  });

  for (const dependency of milestone.depends_on) {
    edges.push({
      from_key: milestoneKey,
      to_key: dependency.toLowerCase(),
      type: "blocks",
    });
  }

  for (const task of milestone.tasks) {
    const taskKey = task.id.toLowerCase();
    nodes.push({
      key: taskKey,
      id: issueId(task.id),
      title: `${task.id}: ${task.title}`,
      type: task.issue_type,
      priority: task.priority,
      description: task.work,
      acceptance_criteria: task.acceptance,
      parent_key: milestoneKey,
      spec_id: backlog.document,
      external_ref: task.id,
      labels: unique([
        "beadshx",
        `milestone:${milestone.id.toLowerCase()}`,
        `repo:${task.repository}`,
        ...task.labels,
      ]),
      metadata: {
        source_document: backlog.document,
        prd_task_id: task.id,
        repository: task.repository,
      },
    });

    for (const dependency of task.depends_on) {
      edges.push({
        from_key: taskKey,
        to_key: dependency.toLowerCase(),
        type: "blocks",
      });
    }
  }
}

const plan = {
  commit_message: "program: import reconciled BeadsHX backlog",
  nodes,
  edges,
};

mkdirSync(dirname(planPath), { recursive: true });
writeFileSync(planPath, `${JSON.stringify(plan, null, 2)}\n`, { mode: 0o600 });

const args = ["create", "--graph", planPath, "--json"];
if (!write) {
  args.push("--dry-run");
}

const result = spawnSync("bd", args, {
  cwd: repositoryRoot,
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
});

if (result.stdout) {
  process.stdout.write(result.stdout);
}
if (result.stderr) {
  process.stderr.write(result.stderr);
}
if (result.status !== 0) {
  process.exit(result.status ?? 1);
}
