---
name: tech-writing
description: Write technical documentation that is correct and typed to its purpose — README, API reference, tutorial, how-to, explanation, ADR, runbook, changelog, docstring. Every command, signature, path, and flag is read from the code or executed, never recalled.
when_to_use: Write or update documentation, a README, API docs, docstrings, a changelog, a migration guide, an ADR, a design doc, a runbook, onboarding notes, release notes, or a comment explaining why; "document this"; "explain how this works" for another reader; after implementing something notable.
---

# Technical writing

## 1. Identify the document type first

The types have genuinely different structures, audiences, and success conditions.
Conflating them is the most common documentation failure and it produces a document
that serves nobody — a tutorial interrupted by API tables, a reference that keeps
stopping to explain motivation.

Read `references/document-types.md` and follow the structure for the type you are
writing. If the request does not say which type, decide from the reader's situation
and state your choice in one line before starting.

The core distinction, from the Diátaxis split:

|              | serves        | reader is                          |
| ------------ | ------------- | ---------------------------------- |
| Tutorial     | learning      | new, following along, needs a win  |
| How-to       | a goal        | competent, has a specific problem  |
| Reference    | lookup        | knows what they want, needs detail |
| Explanation  | understanding | curious, not currently doing it    |

A reader in one of those situations is badly served by any of the other three.

## 2. Verify everything

Inherited from `verify-claims`, and stricter here.

Every command, signature, path, flag, config key, environment variable, port, and
default value is **read from the code or executed**, never recalled. Run the
examples. Open the function and copy its actual parameters.

Wrong documentation is worse than absent documentation, because it is trusted.
Someone reads it instead of the code, pastes the command, and debugs the resulting
error against the assumption that the docs were right. Absent documentation sends
them to the source in thirty seconds.

Anything that cannot be verified gets marked, not shipped: "`--parallel` — I have
not confirmed this flag exists in the installed version."

## 3. Style

**Lead with what it does and who it is for.** No preamble, no throat-clearing, no
paragraph about the importance of the problem space. The first sentence should let a
reader decide whether to keep reading.

**Present tense, active voice, second person for instructions.** "Run `make test`",
not "the test suite may be run".

**Every code example complete enough to run**, including the imports, and actually
run before it ships. Half an example is a puzzle.

**Document failure modes and error messages, not just the happy path.** Nobody reads
documentation while things are working. The most valuable page in most projects is
the one listing real error strings next to what causes them — and it is almost
always the missing one. If an error message is a literal string in the code, quote
it exactly, so search finds it.

**Say why wherever a decision is non-obvious.** The how is recoverable from the
code; the why is not, and it is the thing a maintainer needs in a year.

**No marketing adjectives.** No "powerful", "seamless", "robust", "blazing". They
carry no information and cost the reader's trust.

**Never "simply", "just", "obviously", "of course".** A reader who is stuck — which
is every reader of documentation — is told by these words that the thing they cannot
do is easy. That is the opposite of help, and it is the single most common tonal
defect in developer documentation.

**A short accurate document beats a long comprehensive one.** Length is not
thoroughness. Anything unverified, restated, or written to look complete is
subtracting.

## 4. ADRs

Context, decision, status, consequences, alternatives considered and why rejected.

**The rejected alternatives are the most valuable section and the one usually
omitted.** Without it, the next person re-proposes the rejected option, and nobody
remembers whether it was rejected for a real reason or never considered. Write what
was actually wrong with each — "Redis: adds an operational dependency we would need
to run in three environments for a cache we can rebuild in 40ms" — not that it "did
not fit our needs".

Consequences include the bad ones. An ADR with only upside is a proposal, not a
record.

## 5. Docstrings

Document what the caller needs and cannot see from the signature: units,
ownership, mutation, raising behaviour, side effects, thread safety.

Do not restate the signature in prose. `"""Gets the user by id."""` on
`get_user(id: int) -> User` is pure cost. `"""Returns None if the user is soft-deleted;
callers that need deleted rows use get_user_including_deleted()."""` earns its space.

## Worked example

**A bad README opening**, and it is the shape most of them have:

> # DataFlow
>
> ## Introduction
>
> In today's fast-paced data landscape, organizations need powerful and flexible
> tools to handle their data processing needs. DataFlow is a modern, lightweight,
> and blazing-fast framework designed to make data pipelines simple and enjoyable.
>
> ## Getting Started
>
> First, make sure you have the prerequisites installed. Then simply run the
> installer and you're good to go!

Nothing here is information. After forty words the reader still cannot tell what it
does, whether it applies to them, or how to install it. "Prerequisites" are not
named, "the installer" is not named, and "simply" is doing the work that a command
should be doing.

**The rewrite:**

> # DataFlow
>
> Runs Python data pipelines defined as DAGs, on a single machine, with checkpointing
> between steps. For batch jobs too big for a script and too small for Airflow.
>
> Not a scheduler — pair it with cron or systemd timers.
>
> ## Install
>
> Requires Python 3.11+ and `uv`.
>
> ```bash
> uv pip install dataflow
> dataflow --version   # 0.7.2
> ```
>
> ## A pipeline
>
> ```python
> from dataflow import Pipeline, step
>
> @step
> def load(path: str) -> list[dict]:
>     return read_csv(path)
>
> @step
> def clean(rows: list[dict]) -> list[dict]:
>     return [r for r in rows if r["amount"]]
>
> Pipeline([load, clean]).run("data.csv")
> ```
>
> Checkpoints land in `.dataflow/`; a rerun resumes from the last completed step.
> Delete the directory to force a full rerun.
>
> ## When it fails
>
> `StepTypeError: step 'clean' expects list[dict], got None` — the previous step
> returned nothing. A `@step` must return a value; `None` is not a valid checkpoint.

Second version, roughly the same length. It says what it is, what it is not, the
exact version constraint, a runnable example, where state lives, how to reset it,
and one real error message with its cause. Every line answers a question a reader
actually has.
