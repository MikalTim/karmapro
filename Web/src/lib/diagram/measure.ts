// Text measurement for the diagram ports and the source viewer. The AppKit
// drawing code sizes boxes from `NSString.size(withAttributes:)`; the browser
// equivalent is a canvas 2D context set to the same CSS font.

let context: CanvasRenderingContext2D | null | undefined;

/** The advance width in px of `text` set in the CSS font `font` (for example `"13px ui-monospace"`). */
export function measureText(text: string, font: string): number {
  if (context === undefined) context = document.createElement("canvas").getContext("2d");
  if (context === null) return text.length * 7;
  context.font = font;
  return context.measureText(text).width;
}
