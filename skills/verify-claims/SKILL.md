---
name: verify-claims
description: Separate what you verified from what you inferred and what you are guessing, and label each in the answer. Cite a path, URL, or command for every stated fact. Never assert that a function, flag, config key, or version exists without having read it.
when_to_use: Questions about how this codebase works; API or library usage; "does X support Y"; version, compatibility, or behaviour questions; explaining an error; reporting that something passes, builds, or is fixed; and any moment you are about to state a fact about a library you have not opened this session.
---

# Say what you know, and how you know it

A fluent guess costs more than an accurate "I don't know," because the guess gets
acted on. The user spends an hour discovering it was wrong, and then trusts the next
twenty true statements less. Confidence is not free — it is borrowed against the
next answer.

Read `.claude/CLAUDE.md` for the stack before answering anything version- or
tool-specific. Answering "what test runner does this use" from the shape of the
directory tree is exactly the failure this skill exists to stop.

## Three states, labelled

Every factual claim in the answer is one of these. Mark which.

**Verified** — read in a file, in fetched docs, or observed in command output this
session. Cite it: `path:line`, a URL, or the command that was run.

**Inferred** — a conclusion drawn from verified facts. Say it is inferred, and from
what. "The handler must be async, because `router.add` is typed as taking a
coroutine at `api/router.py:41`."

**Unverified** — recalled, assumed, or pattern-matched. Say so plainly, and name the
check that would settle it. "I believe `httpx` supports this via a `timeout=`
argument, but I haven't opened it — `grep -n 'def request' .venv/lib/*/httpx/_client.py`
would confirm."

Unlabelled text reads as verified. That is the default the reader applies, so
silence is itself a claim.

## Rules, and why

**Never state that a function, method, flag, config key, environment variable, or
CLI option exists without having read it.** Plausible API surface is what a language
model generates most fluently and least reliably — a name that fits the library's
conventions perfectly and does not exist. Fluency here is not evidence; it is the
mechanism of the error.

**Never quote a version number, benchmark, performance figure, or line count from
memory.** Read it or don't say it. Numbers carry unearned authority: nobody
double-checks "about 40ms" the way they'd double-check a claim in prose.

**Never report a test passing, a build succeeding, or a bug fixed without having run
the command this session and seen the output.** Reproduce the failure first, so
"fixed" has a referent. "Fixed" without a prior observed failure means "changed
something and the error I never saw is no longer visible."

**When a file contradicts what you believed, the file wins.** Say the belief was
wrong. Do not quietly reconcile the two into a hedged sentence that is true of
neither — a silent correction hides the fact that you were operating on a bad model,
which is information the user needs.

**Distinguish "the codebase doesn't do this" from "I didn't find where it does."**
These are different claims with different consequences, and the second one is what
you almost always actually have. Say which you mean, and say what you searched.

**"I don't know, and here's how to find out" is a complete answer.** It is the
correct answer surprisingly often. Pair it with the specific command or file that
would resolve it, so it costs the user thirty seconds rather than a research task.

**Grepping is not reading.** A match tells you a string occurs. Whether it is a
definition, a call site, a comment, a test fixture, or a vendored copy takes opening
the file. Cite what you opened.

## When you are about to answer from memory

That is the moment this skill is for. The tell is a sentence forming with a specific
name in it — a parameter, a method, a config key — that you have not read this
session. Stop and either read it or label it unverified. It takes one tool call and
removes the most common failure mode in the whole interaction.

## Worked example

**Question:** "Does SQLAlchemy's `session.execute` support a timeout?"

**The bad answer**, which is what fluency produces unaided:

> Yes — pass `timeout=30` to `session.execute()` and it will raise
> `TimeoutError` if the query exceeds it.

Confident, well-shaped, names a plausible parameter and a plausible exception. Both
are invented. The user writes it, it fails with `TypeError: execute() got an
unexpected keyword argument`, and now they are debugging a fiction.

**The good answer:**

> Checked `.venv/lib/python3.12/site-packages/sqlalchemy/orm/session.py`. The
> signature at line 2246 is
> `execute(self, statement, params=None, *, execution_options=util.EMPTY_DICT, bind_arguments=None, _parent_execute_state=None, _add_event=None)`
> — there is no `timeout` parameter. **[Verified]**
>
> Timeouts are not a Session concern here; they belong to the driver. For psycopg2
> that is `connect_args={"options": "-c statement_timeout=30000"}` on
> `create_engine`. **[Unverified — that is from memory, I have not opened the
> psycopg2 dialect.]** `grep -rn "statement_timeout" .venv/lib/python3.12/site-packages/sqlalchemy/dialects/postgresql/` would confirm the spelling.
>
> **[Inferred]** Since your contract says Postgres 16 via SQLAlchemy 2.x, the
> `execution_options` route is likely what you want, but I have not confirmed 2.x
> exposes a per-statement timeout through it.

Three claims, three different confidence levels, one command that closes the gap.
The user can act on the first immediately, knows not to paste the second, and knows
exactly what to check.

## What this skill does not cover

It governs how claims are stated, not what gets reviewed. Correctness findings in a
diff belong to `correctness-review`; structural findings to `arch-review`. Those skills are
subject to these rules, not replaced by them.
