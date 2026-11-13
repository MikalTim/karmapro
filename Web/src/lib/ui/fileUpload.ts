// NSOpenPanel for choosing a file *to import* from the user's own machine:
// the browser's file chooser. `accept` mirrors the panel's allowedContentTypes
// (for example ".json,.karmaprompts").
export function chooseFile(accept?: string): Promise<File | null> {
  const { promise, resolve } = Promise.withResolvers<File | null>();
  const input = document.createElement("input");
  input.type = "file";
  if (accept) input.accept = accept;
  input.style.display = "none";
  input.addEventListener("change", () => {
    resolve(input.files?.[0] ?? null);
    input.remove();
  });
  input.addEventListener("cancel", () => {
    resolve(null);
    input.remove();
  });
  document.body.appendChild(input);
  input.click();
  return promise;
}
