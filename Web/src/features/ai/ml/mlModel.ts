// The ML training and scan windows' rules as plain functions: what the forms
// check before they ask the server, what the status lines say, how the popups
// keep their choice. The windows only draw these.

/** A dialog's text: `message` is NSAlert.messageText, `informative` its informativeText. */
export interface AlertText {
  message: string;
  informative: string;
}

/** A check that either yields the request or the dialog that explains why not. */
export type Checked<T> = { value: T } | { problem: AlertText };

/** One trained model in the library (`MLService.MLModelDTO`). */
export interface MLModelDTO {
  name: string;
}

/** A language and the extensions it covers (`MLService.MLLanguageDTO`). */
export interface MLLanguageDTO {
  name: string;
  extensions: string[];
}

/** The choices and availability the forms show (`MLService.MLOptionsDTO`). */
export interface MLOptionsDTO {
  trainingLanguages: MLLanguageDTO[];
  scanLanguages: MLLanguageDTO[];
  modelsSummary: string;
  /** Absent or null when a scan can start. */
  unavailableText?: string | null;
  canScan: boolean;
  thresholdMin: number;
  thresholdMax: number;
  thresholdDefault: number;
}

/** `GET /api/ml/models`. */
export interface MLModelsDTO {
  models: MLModelDTO[];
  options: MLOptionsDTO;
}

/** `GET /api/project`, as far as the scan window needs it. */
export interface ProjectRootDTO {
  root?: string | null;
}

/** The result of a training job (`MLService.MLTrainResultDTO`). */
export interface MLTrainResultDTO {
  saved: boolean;
  patches: number;
  lines: number;
  statusText: string;
  model?: MLModelDTO | null;
}

/** One heatmap cell: a scanned file and how many of its lines were flagged (`MLService.HeatmapCellDTO`). */
export interface HeatmapCellDTO {
  path: string;
  name: string;
  flagged: number;
  /** flagged ÷ the hottest file's count, 0...1. */
  intensity: number;
}

/** The heatmap of the most recent scan (`MLService.HeatmapDTO`). */
export interface HeatmapDTO {
  modelName: string;
  thresholdPercent: number;
  totalFiles: number;
  totalFlagged: number;
  maxFlagged: number;
  summary: string;
  cells: HeatmapCellDTO[];
}

/** The result of a scan job (`MLService.MLScanResultDTO`). */
export interface MLScanResultDTO {
  modelName: string;
  thresholdPercent: number;
  totalFiles: number;
  totalLines: number;
  flaggedLines: number;
  statusText: string;
  heatmap: HeatmapDTO;
}

/** The popup entry shown when the library is empty (`MLScanWindowController.refreshModels`). */
export const NO_MODELS_CHOICE = "-- no models --";

/** The dialog the ML scan menu entry shows when no folder is open (`mlScanClicked`). */
export const NO_PROJECT_FOR_SCAN: AlertText = {
  message: "No Folder Open",
  informative: "Open a source folder before running an ML scan.",
};

export function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** The popup keeps `current` when it is still offered, else selects the first item. */
export function keptChoice(current: string, offered: string[]): string {
  return offered.includes(current) ? current : (offered[0] ?? "");
}

/** The scan window's model popup: the library's names, or the placeholder when there are none. */
export function modelChoice(current: string, names: string[]): string {
  return names.length === 0 ? NO_MODELS_CHOICE : keptChoice(current, names);
}

export function modelPopupTitles(names: string[]): string[] {
  return names.length > 0 ? names : [NO_MODELS_CHOICE];
}

/** The fraction a progress bar shows; a job that has not counted anything yet shows nothing. */
export function progressFraction(done: number, total: number): number {
  return total > 0 ? done / total : 0;
}

/**
 * The Train button's check (`trainClicked`): a patch folder first, then a
 * non-blank model name. The name is sent trimmed.
 */
export function trainRequest(
  folder: string | null,
  name: string,
  language: string,
): Checked<{ folder: string; language: string; name: string }> {
  if (folder === null) {
    return {
      problem: {
        message: "No patch folder chosen",
        informative: "Use “Choose Patch Folder…” to select a directory of patches first.",
      },
    };
  }
  const modelName = name.trim();
  if (modelName === "") {
    return { problem: { message: "No model name", informative: "Enter a name for the training model." } };
  }
  return { value: { folder, language, name: modelName } };
}

export const READING_PATCHES_STATUS = "Reading patches…";

/** The export dialog needs at least one model in the library. */
export function exportProblem(names: string[]): AlertText | null {
  return names.length === 0
    ? { message: "No Models", informative: "There are no trained models to export yet." }
    : null;
}

export function exportedAlert(name: string, fileName: string): AlertText {
  return { message: "Exported", informative: `Model “${name}” exported to ${fileName}` };
}

export function exportFailedAlert(reason: string): AlertText {
  return { message: "Export Failed", informative: reason };
}

export function importedAlert(name: string): AlertText {
  return { message: "Imported", informative: `Imported model “${name}”.` };
}

export function importFailedAlert(reason: string): AlertText {
  return { message: "Import Failed", informative: reason };
}

export const IMPORT_URL_PROMPT = {
  message: "Import Model from URL",
  informative: "Enter the web address of a raw Karma Pro model file (.karmamodel or .json):",
  placeholder: "https://example.com/model.json",
};

export const DOWNLOADING_STATUS = "Downloading model…";

export function importedFromURLStatus(name: string): string {
  return `Imported model “${name}” from URL.`;
}

/** The address typed into the import prompt, trimmed, or the "Invalid URL" dialog. */
export function modelAddress(raw: string): Checked<{ url: string }> {
  const url = raw.trim();
  if (url !== "" && URL.canParse(url)) return { value: { url } };
  return { problem: { message: "Invalid URL", informative: "Enter a valid web address." } };
}

/** The scan window's status line while a scan runs. */
export function scanningStatus(model: string): string {
  return `Scanning with model “${model}”…`;
}

/** The extensions a language covers; "All Languages" (and anything unknown) has none, which means every file. */
export function languageExtensions(languages: MLLanguageDTO[], name: string): string[] {
  return languages.find((language) => language.name === name)?.extensions ?? [];
}

/** True when a project folder is open, from `GET /api/project`. */
export function hasProjectRoot(info: ProjectRootDTO): boolean {
  return typeof info.root === "string" && info.root !== "";
}

export interface ScanRequest {
  model: string;
  extensions: string[];
  threshold: number;
}

/**
 * The Scan button's checks (`scanClicked`), in the order the window makes them:
 * an open folder, then a chosen model. The threshold is a percentage.
 */
export function scanRequest(input: {
  hasRoot: boolean;
  model: string;
  languages: MLLanguageDTO[];
  language: string;
  threshold: number;
}): Checked<ScanRequest> {
  if (!input.hasRoot) {
    return { problem: { message: "No Folder Open", informative: "Open a source folder first." } };
  }
  if (input.model === "" || input.model === NO_MODELS_CHOICE) {
    return { problem: { message: "No Model", informative: "Choose a trained model." } };
  }
  return {
    value: {
      model: input.model,
      extensions: languageExtensions(input.languages, input.language),
      threshold: input.threshold,
    },
  };
}
