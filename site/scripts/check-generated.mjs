// Guard for npm run dev / npm run build: the demo pages import build-time
// JSON emitted by the clicklisp binary (gitignored), so a fresh checkout
// fails with a cryptic Rollup "failed to resolve import" unless we say
// what's actually missing.
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SLUGS = ["github-threats", "uk-price-paid", "hackernews", "repo-health"];

const siteRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const missing = SLUGS.map((slug) => join(siteRoot, "src", "generated", `${slug}.json`)).filter(
  (path) => !existsSync(path)
);

if (missing.length > 0) {
  console.error("demo data missing — run 'make site-data' at the repo root (needs ECL)");
  for (const path of missing) console.error(`  missing: ${path}`);
  process.exit(1);
}
