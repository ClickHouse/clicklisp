import { ReactNode, useEffect, useState } from "react";

export const REPO_URL = "https://github.com/ClickHouse/clicklisp";
export const VERSION = "v0.1.1";

// Yellow uppercase section label, clickhouse.com-style.
export function Eyebrow({ children }: Readonly<{ children: ReactNode }>) {
  return <div className="eyebrow">{children}</div>;
}

// The skewed yellow "highlighter" behind a heading word.
export function Highlight({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <span className="highlight">
      <span className="highlight-text">{children}</span>
    </span>
  );
}

export function Section({
  id,
  className,
  children,
}: Readonly<{
  id?: string;
  className?: string;
  children: ReactNode;
}>) {
  return (
    <section id={id} className={className ? `section ${className}` : "section"}>
      <div className="section-inner">{children}</div>
    </section>
  );
}

// Border + radius around click-ui CodeBlocks so they read as terminal panels.
// `boxy` switches to a system mono stack whose box-drawing glyphs align
// (Inconsolata has none, so table borders would render from a fallback font).
export function CodePane({ children, boxy }: Readonly<{ children: ReactNode; boxy?: boolean }>) {
  return <div className={boxy ? "codewrap boxy" : "codewrap"}>{children}</div>;
}

// Assigning location.hash is a no-op when the hash is already set, leaving
// the CTA dead on a second click — scrollIntoView always scrolls (and picks
// up the CSS scroll-behavior, including its reduced-motion override).
export function scrollToId(id: string) {
  document.getElementById(id)?.scrollIntoView();
  history.replaceState(null, "", `#${id}`);
}

export function useGitHubStars(): string | null {
  const [stars, setStars] = useState<string | null>(null);
  useEffect(() => {
    let cancelled = false;
    fetch("https://api.github.com/repos/ClickHouse/clicklisp")
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        if (!cancelled && d && typeof d.stargazers_count === "number") {
          const n = d.stargazers_count as number;
          setStars(n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));
        }
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);
  return stars;
}
