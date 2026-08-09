import { CodeBlock, Link, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, Section } from "../components";
import { playgroundShell } from "../samples";

export default function Playground() {
  return (
    <Section id="playground">
      <div className="centered">
        <Eyebrow>Zero setup</Eyebrow>
        <Title type="h2" className="section-title">
          Real datasets, no server
        </Title>
        <Text color="muted" size="md" className="section-intro">
          sql.clickhouse.com hosts ClickHouse's example datasets behind a read-only HTTP endpoint.{" "}
          <code>scripts/play.sh</code> pipes SQL from stdin, so compiled queries run against real data
          with no server at all.
        </Text>
        <div className="mt-lg" style={{ width: "100%", maxWidth: 860 }}>
          <CodePane boxy>
            <CodeBlock language="plaintext">{playgroundShell}</CodeBlock>
          </CodePane>
        </div>
        <div className="mt-lg">
          <Link href="https://sql.clickhouse.com" target="_blank" rel="noreferrer" icon="arrow-right" size="md">
            Open the playground
          </Link>
        </div>
      </div>
    </Section>
  );
}
