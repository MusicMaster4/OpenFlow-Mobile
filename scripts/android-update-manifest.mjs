/** Build the signed-APK manifest consumed by OpenFlow's in-app updater. */
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const FILE = fileURLToPath(import.meta.url);
const ROOT = path.resolve(path.dirname(FILE), "..");

export function assetName(channel) {
  if (channel === "stable") return "openflow.apk";
  if (channel === "testing") return "openflow-beta.apk";
  throw new Error(`unsupported update channel: ${channel}`);
}

export function manifestName(channel) {
  return channel === "testing"
    ? "android-update-beta.json"
    : "android-update.json";
}

export function buildManifest({
  channel,
  versionName,
  versionCode,
  repo,
  tag,
  sha256,
  publishedAt = new Date().toISOString(),
}) {
  const code = Number(versionCode);
  if (!["stable", "testing"].includes(channel)) {
    throw new Error(`unsupported update channel: ${channel}`);
  }
  if (!Number.isSafeInteger(code) || code < 1) {
    throw new Error("versionCode must be a positive integer");
  }
  if (!/^[a-f0-9]{64}$/i.test(sha256)) {
    throw new Error("sha256 must contain 64 hexadecimal characters");
  }
  return {
    schemaVersion: 1,
    channel,
    versionName,
    versionCode: code,
    apkUrl: `https://github.com/${repo}/releases/download/${encodeURIComponent(tag)}/${assetName(channel)}`,
    sha256: sha256.toLowerCase(),
    publishedAt,
  };
}

export function parseArgs(argv) {
  const args = {
    repo: process.env.GITHUB_REPOSITORY || "MusicMaster4/OpenFlow-Mobile",
    bundleDir: "release-assets",
  };
  const keys = {
    "--channel": "channel",
    "--version": "versionName",
    "--version-code": "versionCode",
    "--repo": "repo",
    "--tag": "tag",
    "--bundle-dir": "bundleDir",
    "--out": "out",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const key = keys[argv[index]];
    if (!key) throw new Error(`unknown argument: ${argv[index]}`);
    args[key] = argv[++index];
  }
  for (const key of ["channel", "versionName", "versionCode", "tag"]) {
    if (!args[key]) throw new Error(`${key} is required`);
  }
  args.out ||= manifestName(args.channel);
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const bundleDir = path.isAbsolute(args.bundleDir)
    ? args.bundleDir
    : path.join(ROOT, args.bundleDir);
  const apk = path.join(bundleDir, assetName(args.channel));
  const sha256 = createHash("sha256").update(readFileSync(apk)).digest("hex");
  const manifest = buildManifest({ ...args, sha256 });
  const output = path.isAbsolute(args.out)
    ? args.out
    : path.join(ROOT, args.out);
  writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`${path.relative(ROOT, output)} -> ${manifest.versionName}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === FILE) main();
