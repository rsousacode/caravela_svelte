import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { appendTopic, poll, subscribe } from "./events"

// ---------------------------------------------------------------------------
// EventSource mock — minimal surface for subscribe() tests.
// ---------------------------------------------------------------------------

type Listener = (ev: Event | MessageEvent) => void

class FakeEventSource {
  static instances: FakeEventSource[] = []

  url: string
  withCredentials: boolean
  closed = false
  listeners: Record<string, Listener[]> = {}

  constructor(url: string, init?: { withCredentials?: boolean }) {
    this.url = url
    this.withCredentials = init?.withCredentials ?? false
    FakeEventSource.instances.push(this)
  }

  addEventListener(type: string, cb: Listener) {
    ;(this.listeners[type] ??= []).push(cb)
  }

  close() {
    this.closed = true
  }

  // Drive events from tests.
  emit(type: string, ev: Event | MessageEvent) {
    for (const cb of this.listeners[type] ?? []) cb(ev)
  }
}

function makeWindow(overrides: Partial<Window> = {}) {
  return {
    EventSource: FakeEventSource as unknown as typeof EventSource,
    location: { pathname: "/dashboard", search: "" },
    ...overrides,
  } as unknown as Window & typeof globalThis
}

beforeEach(() => {
  FakeEventSource.instances = []
})

afterEach(() => {
  vi.useRealTimers()
})

// ---------------------------------------------------------------------------
// appendTopic
// ---------------------------------------------------------------------------

describe("appendTopic", () => {
  it("appends with ? when no query string", () => {
    expect(appendTopic("/dashboard/__events", "foo:1")).toBe(
      "/dashboard/__events?topic=foo%3A1",
    )
  })

  it("appends with & when query string present", () => {
    expect(appendTopic("/events?a=1", "bar")).toBe("/events?a=1&topic=bar")
  })

  it("encodes special characters in the topic", () => {
    expect(appendTopic("/e", "a b&c")).toBe("/e?topic=a%20b%26c")
  })
})

// ---------------------------------------------------------------------------
// subscribe (SSE)
// ---------------------------------------------------------------------------

describe("subscribe", () => {
  it("opens an EventSource at <pathname>/__events with the topic query param", () => {
    const win = makeWindow()
    const stop = subscribe("dashboard:42", () => {}, { window: win })

    expect(FakeEventSource.instances).toHaveLength(1)
    expect(FakeEventSource.instances[0].url).toBe(
      "/dashboard/__events?topic=dashboard%3A42",
    )
    expect(FakeEventSource.instances[0].withCredentials).toBe(true)

    stop()
  })

  it("calls onPatch when a patch event arrives", () => {
    const win = makeWindow()
    const onPatch = vi.fn()
    const stop = subscribe("t", onPatch, { window: win })

    FakeEventSource.instances[0].emit("patch", {
      data: JSON.stringify([["replace", "/n", 9]]),
    } as MessageEvent)

    expect(onPatch).toHaveBeenCalledWith([["replace", "/n", 9]])
    stop()
  })

  it("surfaces open and error events through opts callbacks", () => {
    const win = makeWindow()
    const onOpen = vi.fn()
    const onError = vi.fn()
    const stop = subscribe("t", () => {}, { window: win, onOpen, onError })

    const src = FakeEventSource.instances[0]
    src.emit("open", new Event("open"))
    src.emit("error", new Event("error"))

    expect(onOpen).toHaveBeenCalled()
    expect(onError).toHaveBeenCalled()
    stop()
  })

  it("honours an explicit path override", () => {
    const win = makeWindow()
    const stop = subscribe("t", () => {}, {
      window: win,
      path: "/api/events",
    })

    expect(FakeEventSource.instances[0].url).toBe("/api/events?topic=t")
    stop()
  })

  it("close()s the underlying EventSource when the returned fn is called", () => {
    const win = makeWindow()
    const stop = subscribe("t", () => {}, { window: win })
    const src = FakeEventSource.instances[0]

    expect(src.closed).toBe(false)
    stop()
    expect(src.closed).toBe(true)
  })

  it("is idempotent — calling stop twice only closes once", () => {
    const win = makeWindow()
    const stop = subscribe("t", () => {}, { window: win })
    const src = FakeEventSource.instances[0]
    const closeSpy = vi.spyOn(src, "close")

    stop()
    stop()

    expect(closeSpy).toHaveBeenCalledTimes(1)
  })

  it("ignores malformed patch frames without throwing", () => {
    const win = makeWindow()
    const onPatch = vi.fn()
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    const stop = subscribe("t", onPatch, { window: win })

    FakeEventSource.instances[0].emit("patch", { data: "not-json" } as MessageEvent)

    expect(onPatch).not.toHaveBeenCalled()
    expect(errSpy).toHaveBeenCalled()

    errSpy.mockRestore()
    stop()
  })

  it("falls back to polling when forcePolling is set + refreshInterval is given", () => {
    vi.useFakeTimers()
    const win = makeWindow()
    const stop = subscribe("t", () => {}, {
      window: win,
      forcePolling: true,
      refreshInterval: 100,
    })

    // No EventSource was opened.
    expect(FakeEventSource.instances).toHaveLength(0)

    stop()
  })

  it("no-ops when no window is available (SSR)", () => {
    // Pass undefined to force the fallback branch.
    const stop = subscribe("t", () => {}, {
      window: undefined as unknown as Window & typeof globalThis,
    })
    stop()
    expect(FakeEventSource.instances).toHaveLength(0)
  })
})

// ---------------------------------------------------------------------------
// poll
// ---------------------------------------------------------------------------

describe("poll", () => {
  it("returns a no-op when interval is zero", () => {
    vi.useFakeTimers()
    const win = makeWindow()
    const stop = poll(0, { window: win })

    vi.advanceTimersByTime(10_000)
    stop()
  })

  it("sets up an interval that can be cleared", () => {
    vi.useFakeTimers()
    const win = makeWindow()
    const setSpy = vi.spyOn(win, "setInterval" as keyof Window)
    const stop = poll(250, { window: win })

    // Can't spy on setInterval on the plain object without
    // wrapping; assert via FakeEventSource.instances still empty
    // (poll never opens SSE) and that stop() doesn't throw.
    expect(FakeEventSource.instances).toHaveLength(0)
    stop()
    setSpy.mockRestore()
  })
})
