// The Notes window's Export, Import and Import from URL flows, with the alerts of
// `NotesWindowController`. Import results come back with their own title and
// message from the server, so the alerts read them as they are.
import { ApiError, api, download, upload } from "../../../lib/api";
import { runJob } from "../../../lib/jobs";
import { chooseFile } from "../../../lib/ui/fileUpload";
import { showAlert, showAlertWithFields } from "../../../lib/ui/alert.svelte";
import { messageOf } from "./bugModel";
import type { NotesImportResultDTO } from "./notesModel";

async function alertOK(message: string, informative: string): Promise<void> {
  await showAlert({ message, informative, buttons: ["OK"] });
}

async function showImportResult(result: NotesImportResultDTO): Promise<void> {
  await alertOK(result.title, result.message);
}

/** Export Notes…: the server names the `.codenotes` file; the browser saves it. */
export async function exportNotes(): Promise<void> {
  try {
    const fileName = await download("/api/notes/export", { fallbackName: "notes.codenotes" });
    await alertOK("Exported", `Notes exported to ${fileName}.`);
  } catch {
    await alertOK("Export Failed", "Could not write the notes file.");
  }
}

/** Import Notes…: merges the chosen `.codenotes` or `.json` file. */
export async function importNotesFile(): Promise<void> {
  const file = await chooseFile(".codenotes,.json");
  if (!file) return;
  try {
    await showImportResult(await upload<NotesImportResultDTO>("/api/notes/import", file));
  } catch (error) {
    await alertOK("Import Failed", messageOf(error));
  }
}

/**
 * Import from URL…: asks for an address and merges the notes file it points to.
 * The server fetches it as a job. A refused address (400) is "Invalid URL"; any
 * other failure is "Import Failed", as the window's alerts read.
 */
export async function importNotesFromURL(): Promise<void> {
  const answer = await showAlertWithFields({
    message: "Import Notes from URL",
    informative: "Enter the web address of a raw Karma Pro notes file (.codenotes or .json):",
    buttons: ["Import", "Cancel"],
    fields: [{ placeholder: "https://example.com/notes.json", width: 380 }],
  });
  if (answer.button !== 0) return;
  const raw = (answer.values[0] ?? "").trim();
  if (raw === "") {
    await alertOK("Invalid URL", "Enter a valid web address.");
    return;
  }
  try {
    const outcome = await runJob<NotesImportResultDTO>(
      api<{ jobId: string }>("POST", "/api/notes/import-url", { url: raw }),
    ).promise;
    if (outcome.result) await showImportResult(outcome.result);
  } catch (error) {
    if (error instanceof ApiError && error.status === 400) {
      await alertOK("Invalid URL", messageOf(error));
    } else {
      await alertOK("Import Failed", messageOf(error));
    }
  }
}
