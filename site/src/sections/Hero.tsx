import { Badge, Button, CodeBlock, Icon, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, Highlight, REPO_URL, scrollToId, VERSION } from "../components";
import { heroLisp, heroSql } from "../samples";

export default function Hero() {
  return (
    <section className="hero" id="top">
      <div className="hero-inner">
        <div className="fade-up">
          <Badge text={`${VERSION} · Apache 2.0 · zero runtime dependencies`} state="neutral" icon="sparkle" />
        </div>
        <div className="fade-up">
          <Eyebrow>Common Lisp × ClickHouse</Eyebrow>
          <Title type="h1" className="hero-title">
            The <Highlight>CL</Highlight> in ClickHouse.
          </Title>
        </div>
        <Text color="muted" size="lg" className="hero-sub fade-up d1">
          Common Lisp was hiding in the first two letters the whole time. S-expressions in, ClickHouse SQL
          out — a query compiler and an executable-UDF runner in one small static binary.
        </Text>
        <div className="hero-ctas fade-up d2">
          <Button type="primary" iconRight="arrow-right" onClick={() => scrollToId("get-started")}>
            Get clicklisp
          </Button>
          <Button
            type="secondary"
            onClick={() => {
              window.open(REPO_URL, "_blank", "noopener");
            }}
          >
            View on GitHub
          </Button>
        </div>
        <div className="hero-code fade-up d3">
          <div className="hero-pane">
            <div className="pane-label">S-expressions in</div>
            <CodePane>
              <CodeBlock language="bash">{heroLisp}</CodeBlock>
            </CodePane>
          </div>
          <Icon name="arrow-right" size="lg" className="hero-arrow" />
          <div className="hero-pane">
            <div className="pane-label">ClickHouse SQL out</div>
            <CodePane>
              <CodeBlock language="sql" wrapLines>
                {heroSql}
              </CodeBlock>
            </CodePane>
          </div>
        </div>
      </div>
    </section>
  );
}
