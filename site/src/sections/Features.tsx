import { CardSecondary, GridContainer, Title } from "@clickhouse/click-ui";
import { Eyebrow, Section } from "../components";

const FEATURES = [
  {
    icon: "brackets",
    title: "A query compiler",
    description:
      "(select ...) forms become ClickHouse SQL. Queries are data: composable, diffable, testable.",
    infoUrl: "#language",
  },
  {
    icon: "plug",
    title: "Executable UDFs",
    description:
      "The same binary speaks ClickHouse's executable-UDF protocol. Call Lisp from SELECT.",
    infoUrl: "#udfs",
  },
  {
    icon: "rocket",
    title: "One static binary",
    description:
      "ECL compiles Lisp → C → native. A few MB, statically linked, runs on any Linux of its architecture.",
    infoUrl: "#get-started",
  },
  {
    icon: "flash",
    title: "Hot code reload",
    description:
      "--watch re-loads Lisp while the pool keeps serving queries. Live-code inside your database.",
    infoUrl: "#udfs",
  },
] as const;

export default function Features() {
  return (
    <Section>
      <div className="centered">
        <Eyebrow>Two halves that compose</Eyebrow>
        <Title type="h2" className="section-title">
          Built for queries that are programs
        </Title>
      </div>
      <GridContainer
        className="feature-grid"
        gridTemplateColumns="repeat(2, minmax(0, 1fr))"
        gap="md"
        fillWidth
      >
        {FEATURES.map((f) => (
          <CardSecondary
            key={f.title}
            icon={f.icon}
            title={f.title}
            description={f.description}
            infoText="Learn more"
            infoUrl={f.infoUrl}
          />
        ))}
      </GridContainer>
    </Section>
  );
}
