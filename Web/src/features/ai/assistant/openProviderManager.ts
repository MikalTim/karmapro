// Opens the AI Providers window. AppKit creates a new manager each time, so the
// window is not a singleton here either.
import { asWindowContent, openWindow } from "../../../lib/ui/windows.svelte";
import { startAssistant } from "./assistantStore.svelte";
import ProviderManagerWindow from "./ProviderManagerWindow.svelte";

export function openProviderManager(): void {
  startAssistant();
  openWindow({
    title: "AI Providers",
    width: 620,
    height: 380,
    // The AppKit window has a fixed size. The minimum keeps it from shrinking below
    // its layout; the in-page window cannot yet refuse to grow.
    minWidth: 620,
    minHeight: 380,
    component: asWindowContent(ProviderManagerWindow),
  });
}
