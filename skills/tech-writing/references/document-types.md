# Document types

Pick one before writing. A document that is two of these at once serves neither
reader, because their situations are incompatible: the learner needs to be carried,
the looker-up needs to be left alone.

---

## README

The reader is deciding whether this project is for them, in about thirty seconds.

1. **Name, then one or two sentences: what it does and who for.** Concrete enough to
   exclude people. "For batch jobs too big for a script and too small for Airflow."
2. **What it is not.** Prevents the most common wrong expectation. Cheap, and almost
   never written.
3. **Install**, with the version constraints that actually matter, and a command
   that verifies it worked.
4. **Smallest complete working example.** Runnable as printed.
5. **Where to go next** — links to the real documentation.
6. **Common failures**, if there are one or two that everyone hits.

Not in a README: architecture tours, exhaustive configuration tables, contribution
guidelines, philosophy. Link them.

---

## API reference

The reader knows what they want and needs the detail. Optimised for lookup, not
reading. Completeness and consistency matter more than prose.

Per entry: signature with types · what it does in one line · each parameter,
including units and whether it is mutated · return value, including the empty and
error cases · what it raises and when · side effects · one short example.

Same order every time. A reference where entries vary in shape cannot be skimmed.

---

## Tutorial

The reader is new and needs a success. Learning-oriented.

Single narrative path, no branching, no options. Every command in order, nothing
assumed. State the end result up front so they know where they are going, and give
them something visibly working early. Tell them what they should see after each
step, so they can detect divergence themselves.

Do not explain alternatives, do not editorialise about best practices, do not
mention the twelve other ways to do it. Those belong in explanation, and here they
are just obstacles. Say at the end what they have built and what to read next.

---

## How-to

The reader is competent and has a specific problem. Goal-oriented.

Title is the goal, phrased as they would search for it: "Rotate the signing key
without downtime." Assume competence. State prerequisites and starting state, give
the steps, note the branch points that matter. No teaching.

---

## Explanation

The reader wants to understand something and is not currently doing it.
Understanding-oriented.

Why it works this way. What the alternatives were. What the tradeoff was and what it
cost. History where it explains a constraint that otherwise looks arbitrary.

No step-by-step instructions here — the moment they appear, it has become a how-to
with distractions.

---

## ADR

A record for someone who was not in the room, read years later.

- **Title** — the decision, not the topic. "Use Postgres advisory locks for job
  claiming", not "Job locking".
- **Status** — proposed / accepted / superseded by *X*. Keep superseded ones;
  deleting them destroys the record.
- **Date**, absolute.
- **Context** — the forces. What was true that made this a decision rather than an
  obvious choice. Constraints, deadlines, existing commitments.
- **Decision** — active voice: "We will…"
- **Consequences** — including the bad ones and the things now harder. An ADR with
  only upside is a proposal.
- **Alternatives considered** — each with the specific reason it was rejected. The
  most valuable section, and the one usually missing. Without it the next person
  re-proposes the rejected option.

---

## Runbook

The reader is on call, at 3am, stressed, and possibly not the author.

- **Symptom first**, phrased as it appears — the literal alert name, the literal
  error string. They are matching against what is on their screen.
- **Impact** — who is affected, how badly. Determines whether to keep reading.
- **Diagnosis** — exact commands to run, with what the healthy output looks like.
- **Remediation** — numbered, copy-pasteable, with the destructive steps marked and
  each one's blast radius named.
- **Escalation** — who, and at what point.

No prose. No background. Every command copy-pasteable without editing, or it will be
mistyped. If a step requires judgement, say what the judgement is between.

---

## Changelog

The reader is deciding whether to upgrade, and what will break.

Grouped by version, newest first, with dates. Within a version: **Breaking** first,
always. Then Added, Changed, Fixed, Deprecated, Removed, Security.

Written from the user's perspective, not the commit's. "Timestamps in `/events` are
now UTC; clients parsing them as local time will shift by their offset" — not
"refactor datetime handling". Every breaking entry says what to do about it.

---

## Docstring

The reader has autocomplete open and does not want to read the source.

Say what the signature cannot: units, ownership and mutation, what it raises and
when, side effects, thread safety, and the empty/None/zero cases.

Do not restate the signature in prose. If the docstring is recoverable from the
name and types, delete it — it is a maintenance liability that will eventually
disagree with the code and be believed.
