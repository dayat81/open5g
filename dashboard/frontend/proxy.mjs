import { spawn } from "node:child_process";
import http from "node:http";
import { URL } from "node:url";

const listenHost = process.env.OPEN5G_WEB_HOST || "0.0.0.0";
const listenPort = Number(process.env.PORT || 3000);
const nextPort = Number(process.env.OPEN5G_NEXT_PORT || 3001);
const apiBase = new URL(process.env.OPEN5G_API_INTERNAL_URL || "http://dashboard-api:8000");

if (apiBase.protocol !== "http:") {
  process.stderr.write("OPEN5G_API_INTERNAL_URL must use http inside the lab network\n");
  process.exit(1);
}

const child = spawn(process.execPath, ["server.js"], {
  stdio: "inherit",
  env: {
    ...process.env,
    HOSTNAME: "127.0.0.1",
    PORT: String(nextPort),
  },
});

child.on("exit", (code) => {
  process.exit(code ?? 1);
});

function isApi(url) {
  return url === "/health" || url.startsWith("/health?") || url === "/api" || url.startsWith("/api/") || url.startsWith("/api?");
}

function forward(req, res, host, port, path) {
  const headers = { ...req.headers };
  delete headers.connection;
  headers.host = `${host}:${port}`;
  const upstream = http.request(
    {
      protocol: "http:",
      hostname: host,
      port,
      method: req.method,
      path,
      headers,
    },
    (up) => {
      res.writeHead(up.statusCode || 502, up.headers);
      up.pipe(res);
    },
  );
  upstream.on("error", () => {
    if (!res.headersSent) {
      res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    }
    res.end("upstream unavailable");
  });
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  const path = req.url || "/";
  if (isApi(path)) {
    const port = apiBase.port ? Number(apiBase.port) : 80;
    forward(req, res, apiBase.hostname, port, path);
    return;
  }
  forward(req, res, "127.0.0.1", nextPort, path);
});

server.listen(listenPort, listenHost, () => {
  process.stdout.write(`dashboard-web listening on ${listenHost}:${listenPort}\n`);
});

function shutdown() {
  server.close();
  child.kill("SIGTERM");
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
