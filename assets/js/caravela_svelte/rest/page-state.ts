/**
 * Page-state store for REST mode.
 *
 * Holds the current `PageObject` and is swapped on SPA
 * navigation. Svelte components subscribe via `$pageState`.
 *
 * Uses `svelte/store` (not the `$state` rune) so the module can
 * stay a plain `.ts` file and be imported from anywhere.
 */

import { writable, type Writable } from "svelte/store";

import type { PageObject } from "./index";

export const pageState: Writable<PageObject | null> = writable(null);

/**
 * Convenience snapshot of the current page without subscribing.
 * Useful inside event handlers that don't need reactivity.
 */
export function currentPage(): PageObject | null {
  let snapshot: PageObject | null = null;
  const unsub = pageState.subscribe((v) => {
    snapshot = v;
  });
  unsub();
  return snapshot;
}
