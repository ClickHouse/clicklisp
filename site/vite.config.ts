import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Deployed to GitHub Pages behind the custom domain https://cl.clickhouse.com/
// (served from the root — if the custom domain is ever removed, the site moves
// back under https://clickhouse.github.io/clicklisp/ and base must become
// "/clicklisp/" again).
export default defineConfig({
  base: "/",
  plugins: [react()],
});
