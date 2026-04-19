/**
 * CaravelaSvelte REST (Inertia-style) client runtime.
 *
 * `initRest()` boots the page from the `data-page` attribute on a
 * `data-mode="rest"` root element, mounts a dynamic `PageRoot`
 * component, and wires up browser history so subsequent
 * `navigate()` calls push/restore the right page without full
 * reloads.
 *
 * Usage from a consumer app's `app.js`:
 *
 *     import { initRest } from "@caravela/svelte/rest"
 *
 *     const components = import.meta.glob(
 *       "./svelte/**\/*.svelte",
 *       { eager: true },
 *     )
 *
 *     initRest({
 *       resolveComponent: (name) =>
 *         components[`./svelte/${name}.svelte`]?.default,
 *     })
 */

import { mount } from "svelte";

import { findModeRoot, readMode } from "../mode";
import { pageState } from "./page-state";
import { installHistoryHandler } from "./navigate";
import PageRoot from "./PageRoot.svelte";

export interface PageObject {
  component: string;
  props: Record<string, unknown>;
  url: string;
  version: string;
}

export interface InitRestOptions {
  /**
   * Resolve a component name string (as emitted by the server's
   * `page_object.component`) to its Svelte component constructor.
   */
  resolveComponent: (name: string) => unknown;

  /**
   * Override the document the runtime looks at. Mostly useful for
   * tests / SSR-side rendering.
   */
  document?: Document;
}

export interface InitRestHandle {
  /**
   * Unmount the runtime and remove the history handler. Idempotent.
   */
  destroy: () => void;
}

/**
 * Boot the REST runtime. No-ops (returns `null`) when the current
 * page isn't a CaravelaSvelte REST page.
 */
export function initRest(options: InitRestOptions): InitRestHandle | null {
  const doc = options.document ?? document;
  const root = findModeRoot(doc);

  if (!root || readMode(root) !== "rest") {
    return null;
  }

  const page = readPageObject(root);
  if (!page) {
    console.error(
      "[caravela_svelte] rest root missing or invalid data-page attribute",
    );
    return null;
  }

  // Seed page state and push an initial history entry so back-
  // button handling has something to restore to.
  pageState.set(page);
  history.replaceState({ page }, "", page.url);

  // Clear the data-page attribute — the store owns the state now.
  root.removeAttribute("data-page");

  const instance = mount(PageRoot, {
    target: root,
    props: {
      resolveComponent: options.resolveComponent as never,
    },
  });

  const uninstallHistory = installHistoryHandler();

  return {
    destroy: () => {
      uninstallHistory();
      // Svelte 5's `mount` returns an instance whose `destroy` is
      // the shutdown hook (runtime-provided).
      (instance as { $destroy?: () => void }).$destroy?.();
    },
  };
}

/**
 * Read and JSON-parse the `data-page` attribute from a root
 * element. Returns `null` on any failure (absent, malformed JSON,
 * missing required keys).
 */
export function readPageObject(root: HTMLElement): PageObject | null {
  const raw = root.getAttribute("data-page");
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw);
    if (
      typeof parsed.component === "string" &&
      typeof parsed.url === "string" &&
      typeof parsed.version === "string" &&
      parsed.props &&
      typeof parsed.props === "object"
    ) {
      return parsed as PageObject;
    }
  } catch {
    // fall through
  }

  return null;
}

// --- Public sub-module surface ---------------------------------------
//
// Users import from `@caravela/svelte/rest`. The re-exports below
// are the stable API for B.3.

export { navigate } from "./navigate";
export type { NavigateOptions, NavigateMethod } from "./navigate";
export { pageState, currentPage } from "./page-state";
export { useNavigate } from "./useNavigate";
export { useForm } from "./useForm";
export type { UseFormOptions, UseFormReturn, FormErrors } from "./useForm";
export { default as Link } from "./Link.svelte";
