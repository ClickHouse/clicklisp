import { CodeBlock, Icon, Text, Title } from "@clickhouse/click-ui";
import { CodePane, Eyebrow, REPO_URL, Section, useGitHubStars } from "../components";
import type { Demo } from "./registry";
import type { RulesJson } from "./types";
import RuleCard from "./RuleCard";

// Shared chrome + body for the four demo pages. Landing-page anchors must be
// absolute paths ("/#demos") — a bare #hash does not cross pages.
export default function DemoLayout({ demo, data }: Readonly<{ demo: Demo; data: RulesJson }>) {
  const stars = useGitHubStars();
  return (
    <>
      <header className="site-header">
        <div className="header-inner">
          <a className="brand" href="/">
            <img src={`${import.meta.env.BASE_URL}logo.png`} alt="clicklisp logo" width={28} height={28} />
            <Text component="span" size="md" weight="semibold">
              clicklisp
            </Text>
          </a>
          <nav className="header-nav">
            <a className="nav-link" href="/#demos">
              All demos
            </a>
          </nav>
          <div className="header-spacer" />
          <a className="gh-link" href={REPO_URL} target="_blank" rel="noreferrer">
            <Icon name="github" size="sm" />
            <span>{stars ? `★ ${stars}` : "GitHub"}</span>
          </a>
        </div>
      </header>
      <main>
        <Section className="demo-page">
          <Eyebrow>Live demo</Eyebrow>
          <Title type="h1" className="section-title">
            {demo.title}
          </Title>
          <div className="demo-lede">
            <Text color="muted" size="md">
              {demo.blurb}
            </Text>
            <Text color="muted" size="sm">
              Dataset:{" "}
              <a className="footer-link" href={demo.datasetHref} target="_blank" rel="noreferrer">
                {demo.dataset}
              </a>
              {" · "}rules compiled from{" "}
              {demo.exampleFiles.map((href, i) => (
                <span key={href}>
                  {i > 0 && ", "}
                  <a className="footer-link" href={href} target="_blank" rel="noreferrer">
                    {href.split("/").slice(-1)[0]}
                  </a>
                </span>
              ))}
              {" "}with clicklisp {data.clicklisp}. Runs in your browser against the read-only public
              playground.
            </Text>
          </div>
          <div className="demo-load">
            <div className="pane-label">Run it yourself from a checkout</div>
            <CodePane>
              <CodeBlock language="bash" wrapLines>
                {demo.loadCommand}
              </CodeBlock>
            </CodePane>
          </div>
          <div className="rule-list">
            {data.rules.map((rule) => (
              <RuleCard key={rule.name} rule={rule} demo={demo} />
            ))}
          </div>
        </Section>
      </main>
      <footer className="site-footer">
        <div className="footer-bottom">
          <span>Apache-2.0 · clicklisp demos</span>
          <span>
            Queries run against the public{" "}
            <a className="footer-link" href="https://sql.clickhouse.com" target="_blank" rel="noreferrer">
              ClickHouse SQL playground
            </a>
          </span>
        </div>
      </footer>
    </>
  );
}
