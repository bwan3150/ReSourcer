/**
 * Web E2E expects Node 22 (fnm + web/.node-version).
 * Fail fast on other majors so Mac/CI do not silently run on Node 24+.
 */
const major = Number(process.versions.node.split(".")[0]);
if (major !== 22) {
  console.error(
    `Web E2E requires Node 22 (use fnm: \`fnm use\` in web/, honors .node-version). Current: ${process.version}`,
  );
  process.exit(1);
}
