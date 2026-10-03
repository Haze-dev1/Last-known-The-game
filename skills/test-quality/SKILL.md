---
name: test-quality
description: Judge whether tests would actually catch a regression, rather than whether they exist. Flags assertion-free tests, over-mocking, missing failure paths, tests coupled to implementation detail, and non-determinism. Coverage percentage is not the question; assertion depth is.
when_to_use: Reviewing tests; "are these tests any good"; after writing or generating tests; before merging a change that adds tests; "is this well tested"; "why didn't the tests catch this"; a bug that reached production despite passing CI.
---

# Would these tests fail if the code were wrong?

That is the entire question. A suite can be green, fast, and eighty percent covering
while failing to constrain the implementation at all. Coverage measures which lines
ran, not whether anyone checked what they did — a test with no assertions covers
every line it touches.

Read `.claude/CLAUDE.md` for the stack and the invariants before starting. The
invariants are the properties most worth having tests for, and the ones most often
untested, because they are the things everybody on the team already knows.

## The central heuristic

For each test, ask: **what change to the implementation would make this fail?**

If the answer is "very little" — deleting the body, returning a constant, inverting
a condition — the test is decorative. It costs CI time and creates the impression of
coverage, which is worse than no test, because no test at least looks like no test.

Apply it literally. Take the function under test, imagine returning `None`
unconditionally, and see whether the assertions notice.

## What to flag

Each of these with the reason attached, because the reason is what makes the fix
obvious.

**Tests that only assert no exception was raised.** `run_import(data)` with nothing
after it passes on nearly any wrong implementation, including one that silently
imports zero rows. If the real assertion is hard to write, that is usually a design
finding, not a testing one.

**Mocking the unit under test.** Patching the very function being tested, or
patching so deeply that the assertions describe the mock's configured behaviour
rather than the code's. The tell: you could delete the implementation and the test
still passes because everything it touches is a `MagicMock`.

**Missing failure paths.** No test for the error branch, the timeout, the empty
collection, the boundary value, the malformed input. Happy paths are the ones that
get exercised in manual use anyway; the error branches are the code nobody has ever
actually run.

**Coupling to implementation detail.** Asserting on call counts, private attributes,
or the exact sequence of internal calls, where the behaviour is what matters. These
break on refactor and pass on regression — precisely backwards from what a test is
for.

**Non-determinism.** Real clocks, real network, unseeded randomness, dependence on
dict or filesystem ordering, dependence on which test ran first. A flaky test does
not just fail sometimes; it teaches the team to re-run CI without reading it, which
disables the whole suite.

**Shapeless tests.** No arrange/act/assert separation, or twelve assertions spread
across sixty lines so a failure does not localise. When it breaks in six months the
question is "what broke," and the test should answer it from the failure output
alone.

**Assertions that cannot fail.** `assert result is not None` after a function whose
signature guarantees a return; `assert len(x) >= 0`. Easy to write by accident and
completely inert.

## What not to flag

**Do not flag a minimal smoke test as insufficient when it is the only test.** Some
coverage is not a defect, and "this test is shallow" on the one test protecting a
module is a demoralising and useless finding. Flag the *missing failure-path test*,
which is actionable, rather than the presence of a simple happy-path one.

**Do not demand unit tests for code an integration test already pins down.** Ask
what is unconstrained, not what is unconventional.

**Do not report a coverage number as a finding.** It is a hook's job and it does not
answer the question this skill asks.

## Mutation testing

Where a mutation tool exists for the detected stack, recommend running it rather
than eyeballing — it answers the central heuristic mechanically instead of by
judgement:

| stack  | tool            |
| ------ | --------------- |
| Python | `mutmut`        |
| Rust   | `cargo-mutants` |
| Java   | `pitest`        |
| JS/TS  | Stryker         |

It is slow — it reruns the suite once per mutant — so scope it to changed files
rather than the repository. Name the tool and the scoping flag; a recommendation to
"consider mutation testing" without either is not actionable.

## Output

Findings by file, each naming the test, what it fails to constrain, and the
assertion or case that would fix it. Then one line on whether the change is
adequately tested.

"These tests are adequate" is an available answer. Say it when true.

## Worked example

**Reviewing:**

```python
def test_process_order(mocker):
    mock_repo = mocker.patch("service.order.repo")
    mock_repo.save.return_value = True
    result = process_order({"id": 1, "total": 500})
    assert result is not None
    assert mock_repo.save.called
```

> **`test_process_order` — does not constrain the implementation.**
>
> `process_order` could return `True`, `[]`, or the string "ok" and this passes;
> `assert result is not None` only excludes one of the values it will never return.
> `assert mock_repo.save.called` checks that *something* was saved, not what — the
> function could persist an order with a total of zero, the wrong id, or a
> `MagicMock`, and the test is satisfied. Replacing the entire body with
> `repo.save(None); return True` keeps it green.
>
> What to assert instead: the object handed to `save`. `mock_repo.save.assert_called_once_with(Order(id=1, total=500))`,
> or capture with `mock_repo.save.call_args` and assert on the fields. That is the
> behaviour the function exists for.
>
> **Missing failure paths.** Nothing covers `save` returning `False`, a total of `0`,
> a negative total, or a missing `id` key. Your contract says money is integer minor
> units — there is no test that a float total is rejected rather than silently
> truncated, and that invariant is exactly the kind that decays without one.
>
> **Not a finding:** mocking the repository here is correct. The problem is the
> assertions, not the mock.
>
> **Verdict:** one real test needed — assert on the persisted object — plus the
> zero/negative/float cases. `mutmut run --paths-to-mutate service/order.py` will
> confirm; expect the current test to kill almost no mutants.
