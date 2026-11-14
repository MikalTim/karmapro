// The bug list's Backup, Import and Delete flows, with the alert sequence of
// `BugListWindowController`. The server writes and reads the encrypted files;
// the browser saves and picks them.
import { api, download, upload } from "../../../lib/api";
import { chooseFile } from "../../../lib/ui/fileUpload";
import { showAlert, showAlertWithFields, type AlertOptions } from "../../../lib/ui/alert.svelte";
import {
  backupSavedText,
  deleteConfirmText,
  importCompleteText,
  isNeedsPasswordError,
  messageOf,
  passwordOrNull,
  passwordsMatch,
  type BugDTO,
  type BugImportResultDTO,
  type BugListDTO,
} from "./bugModel";

const BACKUP_FILE_NAME = "KarmaProBugBackup.karmapro";

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

/** Backup…: asks whether to encrypt, asks for the password twice, then saves the file. */
export async function backupBugs(): Promise<void> {
  try {
    const protect = await showAlert({
      message: "Password Protect Backup?",
      informative: "Encrypt the exported backup with a password. You will need this password to import it later.",
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
          : passwordOrNull(
              await showAlertWithFields(passwordAlert("Set Backup Password", "Confirm the backup password.", "Password")),
            );
      if (!passwordsMatch(first, confirmed)) {
        await alertOK("Backup Cancelled", "The passwords did not match or were blank. No backup was saved.");
        return;
      }
      password = first;
    }
    const fileName = await download("/api/bugs/backup", {
      method: "POST",
      body: password === null ? undefined : { password },
      fallbackName: BACKUP_FILE_NAME,
    });
    const total = (await api<BugListDTO>("GET", "/api/bugs")).bugs.length;
    await alertOK("Backup Saved", backupSavedText(total, fileName, password !== null));
  } catch (error) {
    await alertOK("Backup Failed", messageOf(error));
  }
}

/** Import…: uploads the chosen file, asking for its password when it is encrypted. */
export async function importBugs(reloadList: () => Promise<void>): Promise<void> {
  const file = await chooseFile(".karmapro,.json");
  if (!file) return;
  try {
    let result: BugImportResultDTO;
    try {
      result = await upload<BugImportResultDTO>("/api/bugs/import", file);
    } catch (error) {
      if (!isNeedsPasswordError(error)) throw error;
      const password = passwordOrNull(
        await showAlertWithFields(
          passwordAlert("Enter Backup Password", "This backup is encrypted. Enter its password to import it.", "Backup password"),
        ),
      );
      // Cancelling the password prompt ends the import without a message (`importClicked`).
      if (password === null) return;
      result = await upload<BugImportResultDTO>("/api/bugs/import", file, { password });
    }
    if (result.found === 0) {
      await alertOK("Nothing to Import", "The selected file contains no bug reports.");
      return;
    }
    // The list reloads before the result alert, as `importClicked` does.
    await reloadList();
    await alertOK("Import Complete", importCompleteText(result.added, file.name));
  } catch (error) {
    await alertOK("Import Failed", messageOf(error));
  }
}

/** Delete: the confirmation, then the removal. Only a confirmed "Delete" removes the report. */
export async function deleteBug(bug: BugDTO): Promise<void> {
  const choice = await showAlert({
    message: "Delete Bug Report?",
    informative: deleteConfirmText(bug.title),
    buttons: ["Delete", "Cancel"],
  });
  if (choice !== 0) return;
  try {
    await api("DELETE", `/api/bugs/${bug.id}`);
  } catch (error) {
    await alertOK(messageOf(error));
  }
}
