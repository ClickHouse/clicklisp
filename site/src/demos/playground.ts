// The only networking module on the demo pages.
//
// SECURITY CONTRACT
// - The SQL sent here comes verbatim from build-time generated JSON, compiled
//   by clicklisp from this repo's own .lisp files. It is trusted, static
//   content — never concatenate anything into it.
// - User input reaches the server ONLY as typed param_NAME bindings resolved
//   server-side against {name:Type} placeholders, so it can never change the
//   query's structure. Param names are re-validated here (defense in depth)
//   even though they too come from generated JSON.
// - The server side is bounded by the readonly `demo` playground user
//   (max_result_rows=1000, max_execution_time=120).
// - CRITICAL: no `headers` option on fetch. The default text/plain body is
//   CORS-safelisted (no preflight); the endpoint's Access-Control-Allow-Headers
//   does NOT include content-type, so setting one breaks the request.

const PLAYGROUND = "https://sql-clickhouse.clickhouse.com/";

const PARAM_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;

const TIMEOUT_MS = 65000;
const MAX_ERROR_CHARS = 2000;

export interface RunSummary {
  readRows?: number;
  readBytes?: number;
  elapsedNs?: number;
}

export interface RunResult {
  meta: Array<{ name: string }>;
  data: unknown[][];
  rows: number;
  summary?: RunSummary;
}

function truncate(s: string, max: number): string {
  return s.length > max ? `${s.slice(0, max)}…` : s;
}

function parseSummary(header: string | null): RunSummary | undefined {
  if (!header) return undefined;
  try {
    // JSON with string numbers, e.g. {"read_rows":"1234","elapsed_ns":"56789",...}
    const raw = JSON.parse(header) as Record<string, unknown>;
    const num = (key: string): number | undefined => {
      const n = Number(raw[key]);
      return Number.isFinite(n) ? n : undefined;
    };
    return { readRows: num("read_rows"), readBytes: num("read_bytes"), elapsedNs: num("elapsed_ns") };
  } catch {
    return undefined;
  }
}

// AbortSignal.any is newer (Safari 17.4+) than the build's browser floor;
// fall back to forwarding both aborts through a fresh controller.
function combineSignals(signal: AbortSignal | undefined, timeout: AbortSignal): AbortSignal {
  if (!signal) return timeout;
  if (typeof AbortSignal.any === "function") return AbortSignal.any([signal, timeout]);
  const controller = new AbortController();
  const forward = () => controller.abort();
  signal.addEventListener("abort", forward, { once: true });
  timeout.addEventListener("abort", forward, { once: true });
  return controller.signal;
}

export async function runQuery(
  sql: string,
  params: Record<string, string>,
  signal?: AbortSignal
): Promise<RunResult> {
  const url = new URL(PLAYGROUND);
  url.searchParams.set("user", "demo");
  url.searchParams.set("default_format", "JSONCompact");
  for (const [name, value] of Object.entries(params)) {
    if (!PARAM_NAME.test(name)) throw new Error(`invalid query parameter name: ${name}`);
    url.searchParams.set(`param_${name}`, value);
  }

  const timeout = AbortSignal.timeout(TIMEOUT_MS);
  const res = await fetch(url, {
    method: "POST",
    body: sql,
    signal: combineSignals(signal, timeout),
  });

  const summary = parseSummary(res.headers.get("x-clickhouse-summary"));

  const text = await res.text();
  if (!res.ok) {
    throw new Error(truncate(text || `HTTP ${res.status}`, MAX_ERROR_CHARS));
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("unexpected response shape (not JSON)");
  }

  const obj = parsed as { meta?: unknown; data?: unknown; rows?: unknown };
  const metaOk =
    Array.isArray(obj.meta) &&
    obj.meta.every(
      (m) => typeof m === "object" && m !== null && typeof (m as { name?: unknown }).name === "string"
    );
  const dataOk = Array.isArray(obj.data) && obj.data.every((row) => Array.isArray(row));
  if (!metaOk || !dataOk) throw new Error("unexpected response shape");

  const meta = obj.meta as Array<{ name: string }>;
  const data = obj.data as unknown[][];
  const rows = typeof obj.rows === "number" ? obj.rows : data.length;
  return { meta, data, rows, summary };
}
