/**
 * REST-mode navigation — Inertia-style.
 *
 * `navigate(url, opts)` fetches the target URL with the
 * `x-inertia: true` and `x-inertia-version: <digest>` headers the
 * server expects, swaps the `pageState` store, and updates
 * `history`. Callers of `navigate()` should be on a page booted
 * by `initRest` — otherwise the call logs an error and does a
 * hard reload.
 *
 * A 409 with `x-inertia-location` header forces a hard reload
 * (the server has bumped its asset version; the client bundle is
 * stale).
 *
 * 422 responses are treated as form-validation errors: `opts.onError`
 * is called with the parsed body. This is how `useForm` gets its
 * errors back.
 *
 * The current page's asset version is read from the store at call
 * time so navigations always match the server's latest view of the
 * bundle.
 */

import { pageState, currentPage } from "./page-state";
import type { PageObject } from "./index";

export type NavigateMethod = "get" | "post" | "put" | "patch" | "delete";

export interface NavigateOptions {
  /**
   * HTTP method. Defaults to `"get"`. Non-GET methods send the
   * `data` as a JSON body.
   */
  method?: NavigateMethod;

  /**
   * Payload for non-GET requests. JSON-encoded and sent as the
   * body with `Content-Type: application/json`.
   */
  data?: Record<string, unknown>;

  /**
   * When `true`, replace the current history entry instead of
   * pushing a new one. Useful for form re-renders after validation.
   */
  replace?: boolean;

  /**
   * Called with the server-sent errors map on a 422 response. The
   * response body is `{ errors: Record<string, string[]> }`.
   */
  onError?: (errors: Record<string, string[]>) => void;

  /**
   * Called after successful navigation. Receives the new page
   * object.
   */
  onSuccess?: (page: PageObject) => void;

  /**
   * Optional AbortSignal for cancellation.
   */
  signal?: AbortSignal;
}

/**
 * Perform an Inertia-style navigation.
 */
export async function navigate(url: string, opts: NavigateOptions = {}): Promise<void> {
  const method = (opts.method ?? "get").toLowerCase() as NavigateMethod;
  const page = currentPage();
  const version = page?.version ?? "";

  const headers: Record<string, string> = {
    "x-inertia": "true",
    "x-inertia-version": version,
    accept: "application/json, text/html",
  };

  let body: BodyInit | undefined;

  if (method !== "get") {
    headers["content-type"] = "application/json";

    // CSRF token injected by the Phoenix layout as a <meta> tag.
    const csrf = document
      .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
      ?.getAttribute("content");

    if (csrf) headers["x-csrf-token"] = csrf;

    body = JSON.stringify(opts.data ?? {});
  }

  let res: Response;

  try {
    res = await fetch(url, {
      method: method.toUpperCase(),
      headers,
      body,
      credentials: "same-origin",
      signal: opts.signal,
    });
  } catch (err) {
    if ((err as DOMException)?.name === "AbortError") return;
    console.error("[caravela_svelte] navigate fetch failed", err);
    return;
  }

  // Version-mismatch: server tells us to hard-reload to a specific
  // location. The new document re-bootstraps the client bundle.
  if (res.status === 409) {
    const loc = res.headers.get("x-inertia-location");
    if (loc) {
      window.location.href = loc;
      return;
    }
  }

  // Form-validation errors.
  if (res.status === 422) {
    try {
      const parsed = (await res.json()) as { errors?: Record<string, string[]> };
      opts.onError?.(parsed.errors ?? {});
    } catch {
      opts.onError?.({});
    }
    return;
  }

  if (!res.ok) {
    console.error(`[caravela_svelte] navigate ${url} -> ${res.status}`);
    return;
  }

  // Normal Inertia navigation: JSON body is the new page object.
  let nextPage: PageObject;

  try {
    nextPage = (await res.json()) as PageObject;
  } catch (err) {
    console.error("[caravela_svelte] navigate response was not JSON", err);
    return;
  }

  pageState.set(nextPage);

  if (opts.replace) {
    history.replaceState({ page: nextPage }, "", nextPage.url);
  } else {
    history.pushState({ page: nextPage }, "", nextPage.url);
  }

  opts.onSuccess?.(nextPage);
}

/**
 * Install the `popstate` handler so browser back/forward buttons
 * restore the right page. Called once by `initRest()`.
 */
export function installHistoryHandler(): () => void {
  const handler = (ev: PopStateEvent) => {
    const page = (ev.state as { page?: PageObject } | null)?.page;

    if (page) {
      // Restore from history state — no refetch needed.
      pageState.set(page);
    } else {
      // Missing history state (e.g. arrived via a back button from
      // a non-Inertia page) — refetch.
      navigate(window.location.pathname + window.location.search, {
        replace: true,
      });
    }
  };

  window.addEventListener("popstate", handler);
  return () => window.removeEventListener("popstate", handler);
}
