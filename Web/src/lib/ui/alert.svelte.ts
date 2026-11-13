// NSAlert: a modal question with a message, optional explanation, buttons and
// optional text fields (the accessory views the AppKit alerts use).
export type AlertStyle = "informational" | "warning" | "critical";

export interface AlertField {
  label?: string;
  value?: string;
  placeholder?: string;
  secure?: boolean;
  /** Field width in px (the Swift frame width). Defaults to 280. */
  width?: number;
}

export interface AlertOptions {
  message: string;
  informative?: string;
  style?: AlertStyle;
  /** Button titles in the order they are added in Swift: the first is the default and sits rightmost. */
  buttons?: string[];
  fields?: AlertField[];
  /** Id of the window the alert is a sheet of. It then covers only that window. */
  sheetOf?: number;
}

export interface AlertResult {
  /** Index into `buttons` of the pressed button. */
  button: number;
  /** The text of each field, in order. */
  values: string[];
}

export interface PendingAlert {
  id: number;
  options: AlertOptions;
  resolve: (result: AlertResult) => void;
}

export const alertQueue = $state<{ list: PendingAlert[] }>({ list: [] });

let nextId = 1;

/** Shows an alert with text fields and resolves with the pressed button and the field values. */
export function showAlertWithFields(options: AlertOptions): Promise<AlertResult> {
  const { promise, resolve } = Promise.withResolvers<AlertResult>();
  alertQueue.list.push({ id: nextId++, options: { buttons: ["OK"], style: "informational", ...options }, resolve });
  return promise;
}

/** Shows an alert and resolves with the index of the pressed button (`runModal`). */
export async function showAlert(options: AlertOptions): Promise<number> {
  return (await showAlertWithFields(options)).button;
}

/** `promptForText`: one text field, OK and Cancel. Resolves with the trimmed text, or null when cancelled or empty. */
export async function promptForText(options: {
  title: string;
  prompt: string;
  initial?: string;
  placeholder?: string;
  secure?: boolean;
  keepWhitespace?: boolean;
  sheetOf?: number;
}): Promise<string | null> {
  const result = await showAlertWithFields({
    message: options.title,
    informative: options.prompt,
    buttons: ["OK", "Cancel"],
    fields: [{ value: options.initial ?? "", placeholder: options.placeholder, secure: options.secure, width: 260 }],
    sheetOf: options.sheetOf,
  });
  if (result.button !== 0) return null;
  const value = options.keepWhitespace ? result.values[0] : result.values[0].trim();
  return value.length === 0 ? null : value;
}

export function resolveAlert(id: number, result: AlertResult): void {
  const index = alertQueue.list.findIndex((a) => a.id === id);
  if (index < 0) return;
  const [alert] = alertQueue.list.splice(index, 1);
  alert.resolve(result);
}
