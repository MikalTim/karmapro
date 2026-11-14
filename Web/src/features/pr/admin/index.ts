// The two pull request admin dialogs. AppKit keeps each controller once and shows it again, so each window
// is a singleton: opening it again brings the open one to the front.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import AccountsWindow from "./AccountsWindow.svelte";
import MonitoredReposWindow from "./MonitoredReposWindow.svelte";

export function openPRAccountsWindow(): void {
  openWindow({
    key: "AccountsWindow",
    title: "Pull Request Accounts",
    width: 620,
    height: 430,
    escCloses: true,
    component: asWindowContent(AccountsWindow),
  });
}

export function openPRReposWindow(): void {
  openWindow({
    key: "MonitoredReposWindow",
    title: "Watched Repositories",
    width: 660,
    height: 500,
    escCloses: true,
    component: asWindowContent(MonitoredReposWindow),
  });
}
