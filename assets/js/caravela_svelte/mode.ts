/**
 * Mode detection for CaravelaSvelte's dual-transport client runtime.
 *
 * A page is mounted in one mode; the mode is declared on a root
 * element's `data-mode` attribute:
 *
 *   - `data-mode="live"` → LiveView WebSocket (phx-hook wiring).
 *   - `data-mode="rest"` → Inertia-style HTTP navigation.
 *
 * Phase B.2 adds the `"rest"` detection path. The call site wires
 * its own init function per mode (see `initRest` in `./rest`).
 */

export type Mode = "live" | "rest";

export const MODE_ATTRIBUTE = "data-mode";

/**
 * Find the first element in the document that declares a mode.
 * Returns `null` when the page has no CaravelaSvelte root.
 */
export function findModeRoot(doc: Document = document): HTMLElement | null {
  return doc.querySelector<HTMLElement>(`[${MODE_ATTRIBUTE}]`);
}

/**
 * Read the mode from an element's `data-mode` attribute. Returns
 * `null` when the attribute is missing or unrecognised.
 */
export function readMode(el: HTMLElement | null): Mode | null {
  if (!el) return null;
  const value = el.getAttribute(MODE_ATTRIBUTE);
  if (value === "live" || value === "rest") return value;
  return null;
}
