// Shape of the build-time JSON in src/generated/<slug>.json, emitted by the
// clicklisp binary (`make site-data` at the repo root).

export interface RuleParam {
  name: string;
  type: string;
}

export interface RuleJson {
  name: string;
  description: string | null;
  severity: "info" | "low" | "medium" | "high" | "critical" | null;
  tags: string[];
  params: RuleParam[];
  sql: string;
  sql_pretty: string;
  form: string;
}

export interface RulesJson {
  clicklisp: string;
  rules: RuleJson[];
}
