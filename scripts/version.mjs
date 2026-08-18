/**
 * Shared version arithmetic for OpenFlow's stable and beta release channels.
 *
 * Stable builds use X.Y.Z. Beta builds use X.Y.Z-testing.N, where X.Y.Z is
 * the next stable release and N increments for every beta published for it.
 */

export const BETA_CHANNEL = "testing";
export const INITIAL_STABLE_VERSION = "2.0.0";
export const PATCH_MAX = 99;
export const MINOR_MAX = 99;

const VERSION_RE = new RegExp(
  `^v?(\\d+)\\.(\\d+)\\.(\\d+)(?:-${BETA_CHANNEL}\\.(\\d+))?$`,
);

export function parseVersion(input) {
  const match = VERSION_RE.exec(String(input).trim());
  if (!match) return null;
  const [, major, minor, patch, iteration] = match;
  return {
    major: Number(major),
    minor: Number(minor),
    patch: Number(patch),
    channel: iteration === undefined ? "stable" : BETA_CHANNEL,
    iteration: iteration === undefined ? 0 : Number(iteration),
  };
}

export function formatVersion(version) {
  const base = `${version.major}.${version.minor}.${version.patch}`;
  return version.channel === "stable"
    ? base
    : `${base}-${BETA_CHANNEL}.${version.iteration}`;
}

export function channelOf(version) {
  return parseVersion(version)?.channel ?? "stable";
}

export function baseOf(version) {
  return { ...version, channel: "stable", iteration: 0 };
}

export function bump(version, level = "patch") {
  let { major, minor, patch } = version;
  if (level === "major") {
    major += 1;
    minor = 0;
    patch = 0;
  } else if (level === "minor") {
    minor += 1;
    patch = 0;
  } else {
    patch += 1;
  }
  if (patch > PATCH_MAX) {
    patch = 0;
    minor += 1;
  }
  if (minor > MINOR_MAX) {
    minor = 0;
    major += 1;
  }
  return { major, minor, patch, channel: "stable", iteration: 0 };
}

export function compareVersions(a, b) {
  if (a.major !== b.major) return a.major - b.major;
  if (a.minor !== b.minor) return a.minor - b.minor;
  if (a.patch !== b.patch) return a.patch - b.patch;
  if (a.channel !== b.channel) return a.channel === "stable" ? 1 : -1;
  return a.iteration - b.iteration;
}

export function isUpdateFor(currentVersion, candidateVersion) {
  const current = parseVersion(currentVersion);
  const candidate = parseVersion(candidateVersion);
  return Boolean(
    current &&
      candidate &&
      current.channel === candidate.channel &&
      compareVersions(candidate, current) > 0,
  );
}

export function latestStable(tags) {
  return tags
    .map(parseVersion)
    .filter((version) => version?.channel === "stable")
    .reduce(
      (best, version) =>
        best === null || compareVersions(version, best) > 0 ? version : best,
      null,
    );
}

export function latestIteration(tags, base) {
  return tags
    .map(parseVersion)
    .filter(
      (version) =>
        version?.channel === BETA_CHANNEL &&
        version.major === base.major &&
        version.minor === base.minor &&
        version.patch === base.patch,
    )
    .reduce((highest, version) => Math.max(highest, version.iteration), 0);
}

export function resolveVersion({ channel, tags, packageVersion, level = "patch" }) {
  const parsedPackage = parseVersion(packageVersion);
  if (!parsedPackage) {
    throw new Error(`pubspec version is not an OpenFlow version: ${packageVersion}`);
  }
  const packageBase = baseOf(parsedPackage);
  const stable = latestStable(tags);
  let base;

  if (stable === null && channel === "stable") {
    base = baseOf(parseVersion(INITIAL_STABLE_VERSION));
  } else if (stable === null) {
    base = packageBase;
  } else if (compareVersions(packageBase, stable) > 0) {
    base = packageBase;
  } else {
    base = bump(stable, level);
  }

  if (channel === "stable") return formatVersion(base);
  return formatVersion({
    ...base,
    channel: BETA_CHANNEL,
    iteration: latestIteration(tags, base) + 1,
  });
}

export function channelForBranch(branch) {
  const name = branch.replace(/^refs\/heads\//, "");
  if (name === "main") return "stable";
  if (name === BETA_CHANNEL) return BETA_CHANNEL;
  return null;
}
