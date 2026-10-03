---
name: correctness-review
description: Correctness-focused review of a diff read against the code it lands in. Checks the requirement, error handling, boundary values, concurrency, resource lifetimes, backward compatibility, and contract invariants. Every finding cites file:line and carries a severity from a written rubric.
when_to_use: Review this; check this; look this over; pre-commit or pre-PR review; after implementing a feature or fixing a bug; "did I miss anything"; "is this right"; reviewing a diff, a patch, or a branch before merge.
---

# Correctness review

Read `references/severity-rubric.md` before assigning any severity, so severity
comes from criteria rather than from tone of voice.

Read `.claude/CLAUDE.md` for the invariants and the off-limits list.

## 1. Read the diff, then read what it lands in

A diff reviewed in isolation misses the interesting bugs, because the interesting
bugs live at the seam between the new code and the code that was already there. The
diff shows a function that handles its inputs correctly; the file shows the two
existing callers that pass something else.

So: read the changed hunks, then open the files they are in, then find the callers
of anything whose signature or behaviour moved. That last step is where the real
findings come from.

## 2. Check in this order

Correctness before style. Style is the formatter's job and it is already running as
a hook.

**Does it do what was asked?** Compare against the stated requirement, not against
what the code appears to be trying to do. Reading the implementation to infer the
intent and then checking the implementation against that inferred intent is circular
and always passes.

**Error handling.** Swallowed exceptions, bare `except`, `catch {}`, ignored return
values, unchecked `Result` or `err`, errors logged with execution continuing as
though nothing happened. Ask what the caller sees when this fails — if the answer is
"a success value", that is the finding.

**Boundaries.** Off-by-one, empty collection, `None`/`nil`/`undefined`, zero,
negative, the maximum, unicode, and input far larger than expected. Walk the actual
values, do not just assert they were considered.

**Concurrency.** Shared mutable state, read-modify-write that is not atomic, a check
and a use with a gap between them, missing idempotence in anything that is retried,
lock ordering that could deadlock. If the code will run under more than one worker,
the single-threaded reading of it is not the reading that matters.

**Resources.** Files, sockets, connections, cursors, transactions, temp files,
subprocesses: opened on every path, closed on every path, including the exception
path. Missing context manager, `defer`, `finally`, or `Drop`. Unbounded growth in a
cache, list, or queue.

**Contract invariants.** Each one, against the diff.

**Backward compatibility.** Signature changes, schema migrations, serialization
format changes, API responses, and default values that break existing callers or
already-stored data. Data written by the old version has to be readable by the new
one unless something says otherwise.

**Silent behaviour changes.** Did the diff change something that was not part of the
request? That is a finding regardless of whether the change is an improvement,
because nobody asked for it and nobody will test it.

## 3. Strictness

**Never approve with "looks good" and nothing else.** Either name what was checked
and found sound, or name findings. An unspecific approval carries no information and
launders the reviewer's inattention as the author's correctness.

**Never soften a real finding to be agreeable.** If it is a bug, write "bug". Hedged
language on a genuine defect gets read as a style preference and skipped.

**Distinguish "this is wrong" from "I would do it differently."** Label preferences
as preferences and put them last, after the findings. Mixing them is what makes
reviews exhausting to read and easy to dismiss wholesale.

**Cite `file:line` on every finding.** An uncited finding is unactionable, and one
uncited finding makes the reader doubt the cited ones.

**If the diff is too large to review properly, say so and propose a split.** A
shallow pass over two thousand lines produces a green tick and no information, which
is worse than declining, because the tick gets recorded.

**Group the trivia.** Below the rubric's Low threshold, collapse into a single
summary line. Forty nits bury the one real bug — that is not a metaphor, it is the
observed outcome.

## 4. Output

Findings by severity, highest first. Then:

- `BLOCK` — at least one Critical or High
- `APPROVE WITH CHANGES` — Medium findings only
- `APPROVE` — nothing above Low

Then one line: **the single most important thing to fix first.** A reviewer who
names a priority gets acted on; a list of twelve equal items gets deferred.

## Scope

Owns correctness. Does not own security (`security-gate`), structure
(`arch-review`), assertion quality (`test-quality`), or whether the code is more
than it needs to be (`ponytail-review`, if installed). All four can run on the same
diff without repeating each other, which only works if each declines what is not
its own.

When a finding is genuinely dual — a correctness bug that is also exploitable —
report it here for the correctness consequence and note in one line that
`security-gate` owns the severity call.

## Worked example

**Diff:** a caching decorator added to `service/pricing.py`.

> **[High] Cache key omits the currency argument.** `service/pricing.py:23` — the
> key is built from `product_id` and `quantity` only, but `get_price` takes
> `currency` as its third parameter (line 19). The second caller with a different
> currency receives the first caller's price. `api/checkout.py:88` and
> `api/quote.py:41` both pass non-default currencies, so this is reachable today,
> not theoretically. Fix: include `currency` in the key tuple.
>
> **[Medium] Unbounded cache growth.** `service/pricing.py:14` — a module-level
> `dict` with no eviction, keyed by product and quantity. Quantity is
> caller-supplied and unbounded, so the dict grows without limit for as long as the
> process lives. `functools.lru_cache(maxsize=...)` or an explicit TTL.
>
> **[Medium] Exception path leaves a poisoned entry.** `service/pricing.py:31` —
> the placeholder is written to the cache before `_fetch` is called, and it is not
> removed when `_fetch` raises. Every later call for that key returns the
> placeholder. Write the entry after the call succeeds.
>
> **Checked and sound:** invariant on integer minor units holds — no float
> arithmetic introduced; the decorator preserves `functools.wraps`, so the two
> places that introspect `__name__` still work; no signature change, so no
> compatibility concern for existing callers.
>
> **Preference, not a finding:** I would name it `_price_cache` rather than
> `_cache`, given there are two other module-level caches in this package.
>
> **BLOCK.** Fix the cache key first — it returns wrong prices to real users, and
> the other two are only ever wasted memory.
