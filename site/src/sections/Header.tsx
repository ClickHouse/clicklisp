import { Button, Icon, Text } from "@clickhouse/click-ui";
import { REPO_URL, scrollToId, useGitHubStars } from "../components";

const NAV: Array<[string, string]> = [
  ["Language", "#language"],
  ["Rules", "#rules"],
  ["UDFs", "#udfs"],
  ["Playground", "#playground"],
  ["FAQ", "#faq"],
];

export default function Header() {
  const stars = useGitHubStars();
  return (
    <header className="site-header">
      <div className="header-inner">
        <a className="brand" href="#top">
          <img src={`${import.meta.env.BASE_URL}logo.png`} alt="clicklisp logo" width={28} height={28} />
          <Text component="span" size="md" weight="semibold">
            clicklisp
          </Text>
        </a>
        <nav className="header-nav">
          {NAV.map(([label, href]) => (
            <a key={href} className="nav-link" href={href}>
              {label}
            </a>
          ))}
        </nav>
        <div className="header-spacer" />
        <a className="gh-link" href={REPO_URL} target="_blank" rel="noreferrer">
          <Icon name="github" size="sm" />
          <span>{stars ? `★ ${stars}` : "GitHub"}</span>
        </a>
        <Button type="primary" onClick={() => scrollToId("get-started")}>
          Get started
        </Button>
      </div>
    </header>
  );
}
