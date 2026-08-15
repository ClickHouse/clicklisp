import dayjs from "dayjs";
import type { IconName } from "@clickhouse/click-ui";

// Everything the demo pages and the landing #demos section know about each
// demo that is NOT in the generated JSON: display copy, dataset links, and
// per-parameter UI config (defaults, validation, help).

export interface ParamConfig {
  label: string;
  default: string | (() => string);
  pattern?: RegExp;
  help?: string;
}

export interface Demo {
  slug: string;
  title: string;
  blurb: string;
  icon: IconName;
  dataset: string;
  datasetHref: string;
  exampleFiles: string[];
  loadCommand: string;
  params: Record<string, ParamConfig>;
  perRuleParamDefaults?: Record<string, Record<string, string | (() => string)>>;
  /** Rule name → short reason it cannot run against the public playground. */
  nonRunnable?: Record<string, string>;
}

const DATETIME = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;
const UINT32 = /^\d{1,9}$/;
const DATETIME_HELP = "YYYY-MM-DD HH:MM:SS";

const EXAMPLES = "https://github.com/ClickHouse/clicklisp/blob/main/examples/analytics";

export type DemoSlug = "github-threats" | "uk-price-paid" | "hackernews" | "repo-health";

export const DEMOS: Record<DemoSlug, Demo> = {
  "github-threats": {
    slug: "github-threats",
    title: "GitHub events threat pack",
    blurb:
      "Detection rules hunting branch-reset storms, mass ref deletion, tag retargeting and star storms across 11B public GitHub events.",
    icon: "secure",
    dataset: "github.events — 11B GitHub events",
    datasetHref: "https://clickhouse.com/docs/getting-started/example-datasets/github-events",
    exampleFiles: [`${EXAMPLES}/github-events.lisp`],
    loadCommand:
      "bin/clicklisp rules sql --load examples/analytics/github-events.lisp tag-retarget | scripts/play.sh since=2025-09-01T00:00:00 until=2025-09-08T00:00:00",
    params: {
      since: { label: "since (DateTime)", default: "2025-01-01 00:00:00", pattern: DATETIME, help: DATETIME_HELP },
      until: { label: "until (DateTime)", default: "2025-01-08 00:00:00", pattern: DATETIME, help: DATETIME_HELP },
      hours: { label: "hours (UInt32)", default: "24", pattern: UINT32 },
      repo: { label: "repo (String)", default: "ClickHouse/ClickHouse", help: "owner/name" },
    },
    perRuleParamDefaults: {
      "tag-retarget": { since: "2025-09-01 00:00:00", until: "2025-09-08 00:00:00" },
      "commit-hour-anomaly": {
        since: () => dayjs().subtract(30, "day").format("YYYY-MM-DD HH:mm:ss"),
      },
    },
  },
  "uk-price-paid": {
    slug: "uk-price-paid",
    title: "UK property prices",
    blurb: "Macro-stamped league tables and price trends over 30M UK property transactions.",
    icon: "home",
    dataset: "uk.uk_price_paid — 30M UK property transactions",
    datasetHref: "https://clickhouse.com/docs/getting-started/example-datasets/uk-price-paid",
    exampleFiles: [`${EXAMPLES}/uk-price-paid.lisp`],
    loadCommand:
      "bin/clicklisp rules sql --load examples/analytics/uk-price-paid.lisp price-trend | scripts/play.sh town=LONDON",
    params: {
      town: { label: "town (String)", default: "LONDON", help: "uppercase, as stored (LONDON, YORK, ...)" },
    },
  },
  hackernews: {
    slug: "hackernews",
    title: "Hacker News analytics",
    blurb: "Hype cycles, vocabulary and prolific authors over 49M Hacker News rows.",
    icon: "fire",
    dataset: "hackernews.hackernews — 49M Hacker News rows",
    datasetHref: "https://sql.clickhouse.com",
    exampleFiles: [`${EXAMPLES}/hackernews.lisp`],
    loadCommand:
      "bin/clicklisp rules sql --load examples/analytics/hackernews.lisp hype-tracker | scripts/play.sh term=clojure",
    params: {
      term: { label: "term (String)", default: "clojure" },
    },
    nonRunnable: {
      "shouting-titles": "needs the local clicklisp_shout executable UDF",
    },
  },
  "repo-health": {
    slug: "repo-health",
    title: "Repo health",
    blurb: "Engineering analytics over ClickHouse's own git history.",
    icon: "git-merge",
    dataset: "git.clickhouse_* — ClickHouse's own git history",
    datasetHref: "https://sql.clickhouse.com",
    exampleFiles: [`${EXAMPLES}/repo-health.lisp`, `${EXAMPLES}/repo-health-playground.lisp`],
    loadCommand:
      "bin/clicklisp rules sql --load examples/analytics/repo-health.lisp --load examples/analytics/repo-health-playground.lisp file-rewrites | scripts/play.sh min_lines=200",
    params: {
      min_lines: { label: "min_lines (UInt32)", default: "200", pattern: UINT32 },
    },
  },
};

export const DEMO_ORDER: DemoSlug[] = ["github-threats", "uk-price-paid", "hackernews", "repo-health"];
