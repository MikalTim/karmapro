// About Karma Pro (`AboutMenuItemTarget.showAbout`): the splash panel for five seconds. A new
// About replaces the panel on screen and restarts the countdown.
import { mount, unmount } from "svelte";
import AboutSplash from "./AboutSplash.svelte";

const SHOW_MS = 5000;

let hideShown: (() => void) | null = null;

export function openAboutWindow(): void {
  hideAbout();
  const target = document.createElement("div");
  document.body.append(target);
  const instance = mount(AboutSplash, { target });
  const timer = setTimeout(hideAbout, SHOW_MS);
  hideShown = () => {
    clearTimeout(timer);
    void unmount(instance);
    target.remove();
  };
}

function hideAbout(): void {
  hideShown?.();
  hideShown = null;
}
