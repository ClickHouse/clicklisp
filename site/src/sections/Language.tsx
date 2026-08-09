import { CodeBlock, Table, Tabs, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, Highlight, Section } from "../components";
import { fullSelect, languagePairs, macroExample } from "../samples";

export default function Language() {
  return (
    <Section id="language">
      <div className="section-intro">
        <Eyebrow>The query language</Eyebrow>
        <Title type="h2" className="section-title">
          Queries are <Highlight>data</Highlight>
        </Title>
        <Text color="muted" size="md">
          Operators and clause names are matched by symbol name, so forms can be written in any package
          and built as plain data. Strings are escaped, identifiers are validated, and every infix
          expression is parenthesized — precedence bugs are structurally impossible, and injection
          requires an explicit <code>(raw ...)</code>.
        </Text>
      </div>
      <div className="mt-lg">
        <Tabs defaultValue="select" ariaLabel="Query language examples">
          <Tabs.TriggersList>
            <Tabs.Trigger value="select">The full SELECT</Tabs.Trigger>
            <Tabs.Trigger value="cheatsheet">Lisp → SQL</Tabs.Trigger>
            <Tabs.Trigger value="macros">Macros</Tabs.Trigger>
          </Tabs.TriggersList>
          <Tabs.Content value="select">
            <div className="mt-lg">
              <CodePane>
                <CodeBlock language="plaintext">{fullSelect}</CodeBlock>
              </CodePane>
              <Text color="muted" size="sm" className="table-note">
                Clauses are emitted in proper ClickHouse order no matter how you write them, and the{" "}
                <code>sql</code> macro compiles at macroexpansion time — a rule library costs nothing at
                runtime.
              </Text>
            </div>
          </Tabs.Content>
          <Tabs.Content value="cheatsheet">
            <div className="mt-lg">
              <Table
                size="sm"
                headers={[{ label: "You write" }, { label: "ClickHouse runs" }, { label: "" }]}
                rows={languagePairs.map((p, i) => ({
                  id: i,
                  items: [
                    { label: <code>{p.lisp}</code> },
                    { label: <code>{p.sql}</code> },
                    {
                      label: p.note ? (
                        <Text component="span" color="muted" size="sm">
                          {p.note}
                        </Text>
                      ) : (
                        ""
                      ),
                    },
                  ],
                }))}
              />
              <Text color="muted" size="sm" className="table-note">
                Unknown functions map kebab-case → camelCase automatically; teach the compiler irregular
                spellings with <code>(define-sql-function my-fn "MyClickHouseName")</code>.
              </Text>
            </div>
          </Tabs.Content>
          <Tabs.Content value="macros">
            <div className="mt-lg">
              <CodePane>
                <CodeBlock language="plaintext">{macroExample}</CodeBlock>
              </CodePane>
              <Text color="muted" size="sm" className="table-note">
                Rule files are full Common Lisp — a macro stamps out a family of queries with no
                copy-paste and no templating language.
              </Text>
            </div>
          </Tabs.Content>
        </Tabs>
      </div>
    </Section>
  );
}
