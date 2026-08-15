import React from "react";
import ReactDOM from "react-dom/client";
import { ClickUIProvider } from "@clickhouse/click-ui";
import DemoLayout from "../DemoLayout";
import { DEMOS } from "../registry";
import type { RulesJson } from "../types";
import data from "../../generated/hackernews.json";
import "../../styles.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ClickUIProvider theme="dark" persistTheme={false}>
      <DemoLayout demo={DEMOS["hackernews"]} data={data as unknown as RulesJson} />
    </ClickUIProvider>
  </React.StrictMode>
);
