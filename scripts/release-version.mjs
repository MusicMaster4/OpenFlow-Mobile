/** Resolve the next release version from git tags and pubspec.yaml. */
import { execFileSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { channelForBranch, resolveVersion } from "./version.mjs";

const FILE = fileURLToPath(import.meta.url);
const ROOT = path.resolve(path.dirname(FILE), "..");

export function parseArgs(argv) {
  const args = { channel: "stable", bump: "patch" };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--channel", "--bump", "--branch"].includes(argument)) {
      args[argument.slice(2)] = argv[++index];
    } else if (argument === "--dry-run") {
      args.dryRun = true;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (!args.bump) args.bump = "patch";
  if (args.branch) {
    const channel = channelForBranch(args.branch);
    if (!channel) {
      throw new Error(
        `branch ${args.branch} does not publish releases (only main and testing do)`,
      );
    }
    args.channel = channel;
  }
  if (!["stable", "testing"].includes(args.channel)) {
    throw new Error(`--channel must be stable or testing, got: ${args.channel}`);
  }
  if (!["patch", "minor", "major"].includes(args.bump)) {
    throw new Error(`--bump must be patch, minor or major, got: ${args.bump}`);
  }
  return args;
}

export function pubspecVersion(text) {
  const match = /^version:\s*([^+\s]+)(?:\+\d+)?\s*$/m.exec(text);
  if (!match) throw new Error("pubspec.yaml does not contain a valid version");
  return match[1];
}

function gitTags() {
  return execFileSync("git", ["tag", "--list"], {
    cwd: ROOT,
    encoding: "utf8",
  })
    .split("\n")
    .map((tag) => tag.trim())
    .filter(Boolean);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const packageVersion = pubspecVersion(
    readFileSync(path.join(ROOT, "pubspec.yaml"), "utf8"),
  );
  const version = resolveVersion({
    channel: args.channel,
    tags: gitTags(),
    packageVersion,
    level: args.bump,
  });
  const output = [
    `version=${version}`,
    `tag=v${version}`,
    `channel=${args.channel}`,
  ];
  console.log(output.join("\n"));
  if (process.env.GITHUB_OUTPUT && !args.dryRun) {
    appendFileSync(process.env.GITHUB_OUTPUT, `${output.join("\n")}\n`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === FILE) main();
