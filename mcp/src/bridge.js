// The local HTTP bridge between the MCP server and the in-game client
// (lua/bridge.lua running in the executor).
//
//   GET  /bridge.lua   the in-game client, host/port/token filled in
//   GET  /cobalt       the user's Cobalt.luau (COBALT_PATH)
//   POST /hello        the client says who it is (place, player, executor...)
//   GET  /poll         long poll: the next command, or 204 after POLL_WAIT
//   POST /result       the answer to a command: { id, ok, result, error }
//   POST /events       console lines and remote calls, in batches
//
// Every request carries the token (?token= or the X-Token header): the
// bridge listens on every interface because the emulator reaches the PC
// through its LAN address.

import http from "node:http";
import os from "node:os";
import fs from "node:fs";
import crypto from "node:crypto";

export const POLL_WAIT = 20_000;   // ms a poll is held open
export const SEEN_FOR = 45_000;    // ms since the last poll for "connected"

// A fixed-size buffer with a running sequence number per entry.
export class Ring {
  constructor(size) {
    this.size = size;
    this.items = [];
    this.seq = 0;
  }
  push(entry) {
    this.seq += 1;
    this.items.push({ seq: this.seq, at: Date.now(), ...entry });
    if (this.items.length > this.size) this.items.splice(0, this.items.length - this.size);
  }
  since(seq = 0) {
    return this.items.filter((item) => item.seq > seq);
  }
  clear() {
    this.items = [];
  }
}

// The PC's IPv4 LAN addresses (MuMu reaches the PC through one of them),
// the home network first (192.168.1.x...), virtual adapters (VirtualBox's
// 192.168.56.x) next, self-assigned 169.254.x.x (no network) last.
export function addressRank(address) {
  if (address.startsWith("169.254.")) return 3;
  if (address.startsWith("192.168.56.")) return 1;
  if (address.startsWith("192.168.") || address.startsWith("10.")) return 0;
  return 2;
}

export function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const nic of list || []) {
      if (nic.family === "IPv4" && !nic.internal) out.push(nic.address);
    }
  }
  return out.sort((a, b) => addressRank(a) - addressRank(b));
}

// The token, created once and kept next to the server.
export function loadToken(file) {
  try {
    const saved = fs.readFileSync(file, "utf8").trim();
    if (saved) return saved;
  } catch {}
  const token = crypto.randomBytes(16).toString("hex");
  try { fs.writeFileSync(file, token + "\n"); } catch {}
  return token;
}

function readBody(req, limit = 8 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new Error("body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

export class Bridge {
  constructor({ port = 7777, host = "0.0.0.0", token, luaPath, cobaltPath, log = () => {} } = {}) {
    this.port = port;
    this.host = host;
    this.token = token || crypto.randomBytes(16).toString("hex");
    this.luaPath = luaPath;
    this.cobaltPath = cobaltPath;
    this.log = log;
    this.queue = [];          // commands waiting for a poll
    this.waiters = [];        // polls waiting for a command
    this.pending = new Map(); // id -> { resolve, reject, timer }
    this.nextId = 1;
    this.session = null;
    this.lastSeen = 0;
    this.console = new Ring(2000);
    this.remotes = new Ring(5000);
  }

  connected() {
    return this.lastSeen > 0 && Date.now() - this.lastSeen < SEEN_FOR;
  }

  // The line to run in the executor.
  loader(address) {
    const host = address || lanAddresses()[0] || "127.0.0.1";
    return `loadstring(game:HttpGet("http://${host}:${this.port}/bridge.lua?token=${this.token}"))()`;
  }

  // The in-game client with its placeholders filled in.
  clientScript(hostHeader) {
    const source = fs.readFileSync(this.luaPath, "utf8");
    const host = (hostHeader || "").split(":")[0] || lanAddresses()[0] || "127.0.0.1";
    return source
      .replaceAll("{{HOST}}", host)
      .replaceAll("{{PORT}}", String(this.port))
      .replaceAll("{{TOKEN}}", this.token);
  }

  // Sends `op` to the game; resolves with its result, rejects on error or
  // when nothing answers within `timeout` ms.
  call(op, args = {}, timeout = 30_000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        this.queue = this.queue.filter((command) => command.id !== id);
        reject(new Error(this.connected()
          ? `the game did not answer "${op}" within ${Math.round(timeout / 1000)} s`
          : "no game connected: run the loader line (get_loader) in the executor"));
      }, timeout);
      this.pending.set(id, { resolve, reject, timer });
      this.dispatch({ id, op, args });
    });
  }

  dispatch(command) {
    const waiter = this.waiters.shift();
    if (waiter) waiter(command);
    else this.queue.push(command);
  }

  answer({ id, ok, result, error }) {
    const entry = this.pending.get(id);
    if (!entry) return;
    clearTimeout(entry.timer);
    this.pending.delete(id);
    if (ok) entry.resolve(result);
    else entry.reject(new Error(String(error ?? "error in game")));
  }

  events(body) {
    for (const line of body.console || []) this.console.push(line);
    for (const call of body.remotes || []) this.remotes.push(call);
    if (body.session && typeof body.session === "object") this.session = { ...this.session, ...body.session };
  }

  authorized(req, url) {
    return url.searchParams.get("token") === this.token || req.headers["x-token"] === this.token;
  }

  async handle(req, res) {
    const url = new URL(req.url, "http://bridge");
    // Always a Content-Length: without it Node answers in chunks, and some
    // executors' HttpGet (Arceus X) read a chunked answer as empty.
    const send = (status, body, type = "application/json") => {
      const text = type === "application/json" && typeof body !== "string" ? JSON.stringify(body) : String(body);
      res.writeHead(status, {
        "content-type": type.startsWith("text/") ? `${type}; charset=utf-8` : type,
        "content-length": Buffer.byteLength(text),
      });
      res.end(text);
    };
    if (!this.authorized(req, url)) return send(403, { error: "bad token" });

    try {
      if (req.method === "GET" && url.pathname === "/bridge.lua") {
        return send(200, this.clientScript(req.headers.host), "text/plain");
      }
      if (req.method === "GET" && url.pathname === "/cobalt") {
        if (!this.cobaltPath || !fs.existsSync(this.cobaltPath)) {
          return send(404, `-- Cobalt.luau not found at ${this.cobaltPath}`, "text/plain");
        }
        return send(200, fs.readFileSync(this.cobaltPath, "utf8"), "text/plain");
      }
      if (req.method === "POST" && url.pathname === "/hello") {
        this.lastSeen = Date.now();
        this.session = { ...JSON.parse((await readBody(req)) || "{}"), since: new Date().toISOString() };
        // A new client: commands sent to the old one are lost with it.
        this.log(`game connected: ${JSON.stringify(this.session)}`);
        return send(200, { ok: true });
      }
      if (req.method === "GET" && url.pathname === "/poll") {
        this.lastSeen = Date.now();
        const command = this.queue.shift();
        if (command) return send(200, command);
        let done = false;
        const timer = setTimeout(() => {
          if (done) return;
          done = true;
          this.waiters = this.waiters.filter((waiter) => waiter !== deliver);
          res.writeHead(204, { "content-length": 0 });
          res.end();
        }, this.pollWait ?? POLL_WAIT);
        const deliver = (next) => {
          if (done) return this.queue.unshift(next);
          done = true;
          clearTimeout(timer);
          this.lastSeen = Date.now();
          send(200, next);
        };
        this.waiters.push(deliver);
        req.on("close", () => {
          if (!done) {
            done = true;
            clearTimeout(timer);
            this.waiters = this.waiters.filter((waiter) => waiter !== deliver);
          }
        });
        return;
      }
      if (req.method === "POST" && url.pathname === "/result") {
        this.lastSeen = Date.now();
        this.answer(JSON.parse(await readBody(req)));
        return send(200, { ok: true });
      }
      if (req.method === "POST" && url.pathname === "/events") {
        this.lastSeen = Date.now();
        this.events(JSON.parse(await readBody(req)));
        return send(200, { ok: true });
      }
      return send(404, { error: "unknown path" });
    } catch (error) {
      return send(400, { error: String(error.message || error) });
    }
  }

  start() {
    this.server = http.createServer((req, res) => { this.handle(req, res); });
    return new Promise((resolve, reject) => {
      this.server.once("error", reject);
      this.server.listen(this.port, this.host, () => {
        this.port = this.server.address().port;
        resolve(this);
      });
    });
  }

  stop() {
    for (const { reject, timer } of this.pending.values()) {
      clearTimeout(timer);
      reject(new Error("bridge stopped"));
    }
    this.pending.clear();
    if (!this.server) return Promise.resolve();
    return new Promise((resolve) => {
      this.server.close(() => resolve());
      this.server.closeAllConnections?.();
    });
  }
}
