// The Help & User Guide window (`HelpWindowController`). The server renders the page
// (`GET /api/help`); this file holds what the window needs around that page.

export const HELP_TITLE = "Karma Pro Help & User Guide";

/** The splash picture's source as the server writes it into the page. */
export const HELP_SPLASH_SRC = "/api/resources/HelpSplash.jpg";

/**
 * Points the splash picture at `imageSrc`. An <img> cannot send the API headers, so the window
 * fetches the picture itself. The page sits in a sandboxed frame with an opaque origin, which may
 * not resolve a blob URL made by this page, so the picture travels as a data URL. The server quotes
 * the source with single quotes; double quotes are handled too.
 */
export function withSplashSource(html: string, imageSrc: string): string {
  return html
    .replaceAll(`src='${HELP_SPLASH_SRC}'`, `src='${imageSrc}'`)
    .replaceAll(`src="${HELP_SPLASH_SRC}"`, `src="${imageSrc}"`);
}

/** The picture's bytes as a `data:` URL. */
export function dataUrl(blob: Blob): Promise<string> {
  const { promise, resolve, reject } = Promise.withResolvers<string>();
  const reader = new FileReader();
  reader.onload = () => resolve(String(reader.result));
  reader.onerror = () => reject(reader.error);
  reader.readAsDataURL(blob);
  return promise;
}
