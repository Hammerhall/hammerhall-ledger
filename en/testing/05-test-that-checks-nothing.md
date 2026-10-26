# A test that checks nothing

> "From Red to Green" · Article 5 · 30 min read
>
> **Who it's for.** You've read Articles 1–4 of this series: you have the
> `testy` sandbox, a table of cases for the deadline scoring rule, and the
> habit of breaking code by hand. You don't need the "From Java to Spring
> Boot" series.
>
> **What's inside.** What a test that can't go red looks like, and how to
> fix it; what JaCoCo coverage shows and what it keeps quiet about; how to
> test the test itself by breaking the code from a shared list of
> breakages.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why test your tests

[Article 1, "Why tests, and what the project expects from you"](https://hammerhall.io/en/ledger/testing/1-why-tests)
left a promise: a test that has never gone red may not check anything at
all. This article is about tests like that.

A test is a program too, and it can have bugs too. The difference is that
a bug in the code turns a test red, while a bug in a test usually turns
nothing red. A test like that stays green even when someone breaks the
code. From the outside it looks like protection, just like a test the
build never runs (Article 1).

The example is the same as before: deadline scoring, `DeadlineScore`, and
the final tests from
[Article 4, "Which cases to test"](https://hammerhall.io/en/ledger/testing/4-which-cases).
We'll write tests for it that check nothing and look at them through the
eyes of coverage. Then we'll break the code in five ways and see who
notices.

You already tried breaking code and watching what goes red in Articles 2
and 4. Today the technique gets a name, and the breakages come together
in the shared list that Article 4 promised.

---

## Part 1. Four ways to always be green

Here are four tests of `DeadlineScore` from the learning file `EmptyTest`.
All of them are green, and you shouldn't write tests like this; the whole
file is at the end of the article. `DEADLINE` is the same constant as in
Article 2: midnight, October 13, Moscow time. As always, the short
examples have no `import` lines.

### Called it, didn't check it

```java
    @Test
    void noAssertion() {
        DeadlineScore.score(DEADLINE, DEADLINE);                    // called it, and that's it
    }
```

The test calls the code and throws the result away. There's no assertion,
so there's nothing to fail. Whether `score` returns 100, 50, or minus
forty, the test is green. The only thing that can turn it red is an
exception thrown along the way.

The fix is an expectation written into the test itself, as a number, like
in Article 2:

```java
    @Test
    void onDeadlineIsStillOnTime() {
        int score = DeadlineScore.score(DEADLINE, DEADLINE);

        assertThat(score).isEqualTo(100);
    }
```

### Expected an exception, then swallowed it

```java
    @Test
    void swallowsException() {
        try {
            DeadlineScore.score(null, DEADLINE);
        } catch (IllegalArgumentException expected) {
            // expected an exception and quietly swallowed it; what if there isn't one?
        }
    }
```

The idea is right: without a deadline, `score` must throw an exception.
If it throws, `catch` catches it, and the test is green. If it doesn't,
`try` finishes quietly, and the test is green again. Both outcomes give
the same color. That means the test can't tell correct code from broken
code.

The fix is `assertThatThrownBy` from Article 4. It calls the code itself
through the lambda `() ->`, catches the exception itself, and **fails if
there was no exception**. It also checks the type and the message:

```java
    @Test
    void noDeadlineIsAnError() {
        assertThatThrownBy(() -> DeadlineScore.score(null, DEADLINE))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Deadline is not set");
    }
```

⚠️ In older examples you'll see another way: inside `try`, right after
the call, there's a `fail()` that fails the test, and the `catch` is
empty. If execution reached `fail()`, there was no exception. This works
as long as `fail()` is there. Forget that one line, and you've got
`swallowsException`. With `assertThatThrownBy`, there's nothing to forget.

### Checked the code against itself

```java
    @Test
    void agreesWithItself() {
        Instant hourLate = DEADLINE.plus(Duration.ofHours(1));

        assertThat(DeadlineScore.score(DEADLINE, hourLate))
                .isEqualTo(DeadlineScore.score(DEADLINE, hourLate));   // the code checks itself
    }
```

There is an assertion, but the expected value is computed by the same
code as the result. Whatever the code answers, it will agree with itself.

In real life this looks sneakier. The expected value comes from the same
constant (`DeadlineScore.HALF`), from the same helper method, or is
recomputed in the test with the same formula. That's why the expectation
in Article 2 became a number rather than a constant: make a mistake in
the constant, and a test that uses it will agree.

**Write expectations independently of the code**: from the rule, from the
task, by hand. For an hour late, the rule says "50", and the Article 2
test says exactly that: `assertThat(score).isEqualTo(50)`.

### Checked something that's always true

```java
    @Test
    void alwaysTrue() {
        assertThat(DeadlineScore.score(DEADLINE, DEADLINE)).isBetween(0, 100);   // true under any rule
    }
```

`isBetween(0, 100)` means "from 0 to 100 inclusive." The scoring rule has
three scores, 100, 50, and 0, and all of them lie between zero and one
hundred. Mix up a boundary, shift the one-day limit, give a late
submission the full score: the score will still be one of the three, and
the assertion will still hold.

"Not `null`" and "the list isn't empty" work the same way. If you know the
answer exactly, check it exactly: "submitted right on the deadline: 100".
That's the `PT0S | 100` row in the Article 4 table.

You can tell whether a test is empty without running it. Think of
a plausible mistake in the rule, one a teammate could make, and ask: will
the test go red? For all four, the answer is "no".

### A helper that agreed with what it was testing

A test that agrees with itself can hide in one convenient line. In the
real project, that happened with protection against forged requests. The
server gives the browser a secret token, and the browser attaches it to
every request that changes something.

In the tests, the token was supplied by a helper from a testing library,
one line per test. It took the token from the inside, from the same server
mechanism, and passed it exactly the way the mechanism expected. One day
the mechanism was only partly configured, and the server couldn't read the
token from a real browser. Sign-up from the browser didn't work. Yet 429
tests, the sign-up tests among them, were green: a person noticed by
sending a request by hand.

Worse, the helper replaced the mechanism for the whole run. A correct
test that took the browser's path went red in the full run. And the
temptation was to "fix" it with the same helper.

After that, the team made a rule. For every mechanism an external client
uses, at least one test takes the same path as the client, with no test
helpers. A helper saves lines, and that's exactly why it bypasses what
you're checking.

---

## Part 2. Coverage: where the tests have been

In the run summary, an empty test looks like any other: it's just as
green as the rest. You need a tool that looks inside.

### JaCoCo in the sandbox

**Coverage** is the share of code the tests executed (Article 1). It's
measured by **JaCoCo**, a Maven plugin, like Surefire. During the run, it
marks the lines that ran and the branches taken, that is, the paths of an
`if`: "yes" and "no". Think of a highlighter run over every line the
tests passed through: after the run, you can see where the tests went and
where they never did.

You'll hardly ever see JaCoCo in course projects, but at work people
rarely do without it. There are hundreds of tests, and nobody remembers
where each one goes. JaCoCo is covered in [Article 0, "What to know before Spring"](https://hammerhall.io/en/ledger/articles/0-before-spring)
of the "From Java to Spring Boot" cycle. Articles 1 and 4 promised to come
back to it in more detail, and here it is, from scratch.

You don't install it separately: a few lines in `pom.xml`, and Maven
downloads it itself. In the real project it's already set up. In the
sandbox we'll add it ourselves, next to the plugin Initializr put there:

```xml
<!-- testy sandbox pom.xml: what Article 5 adds, inside <build><plugins> -->
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>0.8.15</version>
    <executions>
        <execution>
            <goals>
                <goal>prepare-agent</goal>                  <!-- attach the counter to the test run -->
            </goals>
        </execution>
        <execution>
            <id>report</id>
            <phase>verify</phase>
            <goals>
                <goal>report</goal>                         <!-- report in target/site/jacoco -->
            </goals>
        </execution>
    </executions>
</plugin>
```

Each job of a plugin is an `<execution>` block. `<goal>` says what to do,
`<phase>` says at which build phase, and `<id>` is the block's name. There
are two jobs here.

`prepare-agent` runs at its default phase, before the tests. It attaches
an **agent** to the test run: a small program that Java loads along with
the tests. The agent is what holds the highlighter. `report`, at the
`verify` phase, builds a report from what was marked.

⚠️ Online you'll see examples with JaCoCo 0.8.8 or 0.8.11. Java 25 is
officially supported starting with JaCoCo 0.8.14, and older versions trip
over classes from newer JDKs. The sandbox uses 0.8.15, same as the real
project.

To run it: `./mvnw clean verify`. The report is the file
`target/site/jacoco/index.html`; open it in a browser.

⚠️ `clean` isn't here just for tidiness. JaCoCo **appends** the marks from
a new run to the old ones if they're still in `target`. Without `clean`,
the report also includes what the tests executed in earlier runs.

### How to read the report

The report is a set of nested pages: packages, the classes in a package,
the methods in a class, the source code. Every package and class has two
percentages in the table (`Cov.`). The first is for instructions: the tiny
steps Java breaks each line of code into. The second is for branches.
Lines are given as numbers: how many were missed (`Missed`) out of how
many (`Lines`).

Click the `example.testy.score` package, then `DeadlineScore`. Your code
opens, colored line by line:

* a **green** line ran completely;
* a **yellow** one ran partly: usually it's a condition where the tests
  took one path out of two;
* a **red** one never ran at all.

Lines with an `if` have a diamond of the same color on the left. Green
means the tests took both branches, yellow means one, red means none.

⚠️ Red in the report doesn't mean "the test failed". It means "the tests
never came here".

### A hundred percent without a single assertion

Here's the second learning file, `HollowTest`. Its test is written this
way on purpose. It goes into every branch of `score`: on time, half,
zero, no deadline, no submission time. And it checks nothing.

```java
class HollowTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Test
    void touchesEveryLine() {
        DeadlineScore.score(DEADLINE, DEADLINE);                            // "on time" branch
        DeadlineScore.score(DEADLINE, DEADLINE.plus(Duration.ofHours(1)));  // "half" branch
        DeadlineScore.score(DEADLINE, DEADLINE.plus(Duration.ofDays(2)));   // "zero" branch
        try {
            DeadlineScore.score(null, DEADLINE);                            // "no deadline" branch
        } catch (IllegalArgumentException ignored) {
        }
        try {
            DeadlineScore.score(DEADLINE, null);                            // "no submission time" branch
        } catch (IllegalArgumentException ignored) {
        }
    }
}
```

Run only this one: `./mvnw clean verify -Dtest=HollowTest`, where
`-Dtest` runs a single class (Article 1). In the report, `DeadlineScore`
has 100% of instructions and branches and not a single missed line out of
ten. Everything is green, and so are all the diamonds. The other classes
in the sandbox are red: this test didn't touch them.

Run the final tests from Article 4 the same way, `-Dtest=DeadlineScoreTest`.
You'll get the same picture: the report can't tell an empty test from an
honest one. But the four tests from Part 1 (`-Dtest=EmptyTest`) leave two
lines out of ten red, "no submission time" and "zero". The diamonds on two
conditions turn yellow: 75% of the branches are taken.

🔑 **Coverage tells you the code ran, not that it was checked.** JaCoCo
sees where the tests went and doesn't know what they checked there.

### 96% and a screen that lied

The browser side of the real project had a screen that told a person who
had solved ten tasks: "no tasks counted". The screen had more than two
hundred fifty green tests and 96% coverage.

The tests faked the server's responses, and those responses were made up
by the same person who wrote the screen. The screen lied on real data,
the kind the made-up responses didn't include: some tasks don't have the
information the screen needed at all. The screen took "no information"
to mean "nothing solved".

The lesson was written down like this: coverage measures how many lines
ran, not how many states the data can be in.

### An uncovered branch is a question

So is coverage useless? No. It's bad at answering "was this checked?" but
precise at answering "was this left unchecked?" A red line proves the
code was **not** checked: the test didn't run it, so it couldn't have
checked it.

Every red line and every yellow diamond is a question. It has two
possible answers:

* **a gap in the tests**: the case exists, but there's no test; write
  a test, with an assertion;
* **dead code**: no input can reach it; you can't write a test for it,
  so it gets removed.

### The report found the gap, not the run

Once, after a green run, a class at zero percent showed up in the team's
report. The endpoint that shows a person's roles was called by the tests
only for a person **without** roles. The code that turns roles into
a response never ran once. Swap two fields in the response, and none of
the 610 tests would have noticed.

The second answer happens too: what turns out to be uncovered is a
defensive check that no input can reach. In the report, dead code looks
like a forgotten case, but you can neither run it nor check it. It drags
the number down and protects nothing.

Hence a habit. After your change, don't look only at the percentage: one
class at zero among a hundred barely moves it. Look at the names: which
classes and branches stayed red.

### The threshold doesn't catch everything

On the team, JaCoCo has a third job, `check`. At the `verify` phase, it
takes the whole project and requires at least 80% of lines and 70% of
branches (Article 1). Below the threshold, `./mvnw verify` is red, and the
pull request doesn't get merged. New code for a task is covered
completely there.

The same rules state the main point of this article. Coverage isn't
proof: a test that doesn't check the result gives coverage and catches
nothing. That's why the reviewer looks at **what** the test checks.

If `DeadlineScore` were the whole project, the four empty tests would
pass the 80/70 threshold. Eight lines out of ten give exactly 0.80, and
75% of the branches are taken. `HollowTest` would even pass the
requirement for new code. The threshold catches code the tests never
reached. What they checked there is a question for you and the reviewer.

---

## Part 3. Break it by hand

### Mutants

There's one way to test a test: give it a reason to go red. In Articles 2
and 4 you did exactly that: broke the code with a single change and
watched what went red. A broken copy of the code has a name: a
**mutant**.

If a test goes red, the mutant is **killed**: the test notices that kind
of mistake. If everything stays green, the mutant **survived**, and
that's a question for the tests.

Here's the shared list promised in Article 4: five mutants of
`DeadlineScore`, each run against all the tests in the series. Where they
come from: M1 and M2 from Article 1, M3 from Article 2, M4 and M5 from
Article 4.

| mutant | what was broken | 4 "empty" | `HollowTest` | 4 tests from Article 2 | final tests from Article 4 |
|---|---|---|---|---|---|
| M1 | `!isAfter(deadline)` → `isBefore(deadline)`: submitting exactly on the deadline already counts as late | green | green | red `onDeadlineIsStillOnTime` | red row `PT0S` |
| M2 | `GRACE`: 24 hours → 23 | green | green | green | red row `PT24H` |
| M3 | in the second branch, `HALF` → `FULL`: late submissions get the full score | green | green | red `lateWithinDayGetsHalf` | red rows `PT0.000000001S`, `PT20M`, `PT1H`, `PT24H`, the midnight test, and `singleAttemptCountsAsIs` from `AttemptsTest` |
| M4 | no deadline: `return FULL` instead of an exception | green | green | green | red `noDeadlineIsAnError` |
| M5 | `!isAfter(deadline + one day)` → `isBefore(…)`: exactly one day late already gets zero | green | green | green | red row `PT24H` |

What the table shows:

* the empty tests and `HollowTest` didn't kill a single mutant;
* the four tests from Article 2 killed two: none of their cases sits on
  the one-day boundary (M2, M5) or has "no deadline" (M4);
* the final tests from Article 4 killed all five. They caught M3 with six
  checks at once: for a submission three hours late, `Attempts.best` also
  gives 100.

Coverage is the same for `HollowTest` and for the final tests. Mutants
tell them apart honestly: zero out of five and five out of five.

### How to break things

1. **One change at a time**, or you won't know which one got caught.
2. **Run the tests**: `./mvnw test`. The ones guarding the broken spot
   should go red.
3. **Undo the change** and make sure everything is green again. A mutant
   forgotten in a pull request is worse than any empty test.
4. **If a mutant survives, think.** If that kind of mistake is worth
   catching, a case is missing: add it and break the code again. If the
   change doesn't alter behavior, there's nothing to catch.

Where to break: at boundaries (`isAfter` ↔ `isBefore`, `>` ↔ `>=`), in
constants, in return values, where an exception is thrown. That's where
the mistakes tests miss like to hide.

That's how the idea from Article 1 becomes a working technique. Wrote a
test? Break the code it guards, see red, and undo.

💡 Breaking by hand takes time, and you'll have exactly as many mutants
as you can think of. **PIT** (pitest) does the same automatically: it
makes small changes to the code, runs the tests on each one, and counts
how many mutants were killed and how many survived. Its website says it
plainly: traditional coverage "measures only which code is executed by
your tests", while test quality shows in the share of killed mutants. In
the real project, adding it is a call for a mid-level developer, someone
with experience. It's enough for you to know that this is possible, and
you already know how to do it by hand.

### Negative and positive controls

A **negative control** means deliberately breaking what the test guards
and making sure it goes red. The technique goes by this name in
[Article 11, "Guard tests"](https://hammerhall.io/en/ledger/articles/11-guard-tests)
of the "From Spring to a System" cycle as well. Every mutant above is
a negative control.

A **positive control** is needed for checks the other way around, of the
form "X didn't happen": "access denied", "no error", "nothing changed".
Such a check is true even when the mechanism doesn't work at all. A
counter that's switched off also "didn't go up". So next to it you put
proof that X **can** happen: the same path where X is allowed, and the
same check sees it.

### "Didn't happen" is true even when it's broken

On the team, this is a written rule: next to every "X didn't happen"
there must be proof that X can happen at all.

They're strictest about permissions. A "denied" response is true even if
the operation already went through and the denial came after it. So to
every "access denied" they add "and nothing happened": access is
unchanged, zero entries in the audit log. Otherwise access granted
quietly can't be seen by anything.

---

## Part 4. Check the outcome

The empty tests from Part 1 don't ask a question that can have a wrong
answer. One doesn't look at the result at all; the others compare it to
an expectation that's always true. The right question for a test is
about the **outcome**. What must become true if the code worked, and what
won't be there if it's broken? Here's what that question looks like in
code.

### "Checked by the outcome"

Take a list check in Java. A method goes through a group's submissions,
compares each one's score to the rule, and counts: the checked ones go
into `checked`, and the failed ones, where the score didn't match, into
`failed`. The verdict is "all good" if `failed == 0`.

Why isn't that enough? "Zero failed" is also true when there are no
submissions at all: an empty list has zero failures too. The list may not
have loaded, or the wrong one may have loaded, and the check is still
green. So the condition is written like this: more than zero checked
**and** zero failed, `checked > 0 && failed == 0`. The first half is the
positive control from Part 3, in one line.

A similar trap is trusting an "I'm healthy" answer. A loading method that
returned `true` only tells you about itself: it ran without errors.
Whether the list has even one submission, that answer won't say. So you
check not the answer but the outcome: the submissions are there, and each
one's score follows the rule.

The same goes for Part 1. `noAssertion` is like an "I'm healthy" answer:
the code was called and didn't fail. A test with an exact expectation
checks the outcome: submitted right on the deadline, 100.

### A green test and a rate of zero

Picture a screen that shows a rate: how many people out of all
applications made it to sign-up. By this article's standards, the test
of the calculation is a good one. The expectation is written as a number,
and both branches of the condition, "there are applications" and "there
are none", are covered by two tests in the class.

The test's question is this: if the repository says 3 out of 10 made it,
do we get 30.0? That's arithmetic, and it's right. The test is green, and
on the real screen the rate is zero.

The business question is different: what share of people actually made
it? To answer it, someone has to set the final status on an application.
You can't set it by hand, and that's by design: this status is set by
the system. And the code that would set it was never written.

The test can't notice that. It made up "made it: 3" itself: instead of
the real repository, it plugged in a **stub**, an object with a ready-made
answer. More on stubs later in the series. An integration test of the
same screen, with a real database, can't notice it either: it puts an
application into the database already in the right status, bypassing the
code.

In real life, that state only appears after other code has done its
work; the test planted it by hand. The lesson is the same as with the screen
from Part 2. And so is the rule from Article 1: a green test answers
exactly the question it was asked. A test asking the business question
would have been red from day one: "a person made it to sign-up; did they
get counted in the rate?"

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. `swallowsException` and `noDeadlineIsAnError` expect the same
   exception. Why is the first one green even when the code is broken,
   and the second one isn't?
2. Why can't a test take its expected value from the same constant, or
   compute it with the same formula, as the code?
3. Without running a test, how can you tell it won't notice a mistake?
   What question should you ask yourself?
4. `HollowTest` goes through every line and branch of `DeadlineScore`.
   What does that prove, and what doesn't it prove?
5. There's a red line in the JaCoCo report. What two answers can this
   question have, and what do you do in each case?
6. What is a mutant? Why did M2 survive the four tests from Article 2
   but not the final tests from Article 4?
7. How is a positive control different from a negative one? Why does a
   "denied" check need a positive one?
8. What does "checked by the outcome" mean? Why didn't the rate test from
   Part 4, good by every measure in this article, notice the zero on the
   screen?

---

## What's next

The next article in the series is about what happens when your code is
surrounded by other code: a database, the network, the clock, someone
else's service. Stubs by hand and Mockito, and how not to use a stub to
write the same test that agrees with itself.

## Sources

* [JaCoCo: Coverage Counters](https://www.jacoco.org/jacoco/trunk/doc/counters.html):
  what counts as a line and a branch, what the colors and diamonds mean;
* [JaCoCo: Maven Plug-in](https://www.jacoco.org/jacoco/trunk/doc/maven.html):
  the plugin's jobs (goals): `prepare-agent`, `report`, `check`; each one
  has its own page with settings;
* [JaCoCo: check](https://www.jacoco.org/jacoco/trunk/doc/check-mojo.html):
  how threshold rules are set: element, counter, ratio, minimum;
* [PIT: Real world mutation testing](https://pitest.org/): mutation
  testing, killed and surviving mutants; start with Quick Start.

---

## The full example, with imports

The learning example lives in the `testy` sandbox from Article 1. By this
article, it has everything from Articles 1–4: `DeadlineScore` and
`Attempts`, plus the final `DeadlineScoreTest` and `AttemptsTest`. There
are no new dependencies; only the JaCoCo plugin is added to `pom.xml`,
inside `<build><plugins>`:

```xml
<!-- testy sandbox pom.xml: what Article 5 adds, inside <build><plugins> -->
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>0.8.15</version>
    <executions>
        <execution>
            <goals>
                <goal>prepare-agent</goal>                  <!-- attach the counter to the test run -->
            </goals>
        </execution>
        <execution>
            <id>report</id>
            <phase>verify</phase>
            <goals>
                <goal>report</goal>                         <!-- report in target/site/jacoco -->
            </goals>
        </execution>
    </executions>
</plugin>
```

`DeadlineScore` is the same as in Article 1: it's here so you have
something to restore after breaking things. Don't touch the other files
in the sandbox.

```java
// src/main/java/example/testy/score/DeadlineScore.java
package example.testy.score;

import java.time.Duration;
import java.time.Instant;

/**
 * Deadline scoring: how many points a task gets, depending on when it was submitted.
 * A learning rule from the "From Red to Green" series.
 */
public final class DeadlineScore {

    public static final int FULL = 100;                         // on time
    public static final int HALF = 50;                          // late, but by no more than a day
    public static final int NONE = 0;                           // later than that

    static final Duration GRACE = Duration.ofHours(24);         // how late you can be and still get half

    private DeadlineScore() {                                   // no objects needed: just the method
    }

    public static int score(Instant deadline, Instant submittedAt) {
        if (deadline == null) {
            throw new IllegalArgumentException("Deadline is not set");
        }
        if (submittedAt == null) {
            throw new IllegalArgumentException("Submission time is not set");
        }
        if (!submittedAt.isAfter(deadline)) {                   // exactly on the deadline is still on time
            return FULL;
        }
        if (!submittedAt.isAfter(deadline.plus(GRACE))) {       // exactly a day late is still half
            return HALF;
        }
        return NONE;
    }
}
```

The two files for experiments are for learning only: tests aren't written
this way, and their first lines say so. Put them in the
`src/test/java/example/testy/score/` folder as `EmptyTest.java` and
`HollowTest.java`, and delete them after the experiments.

```java
// fragment, for learning: DON'T write tests like this — four tests, green whatever breaks
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class EmptyTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Test
    void noAssertion() {
        DeadlineScore.score(DEADLINE, DEADLINE);                    // called it, and that's it
    }

    @Test
    void swallowsException() {
        try {
            DeadlineScore.score(null, DEADLINE);
        } catch (IllegalArgumentException expected) {
            // expected an exception and quietly swallowed it; what if there isn't one?
        }
    }

    @Test
    void agreesWithItself() {
        Instant hourLate = DEADLINE.plus(Duration.ofHours(1));

        assertThat(DeadlineScore.score(DEADLINE, hourLate))
                .isEqualTo(DeadlineScore.score(DEADLINE, hourLate));   // the code checks itself
    }

    @Test
    void alwaysTrue() {
        assertThat(DeadlineScore.score(DEADLINE, DEADLINE)).isBetween(0, 100);   // true under any rule
    }
}
```

```java
// fragment, for learning: DON'T write tests like this — 100% coverage and not a single check
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

class HollowTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Test
    void touchesEveryLine() {
        DeadlineScore.score(DEADLINE, DEADLINE);                            // "on time" branch
        DeadlineScore.score(DEADLINE, DEADLINE.plus(Duration.ofHours(1)));  // "half" branch
        DeadlineScore.score(DEADLINE, DEADLINE.plus(Duration.ofDays(2)));   // "zero" branch
        try {
            DeadlineScore.score(null, DEADLINE);                            // "no deadline" branch
        } catch (IllegalArgumentException ignored) {
        }
        try {
            DeadlineScore.score(DEADLINE, null);                            // "no submission time" branch
        } catch (IllegalArgumentException ignored) {
        }
    }
}
```

Try it yourself:

1. Add the plugin to `pom.xml` and run `./mvnw clean verify`:
   `Tests run: 18`, everything green. Open `target/site/jacoco/index.html`,
   the `example.testy.score` package, the `DeadlineScore` class: 100% of
   instructions and branches, 0 missed lines out of 10.
2. Add both learning files and run `./mvnw clean verify` again:
   `Tests run: 23`, everything green. Empty tests don't break the build.
3. `./mvnw clean verify -Dtest=HollowTest` gives `Tests run: 1`, and
   `-Dtest=DeadlineScoreTest` gives `Tests run: 12`. In both reports,
   `DeadlineScore` shows the same as in step 1.
4. `./mvnw clean verify -Dtest=EmptyTest` gives `Tests run: 4`: 2 lines
   out of 10 missed, 75% of the branches taken. Find the two red lines
   and the two yellow diamonds.
5. Now without `clean`: `./mvnw verify -Dtest=HollowTest`, and after it
   `./mvnw verify -Dtest=EmptyTest` again. `DeadlineScore` has 0 missed
   lines again: the report added the runs together. That's what `clean`
   is for.
6. The mutants from Part 3, one at a time: change, `./mvnw test`, compare
   with the table, undo. `EmptyTest` and `HollowTest` are green on every
   one. You can't check the Article 2 column this way: those four tests
   aren't in the sandbox anymore; they became rows of the Article 4
   table.
7. Delete `EmptyTest` and `HollowTest`: tests like these don't belong even
   in a sandbox. `./mvnw test` gives `Tests run: 18` again. Keep the
   JaCoCo plugin.

Now you know the difference between a green test and a checked one. The
first has simply never gone red; the second goes red on every breakage it
guards against.
