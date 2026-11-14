// The two pull request admin dialogs. AppKit keeps each controller once and shows it again, so each window
// is a singleton: opening it again brings the open one to the front.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import AccountsWindow from "./AccountsWindow.svelte";
import MonitoredReposWindow from "./MonitoredReposWindow.svelte";

// AppKit's contentRect is 430 pt tall, but its Save Token row is pinned below the whole constraint chain (the
// explanation, the 140 pt table and the four form rows), which is taller than that. The web content is 526 pt tall,
// so the window opens that tall to show it without scrolling.
export function openPRAccountsWindow(): void {
  openWindow({
    key: "AccountsWindow",
    title: "Pull Request Accounts",
    width: 620,
    height: 526,
    escCloses: true,
    component: asWindowContent(AccountsWindow),
  });
}

// AppKit's contentRect is 500 pt tall, but the Add Repository row is pinned below the whole constraint chain, which
// is taller than that. The web content is 558 pt tall, so the window opens 560 pt tall to show it without scrolling.
export function openPRReposWindow(): void {
  openWindow({
    key: "MonitoredReposWindow",
    title: "Watched Repositories",
    width: 660,
    height: 560,
    escCloses: true,
    component: asWindowContent(MonitoredReposWindow),
  });
}
