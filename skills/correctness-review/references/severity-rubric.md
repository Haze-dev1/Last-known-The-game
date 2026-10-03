# Severity rubric

Assign severity from these criteria, not from how serious the finding felt to write.
Severity assigned by vibes is why review comments get argued about instead of fixed,
and it is why a "Critical" from an inconsistent reviewer gets read as "Medium".

Two questions decide almost every case:

1. **Does it produce a wrong result, or only a worse experience?**
2. **Does it need an unlucky coincidence to happen, or does it happen on Tuesday?**

---

## Critical

Data loss, data corruption, silent wrong results in production, or a security
consequence, on a path that runs in normal operation.

The distinguishing property is **silence**: nobody finds out. A crash is not
Critical, because a crash reports itself. A pricing function returning another
customer's currency is Critical, because it returns a plausible number forever.

- writes wrong data, or destroys data
- returns wrong results to users without erroring
- corrupts persisted state, or writes something the reader cannot parse back
- exposes one user's data to another

**Blocks the merge.**

---

## High

Fails, but loudly — or is wrong only under conditions that will certainly occur.

- crashes or 500s on a reachable input
- deadlock, livelock, or a hang
- resource exhaustion under normal load: leaked connections, unbounded growth
- breaks existing callers or stored data (signature, schema, or format change with
  no migration)
- a race that needs concurrency the system actually has — do not rate a race High
  because it is theoretically possible; rate it High because the contract says four
  workers
- the change does not do what was asked

**Blocks the merge.**

---

## Medium

Wrong under conditions that are plausible but not guaranteed, or right today and
fragile against a change that is likely.

- unhandled edge case reachable through unusual but legitimate input
- error swallowed where the caller could have acted on it
- missing validation with no security consequence
- performance problem that will bite at a larger but foreseeable scale
- a latent bug that is currently masked by a caller's behaviour — the bug is real,
  the mask is not guaranteed to hold

**`APPROVE WITH CHANGES`.** Worth fixing before merge; not worth blocking a release
over alone.

---

## Low

Real, small, and safely deferrable. A maintenance cost rather than a defect.

- confusing name that will be misread later
- duplicated logic that will drift apart
- missing or wrong docstring on a public function
- dead code, unused import, unreachable branch
- inconsistent with a strong convention elsewhere in the file

Report individually only if few. Otherwise group.

---

## Nit

Formatting, ordering, phrasing, personal preference. Anything a formatter would fix
if configured to.

**Always grouped into a single line.** Never itemised. Forty nits bury the one real
bug — that is the observed outcome, not a warning.

---

## Adjusting the default

Move a finding **up** one level when:

- it is on an authentication, authorization, payment, or migration path
- it is in code the contract lists as an invariant
- it fails silently rather than loudly (silence is the multiplier)
- it is in code that is hard to change later — a published API, a serialization
  format, anything with data already written in it

Move a finding **down** one level when:

- it is genuinely unreachable, and you have *traced* that rather than assumed it
- it is in test-only or development-only code with no production path
- an existing check upstream makes the bad input impossible, and you have read that
  check

Never move a finding down because the code is new, temporary, internal, or written
by someone who will be annoyed. That is not a severity adjustment; it is a decision
not to report, made without saying so.

---

## When unsure between two levels

Pick the lower one and say why it might be the higher one, in one clause. That is
more useful to the reader than either bare label, and it does not spend credibility
on a severity you cannot defend.
