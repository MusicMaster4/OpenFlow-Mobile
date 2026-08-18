import assert from "node:assert/strict";
import test from "node:test";

import { buildManifest, manifestName } from "./android-update-manifest.mjs";
import { parseArgs, pubspecVersion } from "./release-version.mjs";
import {
  channelForBranch,
  isUpdateFor,
  resolveVersion,
} from "./version.mjs";

test("release branches map to isolated channels", () => {
  assert.equal(channelForBranch("main"), "stable");
  assert.equal(channelForBranch("testing"), "testing");
  assert.equal(channelForBranch("feature/demo"), null);
  assert.throws(() => parseArgs(["--branch", "feature/demo"]));
});

test("stable and beta versions advance like Duckweed", () => {
  assert.equal(
    resolveVersion({ channel: "stable", tags: [], packageVersion: "2.0.0" }),
    "2.0.0",
  );
  assert.equal(
    resolveVersion({ channel: "testing", tags: [], packageVersion: "2.0.0" }),
    "2.0.0-testing.1",
  );
  const tags = ["v2.0.0", "v2.0.1-testing.1", "v2.0.1-testing.2"];
  assert.equal(
    resolveVersion({ channel: "testing", tags, packageVersion: "2.0.0" }),
    "2.0.1-testing.3",
  );
  assert.equal(
    resolveVersion({ channel: "stable", tags, packageVersion: "2.0.0" }),
    "2.0.1",
  );
});

test("an installed build only accepts newer versions from its own channel", () => {
  assert.equal(isUpdateFor("2.0.0", "2.0.1"), true);
  assert.equal(isUpdateFor("2.0.0", "2.0.1-testing.1"), false);
  assert.equal(isUpdateFor("2.0.1-testing.1", "2.0.1-testing.2"), true);
  assert.equal(isUpdateFor("2.0.1-testing.1", "2.0.1"), false);
});

test("pubspec build metadata does not become part of the release tag", () => {
  assert.equal(pubspecVersion("name: voxora\nversion: 2.3.4+17\n"), "2.3.4");
});

test("manifests use distinct names and channel-specific APKs", () => {
  assert.equal(manifestName("stable"), "android-update.json");
  assert.equal(manifestName("testing"), "android-update-beta.json");
  const manifest = buildManifest({
    channel: "testing",
    versionName: "2.0.1-testing.4",
    versionCode: 2000042,
    repo: "MusicMaster4/OpenFlow-Mobile",
    tag: "v2.0.1-testing.4",
    sha256: "a".repeat(64),
    publishedAt: "2026-08-18T00:00:00.000Z",
  });
  assert.equal(manifest.channel, "testing");
  assert.match(manifest.apkUrl, /openflow-beta\.apk$/);
  assert.equal(manifest.versionCode, 2000042);
});
