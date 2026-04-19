/**
 * CaravelaSvelte REST (Inertia-style) client runtime — skeleton.
 *
 * Boots a Svelte component from a `data-page` attribute on the
 * root element. Phase B.2 implements the first-load mount only;
 * history interception + SPA navigation land in B.3.
 *
 * Usage from a consumer app's `app.js`:
 *
 *     import { initRest } from "@caravela/svelte/rest"
 *
 *     const components = import.meta.glob("./svelte/**\/*.svelte",
 *                                          { eager: true })
 *
 *     initRest({
 *       resolveComponent: (name) =>
 *         components[`./svelte/${name}.svelte`].default,
 *     })
 */

import type { Component } from "svelte";
import { mount } from "svelte";

import { findModeRoot, readMode } from "../mode";

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
  resolveComponent: (name: string) => Component | null | undefined;

  /**
   * Override the document the runtime looks at. Mostly useful for
   * tests / SSR-side rendering.
   */
  document?: Document;

  /**
   * Called with the mounted Svelte instance. Use this to swap
   * props on SPA navigation (once B.3 lands that machinery).
   */
  onMount?: (instance: ReturnType<typeof mount>) => void;
}

/**
 * Boot the REST runtime. No-ops when the current page isn't a
 * CaravelaSvelte REST page.
 *
 * Returns the mounted Svelte instance, or `null` when no mount
 * happened.
 */
export function initRest(options: InitRestOptions): ReturnType<typeof mount> | null {
  const doc = options.document ?? document;
  const root = findModeRoot(doc);

  if (!root || readMode(root) !== "rest") {
    return null;
  }

  const page = readPageObject(root);
  if (!page) {
    console.error("[caravela_svelte] rest root missing or invalid data-page attribute");
    return null;
  }

  const Comp = options.resolveComponent(page.component);
  if (!Comp) {
    console.error(
      `[caravela_svelte] unknown component "${page.component}"; check resolveComponent mapping`,
    );
    return null;
  }

  const instance = mount(Comp, {
    target: root,
    props: { ...page.props, live: null },
  });

  options.onMount?.(instance);

  return instance;
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
