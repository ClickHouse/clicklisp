import { CodeBlock, Link, Panel, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, Highlight, REPO_URL, Section } from "../components";
import { installShell } from "../samples";

export default function GetStarted() {
  return (
    <Section id="get-started">
      <Panel
        className="get-started-panel"
        orientation="vertical"
        alignItems="center"
        padding="xl"
        gap="sm"
        hasBorder
        radii="lg"
        color="muted"
      >
        <Eyebrow>Get started</Eyebrow>
        <Title type="h2" className="section-title">
          Start compiling in <Highlight>seconds</Highlight>
        </Title>
        <Text color="muted" size="md">
          Build from source with ECL, or grab a static Linux binary from the releases page.
        </Text>
        <CodePane>
          <CodeBlock language="bash">{installShell}</CodeBlock>
        </CodePane>
        <div className="link-row">
          <Link href={`${REPO_URL}/releases/latest`} icon="arrow-right" size="md">
            Latest release
          </Link>
          <Link href={`${REPO_URL}#readme`} icon="arrow-right" size="md">
            Read the README
          </Link>
          <Link href={`${REPO_URL}/tree/main/examples`} icon="arrow-right" size="md">
            Browse the examples
          </Link>
        </div>
      </Panel>
    </Section>
  );
}
