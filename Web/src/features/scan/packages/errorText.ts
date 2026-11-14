// The text an error shows in a window's status line or in an alert.
export function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
