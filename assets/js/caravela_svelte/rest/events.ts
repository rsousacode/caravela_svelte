/**
 * SSE real-time adapter for REST-mode pages.
 *
 * `subscribe(topic, onPatch, opts)` opens a one-way stream to the
 * server's SSE endpoint (registered by
 * `caravela_rest "...", ..., realtime: true`). The server broadcasts
 * JSON-Patch ops via `Phoenix.PubSub`; the adapter forwards each
 * `event: patch` frame to `onPatch(ops)`. Consumers typically call
 * `applyPatch($pageState.props, ops)` from inside the handler.
 *
 * If `EventSource` is unavailable (old browsers, corporate proxies
 * that strip streaming) or if the caller passes a `refreshInterval`,
 * the adapter falls back to `navigate(currentUrl, { replace: true })`
 * on an interval. Tiny code, big compatibility payoff.
 *
 * Example:
 *
 *     import { subscribe } from "@caravela/svelte/rest"
 *     import { applyPatch } from "@caravela/svelte"
 *     import { currentPage, pageState } from "@caravela/svelte/rest"
 *
 *     const stop = subscribe("dashboard:user:42", (ops) => {
 *       const page = currentPage()
 *       if (!page) return
 *       const nextProps = { ...page.props }
 *       applyPatch(nextProps, ops)
 *       pageState.set({ ...page, props: nextProps })
 *     })
 *
 *     // later:
 *     stop()
 */

import { navigate } from "./navigate";

export interface SubscribeOptions {
  /**
   * Path to the SSE endpoint. Defaults to
   * `<location.pathname>/__events`, matching the route registered
   * by `caravela_rest "...", realtime: true`.
   */
  path?: string;

  /**
   * Polling fallback interval in milliseconds. When set, the
   * adapter polls the current URL on the given interval via
   * `navigate(..., { replace: true })` _in addition to_ (or
   * instead of, when SSE is unavailable) the SSE stream. Unset =
   * no polling.
   */
  refreshInterval?: number;

  /**
   * Force the polling fallback even when `EventSource` is
   * available. Useful for environments with misbehaving proxies.
   * Requires `refreshInterval`.
   */
  forcePolling?: boolean;

  /** Called when the underlying `EventSource` errors. */
  onError?: (ev: Event) => void;

  /** Called when the stream is (re)opened. */
  onOpen?: (ev: Event) => void;

  /**
   * Override the `window` (testing hook). Defaults to the global
   * `window`.
   */
  window?: Window & typeof globalThis;
}

export type PatchOps = unknown[];

/**
 * Subscribe to server-pushed JSON-Patch ops for `topic`.
 *
 * Returns an `unsubscribe()` function that closes the stream and
 * stops any polling interval. Idempotent.
 */
export function subscribe(
  topic: string,
  onPatch: (ops: PatchOps) => void,
  opts: SubscribeOptions = {},
): () => void {
  const win = opts.window ?? (typeof window !== "undefined" ? window : undefined);

  if (!win) {
    // SSR / non-browser — no-op.
    return () => {};
  }

  const path = opts.path ?? win.location.pathname + "/__events";
  const url = appendTopic(path, topic);

  const canStream = typeof win.EventSource === "function" && !opts.forcePolling;
  let source: EventSource | null = null;
  let pollTimer: ReturnType<typeof setInterval> | null = null;
  let stopped = false;

  if (canStream) {
    source = new win.EventSource(url, { withCredentials: true });

    source.addEventListener("open", (ev) => {
      opts.onOpen?.(ev);
    });

    source.addEventListener("patch", (ev: MessageEvent) => {
      let ops: PatchOps;
      try {
        ops = JSON.parse(ev.data) as PatchOps;
      } catch (err) {
        console.error("[caravela_svelte] sse patch was not JSON", err);
        return;
      }
      onPatch(ops);
    });

    source.addEventListener("error", (ev) => {
      opts.onError?.(ev);
    });
  }

  if (opts.refreshInterval && opts.refreshInterval > 0) {
    pollTimer = setInterval(() => {
      if (stopped) return;
      navigate(win.location.pathname + win.location.search, { replace: true });
    }, opts.refreshInterval);
  }

  return () => {
    if (stopped) return;
    stopped = true;
    source?.close();
    if (pollTimer) clearInterval(pollTimer);
  };
}

/**
 * Append `topic=<name>` to a URL, preserving any existing query
 * string. Exported for tests.
 */
export function appendTopic(path: string, topic: string): string {
  const sep = path.includes("?") ? "&" : "?";
  return `${path}${sep}topic=${encodeURIComponent(topic)}`;
}

/**
 * Polling-only helper. Equivalent to `subscribe` with
 * `forcePolling: true` and no topic (no SSE).
 */
export function poll(
  intervalMs: number,
  opts: Omit<SubscribeOptions, "refreshInterval" | "forcePolling"> = {},
): () => void {
  const win = opts.window ?? (typeof window !== "undefined" ? window : undefined);
  if (!win || intervalMs <= 0) return () => {};

  const timer = setInterval(() => {
    navigate(win.location.pathname + win.location.search, { replace: true });
  }, intervalMs);

  return () => clearInterval(timer);
}
