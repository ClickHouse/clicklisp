import { Text } from "@clickhouse/click-ui";
import { REPO_URL, VERSION } from "../components";

const COLS: Array<{ heading: string; links: Array<[string, string]> }> = [
  {
    heading: "Project",
    links: [
      ["GitHub", REPO_URL],
      ["Releases", `${REPO_URL}/releases`],
      ["Issues", `${REPO_URL}/issues`],
      ["Examples", `${REPO_URL}/tree/main/examples`],
    ],
  },
  {
    heading: "ClickHouse",
    links: [
      ["clickhouse.com", "https://clickhouse.com"],
      ["SQL playground", "https://sql.clickhouse.com"],
      ["Example datasets", "https://clickhouse.com/docs/getting-started/example-datasets"],
      ["click-ui", "https://github.com/ClickHouse/click-ui"],
    ],
  },
  {
    heading: "Common Lisp",
    links: [
      ["ECL", "https://ecl.common-lisp.dev/"],
      ["The Common Lisp HyperSpec", "https://www.lispworks.com/documentation/HyperSpec/Front/"],
    ],
  },
];

export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="footer-inner">
        <div className="footer-brand">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="clicklisp logo" width={36} height={36} style={{ borderRadius: 8 }} />
          <Text size="md" weight="semibold">
            clicklisp
          </Text>
          <Text color="muted" size="sm">
            The CL in ClickHouse. S-expressions in, ClickHouse out.
          </Text>
        </div>
        {COLS.map((col) => (
          <div className="footer-col" key={col.heading}>
            <div className="footer-heading">{col.heading}</div>
            {col.links.map(([label, href]) => (
              <a key={href} className="footer-link" href={href} target="_blank" rel="noreferrer">
                {label}
              </a>
            ))}
          </div>
        ))}
      </div>
      <div className="footer-bottom">
        <span>Apache-2.0 · {VERSION}</span>
        <span>
          Built with{" "}
          <a className="footer-link" href="https://github.com/ClickHouse/click-ui">
            @clickhouse/click-ui
          </a>
        </span>
      </div>
    </footer>
  );
}
