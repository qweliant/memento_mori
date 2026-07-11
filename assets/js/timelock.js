// drand timelock encryption in the browser.
//
// The whole point of the concept lives here: a message is encrypted on the
// device and locked to a future drand round. The server only ever receives the
// armored ciphertext. Opening asks the drand network for that round's key and is
// refused until the round has actually been emitted.
import {timelockEncrypt, timelockDecrypt, mainnetClient, Buffer} from "tlock-js"

// One shared client (points at drand quicknet, the timelock-capable chain).
const client = mainnetClient()

// Capsule artifact sealing. The round comes from the capsule's access contract
// (data-round), so every artifact in a capsule locks to the one unlock moment.
// Only the ciphertext is pushed to the server.
export const CapsuleSeal = {
  mounted() {
    const round = parseInt(this.el.dataset.round, 10)
    const btn = this.el.querySelector("[data-seal-submit]")
    btn.addEventListener("click", async () => {
      const filenameEl = this.el.querySelector("[data-seal-filename]")
      const noteEl = this.el.querySelector("[data-seal-note]")
      const statusEl = this.el.querySelector("[data-seal-status]")

      const note = noteEl.value || ""
      const filename = (filenameEl.value || "").trim()

      if (!note.trim()) {
        statusEl.textContent = "Write something to seal first."
        return
      }

      // Kind + template fields live outside this (ignored) hook subtree, in the
      // LiveView-managed part of the same panel. Read them across the panel.
      const panel = this.el.closest(".mm-panel")
      const kindEl = panel && panel.querySelector("[name=kind]")
      const kind = kindEl ? kindEl.value : "generic"

      const attrEls = panel ? panel.querySelectorAll("[data-seal-attr]") : []
      const attributes = {}
      let missing = null
      attrEls.forEach((el) => {
        const value = (el.value || "").trim()
        if (value) {
          attributes[el.dataset.sealAttr] = value
        } else if (el.dataset.sealRequired === "true" && !missing) {
          missing = el.placeholder.replace(/ \*$/, "")
        }
      })

      if (missing) {
        statusEl.textContent = "Still need: " + missing
        return
      }

      btn.disabled = true
      statusEl.textContent = "Sealing on your device…"

      try {
        const armored = await timelockEncrypt(round, Buffer.from(note, "utf8"), client)
        this.pushEvent("sealed", {
          filename: filename,
          armored_ciphertext: armored,
          kind: kind,
          attributes: attributes,
        })
        noteEl.value = ""
        filenameEl.value = ""
        attrEls.forEach((el) => (el.value = ""))
        statusEl.textContent = ""
      } catch (err) {
        statusEl.textContent = "Could not seal: " + (err && err.message ? err.message : err)
      } finally {
        btn.disabled = false
      }
    })
  },
}

// Opens a timelock-sealed artifact: reads the ciphertext from the element named
// in data-ciphertext-id and asks drand to decrypt. Refused until the round.
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
