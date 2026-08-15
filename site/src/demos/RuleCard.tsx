import { useMemo, useRef, useState } from "react";
import { Alert, Badge, Button, CodeBlock, Text, TextField, Title } from "@clickhouse/click-ui";
import { CodePane } from "../components";
import type { RuleJson } from "./types";
import type { Demo } from "./registry";
import { runQuery, type RunResult } from "./playground";
import ResultsTable from "./ResultsTable";

const SEVERITY_STATE = {
  critical: "danger",
  high: "danger",
  medium: "warning",
  low: "info",
  info: "neutral",
} as const;

const MAX_PARAM_CHARS = 200;
const MAX_ERROR_CHARS = 2000;

function resolveDefault(demo: Demo, ruleName: string, paramName: string): string {
  const value =
    demo.perRuleParamDefaults?.[ruleName]?.[paramName] ?? demo.params[paramName]?.default ?? "";
  return typeof value === "function" ? value() : value;
}

export default function RuleCard({ rule, demo }: Readonly<{ rule: RuleJson; demo: Demo }>) {
  const initialValues = useMemo(() => {
    const out: Record<string, string> = {};
    for (const p of rule.params) out[p.name] = resolveDefault(demo, rule.name, p.name);
    return out;
  }, [rule, demo]);

  const [values, setValues] = useState<Record<string, string>>(initialValues);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<RunResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const controllerRef = useRef<AbortController | null>(null);

  const nonRunnableReason = demo.nonRunnable?.[rule.name];

  // Validation happens on Run only — it never blocks typing.
  function validate(): boolean {
    const next: Record<string, string> = {};
    for (const p of rule.params) {
      const cfg = demo.params[p.name];
      const value = values[p.name] ?? "";
      if (value.length === 0) {
        next[p.name] = "required";
      } else if (value.length > MAX_PARAM_CHARS) {
        next[p.name] = `at most ${MAX_PARAM_CHARS} characters`;
      } else if (cfg?.pattern && !cfg.pattern.test(value)) {
        next[p.name] = cfg.help ? `expected ${cfg.help}` : `must match ${cfg.pattern.source}`;
      }
    }
    setFieldErrors(next);
    return Object.keys(next).length === 0;
  }

  async function run() {
    if (!validate()) return;
    const controller = new AbortController();
    controllerRef.current = controller;
    setRunning(true);
    setError(null);
    setResult(null);
    try {
      setResult(await runQuery(rule.sql, values, controller.signal));
    } catch (e) {
      if (controller.signal.aborted) {
        setError(null); // user hit Cancel
      } else {
        const message = e instanceof Error ? e.message : String(e);
        setError(message.slice(0, MAX_ERROR_CHARS));
      }
    } finally {
      if (controllerRef.current === controller) controllerRef.current = null;
      setRunning(false);
    }
  }

  return (
    <div className="rule-card" id={rule.name}>
      <div className="rule-card-head">
        <Title type="h3" className="rule-name">
          {rule.name}
        </Title>
        {rule.severity !== null && (
          <Badge text={rule.severity} state={SEVERITY_STATE[rule.severity]} size="sm" />
        )}
        {rule.tags.map((tag) => (
          <Badge key={tag} text={tag} state="neutral" size="sm" />
        ))}
      </div>
      {rule.description !== null && (
        <Text color="muted" size="sm">
          {rule.description}
        </Text>
      )}
      <CodePane>
        <CodeBlock language="plaintext">{rule.form}</CodeBlock>
      </CodePane>
      <CodePane>
        <CodeBlock language="sql" wrapLines>
          {rule.sql_pretty}
        </CodeBlock>
      </CodePane>
      {nonRunnableReason ? (
        <div className="run-row">
          <Badge text={`not runnable here — ${nonRunnableReason}`} state="neutral" />
        </div>
      ) : (
        <>
          {rule.params.length > 0 && (
            <div className="param-row">
              {rule.params.map((p) => (
                <TextField
                  key={p.name}
                  label={demo.params[p.name]?.label ?? `${p.name} (${p.type})`}
                  value={values[p.name] ?? ""}
                  error={fieldErrors[p.name]}
                  onChange={(inputValue) => {
                    setValues((prev) => ({ ...prev, [p.name]: inputValue }));
                    setFieldErrors((prev) => {
                      if (!(p.name in prev)) return prev;
                      const rest = { ...prev };
                      delete rest[p.name];
                      return rest;
                    });
                  }}
                />
              ))}
            </div>
          )}
          <div className="run-row">
            <Button type="primary" iconLeft="play" loading={running} disabled={running} onClick={run}>
              Run
            </Button>
            {running && (
              <Button type="secondary" onClick={() => controllerRef.current?.abort()}>
                Cancel
              </Button>
            )}
          </div>
          {error !== null && <Alert state="danger" text={error} showIcon />}
          {result !== null && <ResultsTable result={result} />}
        </>
      )}
    </div>
  );
}
