// Canvas text cannot read `var(--font-mono)`, so the measurements of the viewer's chips and tooltips take the
// family from the theme here and set it in the same font the text is drawn with.
export function monoFont(px: number): string {
  const family = getComputedStyle(document.documentElement).getPropertyValue("--font-mono").trim();
  return `${px}px ${family.length > 0 ? family : "monospace"}`;
}
