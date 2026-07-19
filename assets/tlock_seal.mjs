// Dev-only: seal a plaintext to a drand quicknet round with tlock-js, the same
// library the browser uses. Prints the armored ciphertext to stdout so the seeds
// script can store it as an artifact's ciphertext. Sealing to a round that has
// already been emitted makes the blob immediately openable in the UI.
//
//   node tlock_seal.mjs <round> <base64-plaintext>   -> armored ciphertext
//   node tlock_seal.mjs --selftest <round>           -> "OK" if encrypt/decrypt round-trips
import {timelockEncrypt, timelockDecrypt, mainnetClient, Buffer} from "tlock-js"

const client = mainnetClient()

async function seal(round, text) {
  return await timelockEncrypt(round, Buffer.from(text, "utf8"), client)
}

const [flagOrRound, arg2] = process.argv.slice(2)

if (flagOrRound === "--selftest") {
  const round = parseInt(arg2, 10)
  const armored = await seal(round, "hello from the past")
  const back = await timelockDecrypt(armored, client)
  process.stdout.write(back.toString("utf8") === "hello from the past" ? "OK" : "MISMATCH")
} else if (flagOrRound === "--decrypt") {
  // Read an armored blob from a file and print its plaintext (verification only).
  const {readFileSync} = await import("node:fs")
  const armored = readFileSync(arg2, "utf8")
  const back = await timelockDecrypt(armored, client)
  process.stdout.write(back.toString("utf8"))
} else {
  const round = parseInt(flagOrRound, 10)
  const text = Buffer.from(arg2, "base64").toString("utf8")
  process.stdout.write(await seal(round, text))
}
