// The app-level windows and the update menu: Help, Settings (the MCP service), About, the
// update section of the Karma Pro menu, and the update notifications.
import { openWindow, asWindowContent } from "../../lib/ui/windows.svelte";
import HelpWindow from "./HelpWindow.svelte";
import MCPSettingsWindow from "./MCPSettingsWindow.svelte";
import { HELP_TITLE } from "./help";

export { openAboutWindow } from "./about";
export { updateMenuItems } from "./updates.svelte";
export { startUpdateNotifications } from "./updateNotifications";

/** `HelpMenuTarget.showHelp`: one stored controller, so the window is a singleton. */
export function openHelpWindow(): void {
  openWindow({
    key: "HelpWindow",
    title: HELP_TITLE,
    width: 750,
    height: 600,
    escCloses: true,
    component: asWindowContent(HelpWindow),
  });
}

/** `SettingsMenuTarget.showSettings`: the Settings window, which holds the MCP service controls. */
export function openMCPSettingsWindow(): void {
  openWindow({
    key: "MCPSettingsWindow",
    title: "Settings",
    width: 680,
    height: 660,
    minWidth: 620,
    minHeight: 560,
    escCloses: true,
    component: asWindowContent(MCPSettingsWindow),
  });
}
