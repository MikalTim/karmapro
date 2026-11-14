// How a failed request is reported. AppKit reports these with an NSAlert carrying the error's text.
import { showAlert } from "../../../lib/ui/alert.svelte";

/** The text of a thrown error. For a failed request that is the server's `error` field. */
export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export async function showFailure(error: unknown): Promise<void> {
  await showAlert({ message: errorMessage(error), style: "warning" });
}
