import { CardSecondary, GridContainer, Text, Title } from "@clickhouse/click-ui";
import { Eyebrow, Section } from "../components";
import { DEMOS, DEMO_ORDER } from "../demos/registry";

export default function Demos() {
  return (
    <Section id="demos">
      <div className="centered">
        <Eyebrow>Live demos</Eyebrow>
        <Title type="h2" className="section-title">
          Rule packs running on real data
        </Title>
        <Text color="muted" size="md" className="section-intro">
          Four query libraries compiled by clicklisp at build time, runnable in your browser against
          the public ClickHouse playground.
        </Text>
      </div>
      <GridContainer
        className="feature-grid"
        gridTemplateColumns="repeat(2, minmax(0, 1fr))"
        gap="md"
        fillWidth
      >
        {DEMO_ORDER.map((slug) => {
          const demo = DEMOS[slug];
          return (
            <CardSecondary
              key={demo.slug}
              icon={demo.icon}
              title={demo.title}
              description={demo.blurb}
              infoText="Open demo"
              infoUrl={`/${demo.slug}/`}
            />
          );
        })}
      </GridContainer>
    </Section>
  );
}
