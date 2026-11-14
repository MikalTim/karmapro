// Saves text the page already holds, through a Blob. Replies from the server are saved by `download` in api.ts.

/** Saves `text` as a Markdown file named `name` through the browser's download mechanism. */
export function saveTextFile(name: string, text: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: "text/markdown;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
