import { Accordion, CodeBlock, Panel, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, Highlight, Section } from "../components";
import { udfDefinition, udfShell, udfSql, udfXml } from "../samples";

export default function Udfs() {
  return (
    <Section id="udfs">
      <div className="section-intro">
        <Eyebrow>Executable UDFs</Eyebrow>
        <Title type="h2" className="section-title">
          Call <Highlight>Lisp</Highlight> from SELECT
        </Title>
        <Text color="muted" size="md">
          Drop the binary into <code>user_scripts_path</code>, add one XML file, and ClickHouse streams
          rows through your functions over the executable-UDF protocol — TabSeparated over
          stdin/stdout, byte-transparent, with failing rows yielding <code>NULL</code> instead of
          killing the pool.
        </Text>
      </div>
      <div className="split mt-lg">
        <div className="stack">
          <CodePane>
            <CodeBlock language="plaintext">{udfDefinition}</CodeBlock>
          </CodePane>
          <CodePane>
            <CodeBlock language="bash">{udfShell}</CodeBlock>
          </CodePane>
          <CodePane>
            <CodeBlock language="sql">{udfSql}</CodeBlock>
          </CodePane>
        </div>
        <div className="stack">
          <Panel orientation="vertical" alignItems="start" padding="lg" gap="sm" hasBorder radii="md" color="muted">
            <Title type="h3" size="md">
              ⚡ Hot patching, mid-query
            </Title>
            <Text color="muted" size="sm">
              <code>--watch</code> re-loads a Lisp file whenever it changes, while the pool process keeps
              serving queries — using ECL's in-image bytecode compiler, so it works inside the UDF
              sandbox where no C toolchain exists. Edit the file, save, and the next block is served by
              the new definition.
            </Text>
            <Text color="muted" size="sm">
              <code>clicklisp repl</code> gives you the same live-coding loop locally.
            </Text>
          </Panel>
          <Accordion title="The XML that wires it up" size="md">
            <div className="mt-lg">
              <CodePane>
                <CodeBlock language="plaintext">{udfXml}</CodeBlock>
              </CodePane>
            </div>
          </Accordion>
        </div>
      </div>
    </Section>
  );
}
