import { showAlert } from "../../lib/ui/alert.svelte";
import { messageOf } from "./project";

/** Shows a failed request in an alert with its server message, the way AppKit's error alerts do. */
export function reportError(error: unknown): void {
  void showAlert({ message: messageOf(error), buttons: ["OK"] });
}
