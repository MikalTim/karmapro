// The wiki list's Backup, Import, New Page, Rename and Delete flows, with the
// alert sequence of `WikiWindowController`. The server writes and reads the
// archives; the browser saves and picks them.
import { api, download, upload } from "../../../../lib/api";
import { chooseFile } from "../../../../lib/ui/fileUpload";
import { promptForText, showAlert, showAlertWithFields, type AlertOptions } from "../../../../lib/ui/alert.svelte";
import { closeWikiEditorWindow } from "../editor";
import {
  backupSavedText,
  CONFLICT_BUTTONS,
  collectConflictDecisions,
  conflictInformativeText,
  deleteConfirmText,
  messageOf,
  needsPasswordAnswer,
  passwordOrNull,
  passwordsMatch,
  renamedTitle,
  type WikiImportResultDTO,
  type WikiImportSessionDTO,
  type WikiListDTO,
  type WikiPageDTO,
} from "./wikiListModel";

const BACKUP_FILE_NAME = "KarmaProWiki.karmawiki";

/** One page's API path, with the slug encoded for the URL. */
function pagePath(slug: string): string {
  return `/api/wiki/${encodeURIComponent(slug)}`;
}

/** A secure-field alert (`promptForExistingPassword` / `promptForNewPassword`). */
function passwordAlert(title: string, prompt: string, placeholder: string): AlertOptions {
  return {
    message: title,
    informative: prompt,
    buttons: ["OK", "Cancel"],
    fields: [{ secure: true, placeholder, width: 260 }],
  };
}

async function alertOK(message: string, informative?: string): Promise<void> {
  await showAlert({ message, informative, buttons: ["OK"] });
}

/** Backup…: asks whether to encrypt, asks for the password twice, then saves the archive. */
export async function backupWiki(): Promise<void> {
  try {
    const protect = await showAlert({
      message: "Password Protect Backup?",
      informative: "Encrypt the backup with a password? You will need it to import this backup later.",
      buttons: ["Encrypt", "Don't Encrypt"],
    });
    let password: string | null = null;
    if (protect === 0) {
      const first = passwordOrNull(
        await showAlertWithFields(passwordAlert("Set Backup Password", "Choose a password to protect this backup.", "Password")),
      );
      // The second prompt only appears after a first password was given (the Swift `guard`).
      const confirmed =
        first === null
          ? null
          : passwordOrNull(await showAlertWithFields(passwordAlert("Set Backup Password", "Confirm the backup password.", "Password")));
      if (!passwordsMatch(first, confirmed)) {
        await alertOK("Backup Cancelled", "The passwords did not match or were blank. No backup was saved.");
        return;
      }
      password = first;
    }
    const total = (await api<WikiListDTO>("GET", "/api/wiki")).pages.length;
    const fileName = await download("/api/wiki/backup", {
      method: "POST",
      body: password === null ? undefined : { password },
      fallbackName: BACKUP_FILE_NAME,
    });
    await alertOK("Backup Saved", backupSavedText(total, fileName, password !== null));
  } catch (error) {
    await alertOK("Backup Failed", messageOf(error));
  }
}

/**
 * Uploads the chosen archive. An encrypted one answers 422 until its password is
 * given; cancelling that prompt returns null, which ends the import silently.
 */
async function uploadBackup(file: File): Promise<WikiImportSessionDTO | null> {
  try {
    return await upload<WikiImportSessionDTO>("/api/wiki/import", file);
  } catch (error) {
    if (!needsPasswordAnswer(error)) throw error;
    const password = passwordOrNull(
      await showAlertWithFields(
        passwordAlert("Enter Backup Password", "This backup is encrypted. Enter its password to import it.", "Backup password"),
      ),
    );
    if (password === null) return null;
    return upload<WikiImportSessionDTO>("/api/wiki/import", file, { password });
  }
}

// AppKit's `isImporting` guard: a second Import… while one runs does nothing.
let importing = false;

/** Import…: uploads the chosen archive, asks about each existing page, then imports. */
export async function importWiki(): Promise<void> {
  if (importing) return;
  importing = true;
  try {
    const file = await chooseFile();
    if (!file) return;
    const session = await uploadBackup(file);
    if (!session) return;
    const decisions = await collectConflictDecisions(session.conflicts, (slug) =>
      showAlert({
        message: "Page Already Exists",
        informative: conflictInformativeText(session.conflictTitles[slug] ?? slug),
        buttons: CONFLICT_BUTTONS,
      }),
    );
    const result = await api<WikiImportResultDTO>("POST", `/api/wiki/import/${encodeURIComponent(session.importID)}/resolve`, {
      decisions,
    });
    await alertOK("Import Complete", result.summary);
  } catch (error) {
    await alertOK("Import Failed", messageOf(error));
  } finally {
    importing = false;
  }
}

/** New Page…: the name prompt, then the page. Cancelling still creates "Untitled", as AppKit does. */
export async function newWikiPage(): Promise<WikiPageDTO> {
  const entered = await promptForText({ title: "New Page", prompt: "Name of the new page:" });
  return api<WikiPageDTO>("POST", "/api/wiki", { title: entered ?? "Untitled" });
}

/** Rename…: the title prompt; the open editor of the page closes (saving first) before the rename. */
export async function renameWiki(page: WikiPageDTO): Promise<void> {
  const entered = await promptForText({ title: "Rename Page", prompt: "New title:", initial: page.title });
  const title = renamedTitle(page.title, entered);
  if (title === null) return;
  if (!(await closeWikiEditorWindow(page.slug))) return;
  await api<WikiPageDTO>("POST", `${pagePath(page.slug)}/rename`, { title });
}

/** Delete…: the confirmation, then the open editor closes and the page is removed. */
export async function deleteWiki(page: WikiPageDTO): Promise<void> {
  const choice = await showAlert({
    message: "Delete Page",
    informative: deleteConfirmText(page.title),
    buttons: ["Delete", "Cancel"],
  });
  if (choice !== 0) return;
  if (!(await closeWikiEditorWindow(page.slug))) return;
  await api("DELETE", pagePath(page.slug));
}
