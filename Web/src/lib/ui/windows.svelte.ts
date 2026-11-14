// The in-page replacement for NSWindow: floating windows the user can drag,
// resize and close. Windows the AppKit app keeps in a stored `xxxController`
// and shows again are singletons here: opening one with the same `key` brings
// the existing window to the front instead of opening a second one.
import type { Component } from "svelte";

/** A component shown inside a window. It always receives `windowId`; other props come from `WindowSpec.props`. */
export type WindowContent = Component<{ windowId: number }>;

/**
 * Window contents take their own props besides `windowId`, which a plain
 * `Component<{ windowId }>` would reject. The host passes `props` through, so
 * this widening cast is safe as long as the spec's `props` match the component.
 */
export function asWindowContent<P extends { windowId: number }>(component: Component<P>): WindowContent {
  return component as unknown as WindowContent;
}

export interface WindowSpec {
  /** Singleton key. Opening a window with a key that is already open focuses it. */
  key?: string;
  title: string;
  /** Content size in px (the Swift `contentRect`). */
  width: number;
  height: number;
  minWidth?: number;
  minHeight?: number;
  /** True for windows built with `EscClosableWindow`. */
  escCloses?: boolean;
  /** The component shown inside; it receives `props` plus `windowId`. */
  component: WindowContent;
  props?: Record<string, unknown>;
  onClose?: () => void;
  /** Called before closing; return false to keep the window open (`windowShouldClose`). */
  canClose?: () => boolean | Promise<boolean>;
}

export interface WindowState {
  id: number;
  spec: WindowSpec;
  title: string;
  x: number;
  y: number;
  width: number;
  height: number;
  z: number;
}

export const windowStore = $state<{ list: WindowState[]; top: number }>({ list: [], top: 0 });

let nextId = 1;
const TITLE_BAR = 28;
const MIN_WIDTH = 300;
const MIN_HEIGHT = 200;

function viewport() {
  const top = document.querySelector("[data-app-menu]")?.getBoundingClientRect().bottom ?? 0;
  return { left: 0, top, right: window.innerWidth, bottom: window.innerHeight,
    width: window.innerWidth, height: Math.max(0, window.innerHeight - top) };
}

/** Opens a window centred below the app menu at its content size, clamped to the usable viewport. */
export function openWindow(spec: WindowSpec): number {
  if (spec.key) {
    const existing = windowStore.list.find((w) => w.spec.key === spec.key);
    if (existing) {
      focusWindow(existing.id);
      return existing.id;
    }
  }
  const page = viewport();
  const width = Math.min(spec.width, page.width);
  const height = Math.min(spec.height + TITLE_BAR, page.height);
  // Cascade windows that open at the same spot a little, like AppKit's cascading.
  const offset = (windowStore.list.length % 6) * 24;
  const x = Math.max(page.left, Math.min(Math.round((page.width - width) / 2) + offset - 60, page.right - width));
  const y = Math.max(page.top, Math.min(page.top + Math.round((page.height - height) / 2) + offset - 60, page.bottom - height));
  const state: WindowState = {
    id: nextId++,
    spec,
    title: spec.title,
    x,
    y,
    width,
    height,
    z: ++windowStore.top,
  };
  windowStore.list.push(state);
  return state.id;
}

export function focusWindow(id: number): void {
  const found = windowStore.list.find((w) => w.id === id);
  if (found && found.z !== windowStore.top) found.z = ++windowStore.top;
}

export function setWindowTitle(id: number, title: string): void {
  const found = windowStore.list.find((w) => w.id === id);
  if (found) found.title = title;
}

/** Closes a window unless its `canClose` refuses. Resolves true when it closed. */
export async function closeWindow(id: number): Promise<boolean> {
  const found = windowStore.list.find((w) => w.id === id);
  if (!found) return true;
  if (found.spec.canClose && !(await found.spec.canClose())) return false;
  const index = windowStore.list.findIndex((w) => w.id === id);
  if (index >= 0) windowStore.list.splice(index, 1);
  found.spec.onClose?.();
  return true;
}

export function windowIsOpen(key: string): boolean {
  return windowStore.list.some((w) => w.spec.key === key);
}

export function topWindowId(): number | null {
  let best: WindowState | null = null;
  for (const w of windowStore.list) if (!best || w.z > best.z) best = w;
  return best ? best.id : null;
}

export function moveWindow(id: number, x: number, y: number): void {
  const found = windowStore.list.find((w) => w.id === id);
  if (!found) return;
  const page = viewport();
  found.x = Math.max(page.left, Math.min(x, page.right - found.width));
  found.y = Math.max(page.top, Math.min(y, page.bottom - found.height));
}

export function resizeWindow(id: number, x: number, y: number, width: number, height: number, edge = ""): void {
  const found = windowStore.list.find((w) => w.id === id);
  if (!found) return;
  const page = viewport();
  const minW = Math.min(Math.max(found.spec.minWidth ?? 0, MIN_WIDTH), page.width);
  const minH = Math.min(Math.max((found.spec.minHeight ?? 0) + TITLE_BAR, MIN_HEIGHT), page.height);
  const right = Math.max(page.left + minW, Math.min(x + width, page.right));
  const bottom = Math.max(page.top + minH, Math.min(y + height, page.bottom));
  const left = Math.max(page.left, Math.min(x, page.right - minW));
  const top = Math.max(page.top, Math.min(y, page.bottom - minH));
  const maxW = edge.includes("w") ? right - page.left : edge ? page.right - left : page.width;
  const maxH = edge.includes("n") ? bottom - page.top : edge ? page.bottom - top : page.height;
  found.width = Math.max(minW, Math.min(width, maxW));
  found.height = Math.max(minH, Math.min(height, maxH));
  found.x = edge.includes("w") ? right - found.width : left;
  found.y = edge.includes("n") ? bottom - found.height : top;
  moveWindow(id, found.x, found.y);
}

export const WINDOW_TITLE_BAR = TITLE_BAR;
