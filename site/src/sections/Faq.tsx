import { Accordion, Text, Title } from "@clickhouse/click-ui";
import { Eyebrow, Section } from "../components";

const FAQS: Array<{ q: string; a: JSX.Element }> = [
  {
    q: "Why Common Lisp?",
    a: (
      <Text color="muted" size="sm">
        Because queries-as-data is what Lisp is for. S-expressions compose, diff, and test like any
        other data structure; macros generate whole families of queries with no templating language;
        and the REPL gives you a live-coding loop against your database. Also, ClickHouse had the
        letters C and L sitting right there.
      </Text>
    ),
  },
  {
    q: "What does it depend on at runtime?",
    a: (
      <Text color="muted" size="sm">
        Nothing. ECL compiles Lisp through C to a native, statically linked binary — a few MB after
        stripping. Copy it onto any Linux box of the same architecture and it runs.
      </Text>
    ),
  },
  {
    q: "Does it work with ClickHouse Cloud?",
    a: (
      <Text color="muted" size="sm">
        The compiler works everywhere — it just emits SQL, which you can send to Cloud, a self-managed
        server, or the public playground. clicklisp's executable UDFs need a self-managed server, where
        you can drop the binary into <code>user_scripts_path</code>; Cloud's UDF beta only accepts
        Python, so the native binary can't run there.
      </Text>
    ),
  },
  {
    q: "What about SQL injection?",
    a: (
      <Text color="muted" size="sm">
        Strings are escaped, identifiers are validated or backtick-quoted, and every infix expression
        is parenthesized, so precedence bugs are structurally impossible. Getting raw text into a query
        requires writing <code>(raw ...)</code> on purpose.
      </Text>
    ),
  },
];

export default function Faq() {
  return (
    <Section id="faq">
      <Eyebrow>FAQ</Eyebrow>
      <Title type="h2" className="section-title">
        Fair questions
      </Title>
      <div className="faq-list">
        {FAQS.map((f) => (
          <Accordion key={f.q} title={f.q} size="md">
            {f.a}
          </Accordion>
        ))}
      </div>
    </Section>
  );
}
