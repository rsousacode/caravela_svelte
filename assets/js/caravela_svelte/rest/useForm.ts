/**
 * `useForm` composable for REST mode.
 *
 * Returns reactive `values` + `errors` stores plus `submit/change`
 * helpers. Submit POSTs the form to the action URL via `navigate`;
 * the server responds either with a new page (success) or a 422
 * whose body is `{ errors: ... }` (validation). Either way, the
 * composable updates its state in place and the mounted component
 * rerenders.
 *
 * Usage:
 *
 *     import { useForm } from "@caravela/svelte/rest"
 *
 *     const form = useForm({
 *       initial: { title: "", isbn: "" },
 *       action: "/library/books",
 *       method: "post",
 *     })
 *
 *     // In markup:
 *     // <input
 *     //   value={$form.values.title}
 *     //   oninput={(e) => form.change("title", e.currentTarget.value)}
 *     // />
 *     // <button onclick={form.submit}>Save</button>
 *
 * ### Scope
 *
 * Phase B.3 ships the happy path (submit, change, errors). Things
 * deferred:
 *
 *   - live validation via XHR on every keystroke (requires
 *     debouncing + per-field targeting; not common in REST mode).
 *   - nested / array field path manipulation helpers.
 *   - file uploads (the Inertia `multipart/form-data` path).
 */

import { writable, type Writable, type Readable, get, derived } from "svelte/store";

import { navigate, type NavigateMethod } from "./navigate";

export type FormErrors = Record<string, string[]>;

export interface UseFormOptions<T extends Record<string, unknown>> {
  /** Initial field values. */
  initial: T;
  /** URL the form submits to. */
  action: string;
  /** HTTP method. Defaults to `"post"`. */
  method?: NavigateMethod;
  /**
   * Override `replace` on successful submit. Default is to push a
   * new history entry.
   */
  replace?: boolean;
  /** Called after a successful submit. */
  onSuccess?: () => void;
}

export interface UseFormReturn<T extends Record<string, unknown>> {
  /** Readable snapshot of `{ values, errors, submitting }`. */
  subscribe: Readable<{ values: T; errors: FormErrors; submitting: boolean }>["subscribe"];
  /** Update a single field's value. */
  change: (field: keyof T & string, value: unknown) => void;
  /** Submit the form. Returns a promise that resolves after the round trip. */
  submit: () => Promise<void>;
  /** Reset to the initial values and clear errors. */
  reset: () => void;
}

export function useForm<T extends Record<string, unknown>>(
  options: UseFormOptions<T>,
): UseFormReturn<T> {
  const values: Writable<T> = writable({ ...options.initial });
  const errors: Writable<FormErrors> = writable({});
  const submitting: Writable<boolean> = writable(false);

  const combined = derived([values, errors, submitting], ([$v, $e, $s]) => ({
    values: $v,
    errors: $e,
    submitting: $s,
  }));

  const change: UseFormReturn<T>["change"] = (field, value) => {
    values.update((prev) => ({ ...prev, [field]: value }));
  };

  const submit: UseFormReturn<T>["submit"] = async () => {
    submitting.set(true);
    errors.set({});

    const data = get(values) as Record<string, unknown>;

    await navigate(options.action, {
      method: options.method ?? "post",
      data,
      replace: options.replace,
      onError: (errs) => {
        errors.set(errs);
      },
      onSuccess: () => {
        options.onSuccess?.();
      },
    });

    submitting.set(false);
  };

  const reset: UseFormReturn<T>["reset"] = () => {
    values.set({ ...options.initial });
    errors.set({});
    submitting.set(false);
  };

  return {
    subscribe: combined.subscribe,
    change,
    submit,
    reset,
  };
}
