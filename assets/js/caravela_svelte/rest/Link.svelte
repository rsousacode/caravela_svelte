<script lang="ts">
  /**
   * REST-mode `<Link>` component.
   *
   * Renders an `<a>` tag that intercepts clicks and dispatches
   * through `navigate()` — Inertia-style SPA navigation without
   * a full page reload.
   *
   * Modifier-clicks (cmd/ctrl/shift/alt/middle-button) fall
   * through to the browser so users can open in a new tab as
   * expected.
   *
   * Live-mode apps should continue using the top-level `Link`
   * component (which wires `data-phx-link`); mixing the two on
   * the same page is fine since each targets a different
   * transport.
   *
   * @example
   *     <Link href="/library/books">Books</Link>
   *     <Link href="/library/books/new" replace>New</Link>
   */

  import type { Snippet } from "svelte";
  import { navigate, type NavigateMethod } from "./navigate";

  interface Props {
    /** Destination URL. */
    href: string;
    /** HTTP method. Defaults to `"get"`. */
    method?: NavigateMethod;
    /** Replace the current history entry instead of pushing. */
    replace?: boolean;
    /** Payload for non-GET requests. */
    data?: Record<string, unknown>;
    children?: Snippet;
    [key: string]: unknown;
  }

  let {
    href,
    method = "get",
    replace = false,
    data,
    children,
    ...rest
  }: Props = $props();

  function onclick(event: MouseEvent) {
    // Respect the native open-in-new-tab / new-window gestures.
    if (
      event.defaultPrevented ||
      event.button !== 0 ||
      event.metaKey ||
      event.ctrlKey ||
      event.shiftKey ||
      event.altKey
    ) {
      return;
    }

    event.preventDefault();
    void navigate(href, { method, replace, data });
  }
</script>

<a {href} {onclick} {...rest}>
  {@render children?.()}
</a>
