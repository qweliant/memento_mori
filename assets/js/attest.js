// Trustee attestation signing — proof-of-possession on top of the bearer link.
//
// Trust-on-first-use: the first time a trustee opens their attestation link, the
// browser generates a non-extractable ECDSA P-256 keypair, keeps the private key
// in IndexedDB (it never leaves the device), and registers the public key with
// the server. Every attestation is signed over "capsule_id|trustee_id|
// attested_at"; the server verifies it against the pinned public key. A leaked
// link alone can no longer confirm as the trustee.

const DB_NAME = "mm-trustee-keys"
const STORE = "keys"

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

async function idbGet(key) {
  const db = await openDb()
  return new Promise((resolve, reject) => {
    const req = db.transaction(STORE, "readonly").objectStore(STORE).get(key)
    req.onsuccess = () => resolve(req.result || null)
    req.onerror = () => reject(req.error)
  })
}

async function idbPut(key, value) {
  const db = await openDb()
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite")
    tx.objectStore(STORE).put(value, key)
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error)
  })
}

// One keypair per trustee, generated once and reused. The private key is
// non-extractable; public keys are always exportable, which is all we need.
async function ensureKeypair(trusteeId) {
  const existing = await idbGet(trusteeId)
  if (existing && existing.privateKey) return existing

  const kp = await crypto.subtle.generateKey({name: "ECDSA", namedCurve: "P-256"}, false, [
    "sign",
    "verify",
  ])
  await idbPut(trusteeId, kp)
  return kp
}

function toBase64(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

export async function initAttestSigner() {
  const form = document.querySelector("[data-attest-signer]")
  if (!form || !window.crypto || !window.crypto.subtle) return

  const capsuleId = form.dataset.capsuleId
  const trusteeId = form.dataset.trusteeId
  const pubEl = form.querySelector("[name=public_key]")
  const sigEl = form.querySelector("[name=signature]")
  const atEl = form.querySelector("[name=attested_at]")

  let keypair
  try {
    keypair = await ensureKeypair(trusteeId)
    pubEl.value = toBase64(await crypto.subtle.exportKey("raw", keypair.publicKey))
  } catch (err) {
    console.error("attest signer: key setup failed", err)
    return
  }

  form.addEventListener("submit", async (event) => {
    // Sign, fill the hidden fields, then re-submit programmatically (which does
    // not re-fire this handler). If signing fails we do NOT submit — fail closed.
    event.preventDefault()
    try {
      const attestedAt = new Date().toISOString()
      const message = new TextEncoder().encode(`${capsuleId}|${trusteeId}|${attestedAt}`)
      const signature = await crypto.subtle.sign(
        {name: "ECDSA", hash: "SHA-256"},
        keypair.privateKey,
        message
      )
      sigEl.value = toBase64(signature)
      atEl.value = attestedAt
      form.submit()
    } catch (err) {
      console.error("attest signer: signing failed", err)
    }
  })
}
