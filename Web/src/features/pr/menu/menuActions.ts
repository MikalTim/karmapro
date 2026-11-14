// What the pull request status menu does when an item is chosen (`PRMenuBarController`'s menu actions).
import { api } from "../../../lib/api";
import { showAlert } from "../../../lib/ui/alert.svelte";
import { openPRAccountsWindow, openPRReposWindow } from "../../pr";
import { showFailure } from "./failures";
import { reviewState, setPRState } from "./review.svelte";
import type { PRAbout, PRState } from "./prTypes";
import type { PRMenuAction } from "./menuModel";

export async function runMenuAction(action: PRMenuAction): Promise<void> {
  try {
    switch (action.kind) {
      case "enableMonitoring":
        await enableMonitoring();
        return;
      case "disableMonitoring":
        setPRState(await api<PRState>("POST", "/api/pr/monitoring", { enabled: false }));
        return;
      case "checkNow":
        await api("POST", "/api/pr/check-now");
        return;
      case "setDepth":
        setPRState(await api<PRState>("PUT", "/api/pr/settings", { depth: action.value }));
        return;
      case "setNotifyStyle":
        setPRState(await api<PRState>("PUT", "/api/pr/settings", { notifyStyle: action.value }));
        return;
      case "manageRepositories":
        openPRReposWindow();
        return;
      case "accounts":
        openPRAccountsWindow();
        return;
      case "about":
        await showAbout();
        return;
      case "quit":
        await confirmQuit();
        return;
    }
  } catch (error) {
    await showFailure(error);
  }
}

/** Turning monitoring on needs a repository to watch and a git to fetch with; the alerts say so first. */
async function enableMonitoring(): Promise<void> {
  const state = reviewState.value;
  if (!state) return;
  if (state.repoCount === 0) {
    const pressed = await showAlert({
      message: "No repositories yet",
      informative: "Add a repository to watch before enabling monitoring.",
      style: "warning",
      buttons: ["Manage Repositories\u2026", "Cancel"],
    });
    if (pressed === 0) openPRReposWindow();
    return;
  }
  if (!state.gitAvailable) {
    await showAlert({
      message: "Git is not available",
      informative: state.gitUnavailableMessage,
      style: "warning",
    });
    return;
  }
  setPRState(await api<PRState>("POST", "/api/pr/monitoring", { enabled: true }));
}

async function showAbout(): Promise<void> {
  const about = await api<PRAbout>("GET", "/api/pr/about");
  await showAlert({ message: about.title, informative: about.message, style: "warning" });
}

/** Quit asks first, as the main window does when it is closed (`windowShouldClose`). */
async function confirmQuit(): Promise<void> {
  const pressed = await showAlert({
    message: "Are you sure you want to quit?",
    informative: "Closing the Karma Pro window will quit the app.",
    style: "warning",
    buttons: ["Quit", "Cancel"],
  });
  if (pressed === 0) await api("POST", "/api/app/quit");
}
