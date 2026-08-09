import { CodeBlock, Icon, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, REPO_URL, Section } from "../components";
import { ruleExample, rulesCli } from "../samples";

const POINTS = [
  "Rules are validated — compiled — at load time, and rendered to SQL on demand.",
  "Severity and ATT&CK-style tags live next to the query, not in a wiki.",
  "defquery is defrule minus the detection metadata: named query libraries for any domain.",
];

export default function Rules() {
  return (
    <Section id="rules">
      <div className="section-intro">
        <Eyebrow>Detection rules</Eyebrow>
        <Title type="h2" className="section-title">
          A rule library, not SQL string blobs
        </Title>
      </div>
      <div className="split">
        <div className="stack">
          <Text color="muted" size="md">
            Detection content lives in a library of forms instead of copy-pasted SQL. Diff it, review
            it, generate it with macros.
          </Text>
          {POINTS.map((p) => (
            <div className="bullet" key={p}>
              <Icon name="check-in-circle" size="sm" />
              <Text size="sm">{p}</Text>
            </div>
          ))}
          <CodePane>
            <CodeBlock language="bash">{rulesCli}</CodeBlock>
          </CodePane>
        </div>
        <div className="stack fill-pane">
          <CodePane>
            <CodeBlock language="plaintext">{ruleExample}</CodeBlock>
          </CodePane>
        </div>
      </div>
      <Text color="muted" size="sm" className="table-note">
        See{" "}
        <a className="footer-link" href={`${REPO_URL}/blob/main/examples/rules.lisp`}>
          examples/rules.lisp
        </a>{" "}
        and the analytics libraries in{" "}
        <a className="footer-link" href={`${REPO_URL}/tree/main/examples/analytics`}>
          examples/analytics/
        </a>.
      </Text>
    </Section>
  );
}
