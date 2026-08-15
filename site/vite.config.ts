import { resolve } from "node:path";
import { defineConfig, type Plugin } from "vite";
import react from "@vitejs/plugin-react";

// Defense-in-depth: GitHub Pages cannot set real response headers, so the
// Content-Security-Policy ships as a <meta> tag baked into every page at
// build time. The policy is centralized here — this is the only place it is
// defined. Build-only on purpose: dev mode needs Vite's inline react-refresh
// preamble, which this policy would block.
const CSP =
  "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src https://sql-clickhouse.clickhouse.com https://api.github.com; base-uri 'none'; form-action 'none'; object-src 'none'; frame-src 'none'; manifest-src 'self'";

function cspPlugin(): Plugin {
  return {
    name: "csp-meta",
    apply: "build",
    transformIndexHtml() {
      return [
        {
          tag: "meta",
          attrs: { "http-equiv": "Content-Security-Policy", content: CSP },
          injectTo: "head-prepend",
        },
      ];
    },
  };
}

// Deployed to GitHub Pages behind the custom domain https://cl.clickhouse.com/
// (served from the root — if the custom domain is ever removed, the site moves
// back under https://clickhouse.github.io/clicklisp/ and base must become
// "/clicklisp/" again).
export default defineConfig({
  base: "/",
  plugins: [react(), cspPlugin()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(import.meta.dirname, "index.html"),
        "github-threats": resolve(import.meta.dirname, "github-threats/index.html"),
        "uk-price-paid": resolve(import.meta.dirname, "uk-price-paid/index.html"),
        hackernews: resolve(import.meta.dirname, "hackernews/index.html"),
        "repo-health": resolve(import.meta.dirname, "repo-health/index.html"),
      },
    },
  },
});
