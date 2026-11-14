// Text the pull request windows build from the server's data. Pure, so it can be tested without a page.
import type { PRItem } from "./prTypes";

/**
 * Cuts text to `limit` characters, ending with an ellipsis when it is cut. Counts grapheme clusters, the same
 * unit Swift's `String.count` uses, so an accented letter or an emoji is one character.
 */
export function shortened(text: string, limit: number): string {
  const graphemes = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)].map(
    (part) => part.segment,
  );
  if (graphemes.length <= limit) return text;
  return graphemes.slice(0, limit - 1).join("") + "\u2026";
}

/** The first line of the "Preparing review" window: "#12 Fix login". */
export function progressTitle(item: PRItem): string {
  return `#${item.number} ${shortened(item.title, 72)}`;
}

/** The second line of the "Preparing review" window: "owner/name  ·  feature → main". */
export function progressRepoLine(item: PRItem): string {
  return `${item.repoSlug}  \u00B7  ${shortened(item.headBranch, 28)} \u2192 ${item.baseBranch}`;
}
