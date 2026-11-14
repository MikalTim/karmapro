// The wiki's page list. AppKit keeps one stored controller, so opening it again focuses it.
import { asWindowContent, openWindow } from "../../../../lib/ui/windows.svelte";
import WikiListWindow from "./WikiListWindow.svelte";

export function openWikiWindow(): void {
  openWindow({
    key: "WikiListWindow",
    title: "Wiki",
    width: 700,
    height: 520,
    minWidth: 480,
    minHeight: 300,
    escCloses: true,
    component: asWindowContent(WikiListWindow),
  });
}
