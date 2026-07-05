// drand timelock encryption in the browser.
//
// The whole point of the concept lives here: the secret is encrypted on the
// device and locked to a future drand round. The server only ever receives the
// armored ciphertext. Opening asks the drand network for that round's key and is
// refused until the round has actually been emitted.
import {
  timelockEncrypt,
  timelockDecrypt,
  roundAt,
  defaultChainInfo,
  mainnetClient,
  Buffer,
} from "tlock-js"

// One shared client (points at drand quicknet, the timelock-capable chain).
const client = mainnetClient()

export const TimelockSeal = {
  mounted() {
    const btn = this.el.querySelector("[data-seal-submit]")
    btn.addEventListener("click", async () => {
      const labelEl = this.el.querySelector("[data-seal-label]")
      const secretEl = this.el.querySelector("[data-seal-secret]")
      const durationEl = this.el.querySelector("[data-seal-duration]")
      const statusEl = this.el.querySelector("[data-seal-status]")

      const label = (labelEl.value || "").trim()
      const secret = secretEl.value || ""
      const seconds = parseInt(durationEl.value, 10)

      if (!secret.trim()) {
        statusEl.textContent = "Write a message first."
        return
      }

      btn.disabled = true
      statusEl.textContent = "Sealing on your device…"

      try {
        const unlockAt = new Date(Date.now() + seconds * 1000)
        const round = roundAt(unlockAt.getTime(), defaultChainInfo)
        const armored = await timelockEncrypt(round, Buffer.from(secret, "utf8"), client)

        this.pushEvent("sealed", {
          label: label,
          armored_ciphertext: armored,
          unlock_round: round,
          unlock_at: unlockAt.toISOString(),
        })

        secretEl.value = ""
        labelEl.value = ""
        statusEl.textContent = ""
      } catch (err) {
        statusEl.textContent = "Could not seal: " + (err && err.message ? err.message : err)
      } finally {
        btn.disabled = false
      }
    })
  },
}

export const TimelockOpen = {
  mounted() {
    this.el.addEventListener("click", async () => {
      const ctEl = document.getElementById(this.el.dataset.ciphertextId)
      const target = document.querySelector(this.el.dataset.target)
      if (!ctEl || !target) return

      const original = this.el.innerHTML
      this.el.disabled = true
      this.el.textContent = "Opening…"

      try {
        const bytes = await timelockDecrypt(ctEl.textContent, client)
        target.textContent = new TextDecoder().decode(bytes)
        target.classList.remove("hidden")
        this.el.classList.add("hidden")
        this.pushEvent("opened", {id: this.el.dataset.id})
      } catch (err) {
        // Most commonly: "It's too early to decrypt … decryptable at round N".
        target.textContent = "🔒 " + (err && err.message ? err.message : err)
        target.classList.remove("hidden")
        this.el.disabled = false
        this.el.innerHTML = original
      }
    })
  },
}
