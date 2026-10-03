#!/usr/bin/env node
// Prints the line to run in the executor, for each LAN address of this PC
// (npm run loader). Same token as the server (mcp/.bridge-token).

import path from "node:path";
import { fileURLToPath } from "node:url";
import { lanAddresses, loaderLine, loadToken } from "./bridge.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const token = loadToken(path.join(root, ".bridge-token"));
const port = process.env.BRIDGE_PORT || 7777;
const addresses = lanAddresses();

if (addresses.length === 0) {
  console.log("No LAN address found: is the PC on a network?");
}
for (const address of addresses) {
  console.log(`[${address}]`);
  console.log(loaderLine(address, port, token));
  console.log("");
}
