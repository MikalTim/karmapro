/** The count on the Bugs button: hidden at zero, "99+" above ninety-nine (`BugBadgeView.update`). */
export function bugBadgeText(count: number): string | null {
  if (count <= 0) return null;
  return count > 99 ? "99+" : String(count);
}
