import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Deployed to GitHub Pages at https://clickhouse.github.io/clicklisp/
export default defineConfig({
  base: "/clicklisp/",
  plugins: [react()],
});
