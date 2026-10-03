// The HTTP bridge against a fake in-game client.

import { test, after, before } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Bridge, Ring, luaPathFor } from "./helpers.js";
import { addressRank } from "../src/bridge.js";

let bridge;
let base;
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "bridge-"));
const cobalt = path.join(tmp, "Cobalt.luau");
fs.writeFileSync(cobalt, "-- cobalt source");

before(async () => {
  bridge = new Bridge({ port: 0, host: "127.0.0.1", token: "secret", luaPath: luaPathFor(), cobaltPath: cobalt });
  bridge.pollWait = 200;
  await bridge.start();
  base = `http://127.0.0.1:${bridge.port}`;
});

after(async () => {
  await bridge.stop();
});

const get = (route) => fetch(`${base}${route}${route.includes("?") ? "&" : "?"}token=secret`);
const post = (route, body) => fetch(`${base}${route}?token=secret`, {
  method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
});

test("a wrong token is refused", async () => {
  const response = await fetch(`${base}/poll?token=nope`);
  assert.equal(response.status, 403);
});

test("the client script comes with host, port and token filled in", async () => {
  const response = await get("/bridge.lua");
  const source = await response.text();
  assert.equal(response.status, 200);
  assert.ok(source.includes('token = "secret"'));
  assert.ok(source.includes(`port = "${bridge.port}"`));
  assert.ok(!source.includes("{{"));
  assert.equal(Number(response.headers.get("content-length")), Buffer.byteLength(source));
  assert.equal(response.headers.get("transfer-encoding"), null);
});

test("Cobalt is served from COBALT_PATH", async () => {
  const response = await get("/cobalt");
  assert.equal(await response.text(), "-- cobalt source");
});

test("hello records the session; a call goes through poll and result", async () => {
  await post("/hello", { placeId: 4442272183, player: "Tester" });
  assert.equal(bridge.session.player, "Tester");
  assert.ok(bridge.connected());
  const pending = bridge.call("exec", { code: "return 1" }, 2000);
  const polled = await (await get("/poll")).json();
  assert.equal(polled.op, "exec");
  assert.deepEqual(polled.args, { code: "return 1" });
  await post("/result", { id: polled.id, ok: true, result: { returns: [1] } });
  assert.deepEqual(await pending, { returns: [1] });
});

test("a poll waiting first gets the next command", async () => {
  const polling = get("/poll").then((response) => response.json());
  await new Promise((resolve) => setTimeout(resolve, 20));
  const pending = bridge.call("player", {}, 2000);
  const polled = await polling;
  assert.equal(polled.op, "player");
  const rejected = assert.rejects(pending, /no local player/);
  await post("/result", { id: polled.id, ok: false, error: "no local player" });
  await rejected;
});

test("an empty poll ends with 204", async () => {
  const response = await get("/poll");
  assert.equal(response.status, 204);
});

test("a call nobody answers times out", async () => {
  await assert.rejects(bridge.call("tree", {}, 50), /did not answer|no game connected/);
  assert.equal(bridge.queue.length, 0);
});

test("events fill the console and remote buffers", async () => {
  await post("/events", {
    console: [{ text: "hello", type: "output" }],
    remotes: [{ direction: "Outgoing", remote: "game.ReplicatedStorage.Remotes.CommF_", args: ["requestEntrance"] }],
    session: { cobalt: true },
  });
  assert.equal(bridge.console.since(0).at(-1).text, "hello");
  assert.equal(bridge.remotes.since(0).at(-1).args[0], "requestEntrance");
  assert.equal(bridge.session.cobalt, true);
});

test("the ring keeps the newest entries", () => {
  const ring = new Ring(3);
  for (let i = 1; i <= 5; i += 1) ring.push({ n: i });
  assert.deepEqual(ring.since(0).map((item) => item.n), [3, 4, 5]);
  assert.deepEqual(ring.since(4).map((item) => item.n), [5]);
});

test("the loader line points at the bridge", () => {
  assert.equal(bridge.loader("10.0.0.5"),
    `loadstring(game:HttpGet("http://10.0.0.5:${bridge.port}/bridge.lua?token=secret"))()`);
});

test("the home network address comes before virtual and self-assigned ones", () => {
  const sorted = ["169.254.83.107", "192.168.56.1", "192.168.1.145"].sort((a, b) => addressRank(a) - addressRank(b));
  assert.deepEqual(sorted, ["192.168.1.145", "192.168.56.1", "169.254.83.107"]);
});
