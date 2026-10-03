import path from "node:path";
import { fileURLToPath } from "node:url";

export { Bridge, Ring } from "../src/bridge.js";

export const luaPathFor = () =>
  path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "lua", "bridge.lua");

// A bridge stand-in: records calls, answers from a table.
export class FakeBridge {
  constructor(answers = {}) {
    this.answers = answers;
    this.calls = [];
    this.lastSeen = Date.now();
    this.session = { player: "Tester" };
    this.port = 7777;
    this.token = "t";
    const ring = () => ({
      items: [], seq: 0,
      push(entry) { this.seq += 1; this.items.push({ seq: this.seq, ...entry }); },
      since(seq = 0) { return this.items.filter((item) => item.seq > seq); },
      clear() { this.items = []; },
    });
    this.console = ring();
    this.remotes = ring();
  }
  connected() { return true; }
  loader(address) { return `loader ${address || "lan"}`; }
  async call(op, args, timeout) {
    this.calls.push({ op, args, timeout });
    const answer = this.answers[op];
    if (answer instanceof Error) throw answer;
    return typeof answer === "function" ? answer(args) : answer;
  }
}
