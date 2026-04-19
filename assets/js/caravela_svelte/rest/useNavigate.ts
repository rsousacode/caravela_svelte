/**
 * `useNavigate` composable for REST mode.
 *
 * Returns a function that performs Inertia-style navigation. Thin
 * wrapper around `navigate/2` that lets future mode-aware variants
 * hook in without callers changing their code.
 *
 * Usage:
 *
 *     import { useNavigate } from "@caravela/svelte/rest"
 *
 *     const go = useNavigate()
 *     // ...
 *     go("/library/books", { replace: true })
 */

import { navigate, type NavigateOptions } from "./navigate";

export type NavigateFn = (url: string, opts?: NavigateOptions) => Promise<void>;

export function useNavigate(): NavigateFn {
  return navigate;
}
