import React from "react";
import ReactDOM from "react-dom/client";
import { ClickUIProvider } from "@clickhouse/click-ui";
import App from "./App";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ClickUIProvider theme="dark" persistTheme={false}>
      <App />
    </ClickUIProvider>
  </React.StrictMode>
);
