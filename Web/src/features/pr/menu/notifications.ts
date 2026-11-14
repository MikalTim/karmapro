// New pull request alerts in the browser: the Web Notification, the in-page toast with Review and Ignore, and
// the sound. The server sends `pr.notify` only when the user wants alerts, so nothing is decided here about that.
import { mount } from "svelte";
import { on } from "../../../lib/events";
import PRToasts from "./PRToasts.svelte";
import { needsPermissionRequest, notifyStyleOf, toastKey } from "./notifyPolicy";
import { reviewPullRequest } from "./reviewActions";
import { dismissToast, pushToast } from "./toasts.svelte";
import type { PRNotification, PRNotifyEvent, PRState } from "./prTypes";

let started = false;
// Asked once per page load: a permission prompt the user dismissed would otherwise come back on every poll.
let permissionAsked = false;

/** Call once at launch. Subscribes to the alerts and mounts the toast layer. */
export function startPRNotifications(): void {
  if (started) return;
  started = true;

  on<PRState>("pr.changed", (state) => {
    if (typeof Notification === "undefined") return;
    if (!permissionAsked && needsPermissionRequest(notifyStyleOf(state), Notification.permission)) {
      permissionAsked = true;
      void Notification.requestPermission();
    }
  });
  on<PRNotifyEvent>("pr.notify", (event) => {
    for (const item of event.items) {
      pushToast(item);
      if (typeof Notification !== "undefined" && Notification.permission === "granted") showSystemNotice(item);
    }
    if (event.allowSound) playChime();
  });

  mount(PRToasts, { target: document.body });
}

/**
 * Clicking the system notice performs its default action, Review. The browser cannot offer the toast's buttons
 * on a system notice, so the toast carries Ignore and Review.
 */
function showSystemNotice(item: PRNotification): void {
  const notice = new Notification(item.title, { body: item.body, tag: toastKey(item) });
  notice.onclick = () => {
    window.focus();
    notice.close();
    dismissToast(toastKey(item));
    void reviewPullRequest(item.repoID, item.prID);
  };
}

let audio: AudioContext | null = null;

/** A short two-tone chime, for `bannerAndSound`. Browsers may block audio until the page has been clicked. */
function playChime(): void {
  try {
    audio ??= new AudioContext();
    void audio.resume();
    const start = audio.currentTime;
    const oscillator = audio.createOscillator();
    const gain = audio.createGain();
    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(880, start);
    oscillator.frequency.setValueAtTime(1175, start + 0.12);
    gain.gain.setValueAtTime(0.2, start);
    gain.gain.exponentialRampToValueAtTime(0.001, start + 0.3);
    oscillator.connect(gain).connect(audio.destination);
    oscillator.start(start);
    oscillator.stop(start + 0.3);
  } catch {
    // No audio device, or the browser refused the context: the alert is still shown, without its sound.
  }
}
