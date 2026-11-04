import "phoenix_html"
import {initPwa} from "./pwa_client"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const Hooks = {
  Watchlist: {
    mounted() {
      this.storageKey = "evolving-minds:watchlist:v1"
      this.restore = raw => {
        try {
          const ids = JSON.parse(raw || "[]")
          if (Array.isArray(ids)) this.pushEvent("restore_watchlist", {ids: ids.filter(id => typeof id === "string").slice(0, 12)})
        } catch (_) { /* Invalid or unavailable storage never prevents observing. */ }
      }
      try { this.restore(localStorage.getItem(this.storageKey)) } catch (_) {}
      this.onStorage = event => { if (event.key === this.storageKey) this.restore(event.newValue) }
      window.addEventListener("storage", this.onStorage)
    },
    updated() {
      try { localStorage.setItem(this.storageKey, this.el.dataset.watchlist) } catch (_) {}
    },
    destroyed() { window.removeEventListener("storage", this.onStorage) }
  },
  Dialog: {
    mounted() {
      this.previousFocus = document.activeElement
      document.documentElement.classList.add("has-dialog")
      this.dialog = this.el.querySelector("[role=dialog]")
      requestAnimationFrame(() => this.dialog.focus())
      this.onKey = event => {
        const guide = document.getElementById("field-guide-dialog")
        if (guide && guide !== this.el) return
        if (event.key === "Escape") {
          event.preventDefault()
          this.pushEvent(this.el.dataset.closeEvent, {})
        }
        if (event.key === "Tab") {
          const elements = [...this.dialog.querySelectorAll('a[href],button:not([disabled]),input,select,summary,[tabindex="0"]')].filter(el => el.getClientRects().length)
          const first = elements[0], last = elements[elements.length - 1]
          if (!first) { event.preventDefault(); this.dialog.focus(); return }
          if (event.shiftKey && (document.activeElement === first || document.activeElement === this.dialog)) { event.preventDefault(); last.focus() }
          else if (!event.shiftKey && (document.activeElement === last || document.activeElement === this.dialog)) { event.preventDefault(); first.focus() }
        }
      }
      document.addEventListener("keydown", this.onKey)
    },
    destroyed() {
      document.removeEventListener("keydown", this.onKey)
      if (![...document.querySelectorAll(".dialog-backdrop")].some(el => el !== this.el)) document.documentElement.classList.remove("has-dialog")
      if (this.previousFocus?.isConnected) this.previousFocus.focus()
    }
  },
  CopyLink: {
    mounted() {
      this.copy = async () => {
        try {
          await navigator.clipboard.writeText(window.location.href)
          this.el.textContent = "Link copied ✓"
          this.el.setAttribute("aria-live", "polite")
        } catch (_) { this.el.textContent = "Copy the address bar link" }
      }
      this.el.addEventListener("click", this.copy)
    },
    destroyed() { this.el.removeEventListener("click", this.copy) }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})
topbar.config({barColors: {0: "#b9efd2"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
liveSocket.connect()

initPwa()
