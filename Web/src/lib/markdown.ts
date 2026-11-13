// Port of AIWindowController.attributedMarkdownResponse: renders an AI reply
// as styled terminal text. Headings become bold text, `**bold**` and `*italic*`
// are styled, `inline code` and fenced ``` blocks are monospace on a tinted
// background (the fence's language tag line is removed). All text is escaped;
// no raw HTML is ever passed through.
//
// The structure follows the Swift code line for line, including its quirks:
// an italic marker with no closing partner repeats the text before it.

const escapeTable: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => escapeTable[c]);
}

type Style = "plain" | "bold" | "italic";

function span(text: string, style: Style): string {
  if (text === "") return "";
  return `<span class="md-${style}">${escapeHtml(text)}</span>`;
}

/** `**bold**` and `*italic*` / `_italic_` runs on top of `baseStyle`. */
function emphasis(text: string, baseStyle: Style): string {
  let boldSegments = text.split("**");
  if (boldSegments.length % 2 === 0) boldSegments = [text]; // unbalanced: render literally
  let out = "";
  boldSegments.forEach((segment, bi) => {
    const style: Style = bi % 2 === 1 ? "bold" : baseStyle;
    // Italic via single * or _ delimiters hugging non-space characters
    // (so `a * b` in code snippets stays literal).
    const chars = Array.from(segment);
    let index = 0;
    let plainStart = 0;
    while (index < chars.length) {
      const c = chars[index];
      if (
        (c === "*" || c === "_") &&
        index > 0 &&
        index + 1 < chars.length &&
        !/\s/u.test(chars[index - 1]) &&
        !/\s/u.test(chars[index + 1])
      ) {
        if (plainStart < index) out += span(chars.slice(plainStart, index).join(""), style);
        const close = chars.indexOf(c, index + 1);
        if (close >= 0) {
          out += span(chars.slice(index + 1, close).join(""), "italic");
          index = close + 1;
          plainStart = index;
          continue;
        }
      }
      index += 1;
    }
    if (plainStart < chars.length) out += span(chars.slice(plainStart).join(""), style);
  });
  return out;
}

/** One prose line: ATX headings and inline styles, ending in a newline. */
function proseLine(line: string): string {
  const trimmed = line.replace(/^[ \t]+|[ \t]+$/g, "");
  if (trimmed.startsWith("#")) {
    const text = trimmed.replace(/^#+/, "").replace(/^[ \t]+|[ \t]+$/g, "");
    return span(text, "bold") + "\n";
  }
  // Inline `code` first so emphasis markers inside code stay literal.
  let out = "";
  line.split("`").forEach((part, ci) => {
    if (ci % 2 === 1) out += `<span class="md-code-inline">${escapeHtml(part)}</span>`;
    else if (part !== "") out += emphasis(part, "plain");
  });
  return out + "\n";
}

/** The HTML for an AI reply. Put it in an element with class `terminal-text`. */
export function renderMarkdown(markdown: string): string {
  let out = "";
  markdown.split("```").forEach((part, index) => {
    if (index % 2 === 1) {
      let code = part;
      // Drop the optional language tag on the first fence line.
      const firstNewline = code.indexOf("\n");
      if (firstNewline >= 0) {
        const firstLine = code.slice(0, firstNewline).trim();
        if (firstLine !== "" && !firstLine.includes(" ")) code = code.slice(firstNewline);
      }
      code = code.trim();
      out += `<span class="md-code-block">${escapeHtml(code + "\n")}</span>`;
    } else {
      for (const line of part.split("\n")) out += proseLine(line);
    }
  });
  return out;
}
