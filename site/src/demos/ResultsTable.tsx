import { Badge, Table, Text } from "@clickhouse/click-ui";
import type { RunResult, RunSummary } from "./playground";

const MAX_ROWS = 200;
const MAX_CELL_CHARS = 120;

function truncate(s: string, max: number): string {
  return s.length > max ? `${s.slice(0, max)}…` : s;
}

function renderCell(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (Array.isArray(value)) {
    const joined = value
      .map((v) => (v === null || v === undefined ? "—" : typeof v === "object" ? JSON.stringify(v) : String(v)))
      .join(", ");
    return truncate(joined, MAX_CELL_CHARS);
  }
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function humanCount(n: number): string {
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return String(n);
}

function humanBytes(n: number): string {
  const units = ["B", "KiB", "MiB", "GiB", "TiB"];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${i === 0 ? String(v) : v.toFixed(1)} ${units[i]}`;
}

function StatsRow({ summary }: Readonly<{ summary: RunSummary }>) {
  return (
    <div className="stats-row">
      {summary.readRows !== undefined && (
        <Badge text={`${humanCount(summary.readRows)} rows read`} state="neutral" size="sm" />
      )}
      {summary.readBytes !== undefined && (
        <Badge text={`${humanBytes(summary.readBytes)} read`} state="neutral" size="sm" />
      )}
      {summary.elapsedNs !== undefined && (
        <Badge text={`${(summary.elapsedNs / 1e6).toFixed(0)} ms`} state="neutral" size="sm" />
      )}
    </div>
  );
}

export default function ResultsTable({ result }: Readonly<{ result: RunResult }>) {
  const shown = result.data.slice(0, MAX_ROWS);
  return (
    <div className="results">
      {result.summary && <StatsRow summary={result.summary} />}
      <Table
        size="sm"
        headers={result.meta.map((m) => ({ label: m.name }))}
        rows={shown.map((row, i) => ({
          id: i,
          items: row.map((cell) => ({ label: renderCell(cell) })),
        }))}
        noDataMessage="No rows — nothing anomalous in this window."
      />
      {result.data.length > MAX_ROWS && (
        <Text color="muted" size="sm">
          showing first {MAX_ROWS} of {result.rows} rows
        </Text>
      )}
    </div>
  );
}
