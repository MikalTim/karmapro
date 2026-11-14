/** The last component of an absolute path, as `NSURL.lastPathComponent` gives it. */
export function baseName(path: string): string {
  const parts = path.split("/").filter((part) => part.length > 0);
  return parts.at(-1) ?? path;
}
