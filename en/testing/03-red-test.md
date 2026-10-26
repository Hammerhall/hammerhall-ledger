# The test went red: what to do

> "From Red to Green" · Article 3 · 30 min read
>
> **Who it's for.** You've read Articles 1–2 of this series. You have the
> `testy` sandbox and `DeadlineScoreTest` with four tests, and you've seen
> each of them red when you broke the code by hand. You don't need the
> "From Java to Spring Boot" series.
>
> **What's inside.** How to read a red report: the message, the stack
> trace, `Failures` and `Errors`, the report files. How to turn a bug into
> a red test, and why "it's green on my machine but red in the build"
> happens. What not to do with a red test, and when changing the test
> itself is the right call.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why learn to read red

A red X next to your pull request. Behind the Details link: a few
hundred lines of build log, with `BUILD FAILURE` at the bottom. The first
urges are easy to understand: hit Re-run and hope; tweak the test until
it passes; post "works on my machine" in the chat.

All three miss the point. A red test isn't an obstacle between you and the
merge: it's a message. Someone, at some point, wrote down: "this is how it
should be." Right now it isn't, and the test tells you exactly where and by
how much. Reading that message usually takes a few minutes, if you know
where to look.

That's what this article is about, in four parts:

1. a bug the tests don't see: first a red test, then the fix;
2. how to read a red report: in the IDE, in Maven, in the report files;
3. why a test is green on your machine and red in the build;
4. what not to do with a red test, when changing the test is right, and
   how to read someone else's failed test.

The example is the same: deadline scoring. Submitted before the deadline
or exactly on it: 100 points. Up to a day late: 50. Later than that: 0.

From [Article 2, "Your first unit test"](https://hammerhall.io/en/ledger/testing/2-first-test)
you have four tests: submitted a minute before the deadline, exactly on
it, an hour late, two days late. All green. The sandbox is the same as in
[Article 1, "Why tests, and what the project expects from you"](https://hammerhall.io/en/ledger/testing/1-why-tests).
As before, the short examples have no `import` lines: the full files are
at the end of the article.

---

## Part 1. A bug the four tests don't see

### The "simplification"

A teammate decided that comparing points in time was clunky and rewrote
the rule in terms of hours late:

```java
// src/main/java/example/testy/score/DeadlineScore.java — version after the "simplification"
public final class DeadlineScore {
    // … constants: as before

    public static int score(Instant deadline, Instant submittedAt) {
        // … null checks: as before
        long hoursLate = Duration.between(deadline, submittedAt).toHours();   // how many hours late
        if (hoursLate <= 0) {
            return FULL;
        }
        if (hoursLate <= GRACE.toHours()) {
            return HALF;
        }
        return NONE;
    }
}
```

`Duration.between(a, b)` is the span of time from `a` to `b`. If `b` comes
before `a`, the span is negative. `toHours()` is how many hours it holds.
It reads smoothly, almost like the rule itself.

The build is green: all four tests passed. The code gets merged.

### The complaint

A day later, an email arrives: "I submitted 20 minutes after the deadline
and got 100. Someone else was an hour late and got 50. Is that how it's
supposed to work?"

It isn't. The culprit is `toHours()`: it tells you how many **whole**
hours the span holds and throws away the rest. The Java documentation
says exactly that: the number of seconds is divided by 3600, dropping the
remainder. To your teammate's code, any lateness under an hour is 0 whole
hours, which means "not late."

And the tests said nothing. Here are their cases as your teammate's code
sees them, plus the case from the complaint:

| when submitted | `toHours()` | teammate's score | score by the rule |
|---|---|---|---|
| a minute before the deadline | 0 | 100 | 100 |
| exactly on the deadline | 0 | 100 | 100 |
| an hour late | 1 | 50 | 50 |
| two days late | 48 | 0 | 0 |
| 20 minutes late | 0 | 100 | 50 |

For the four test cases, the dropped remainder changes nothing, and the
scores are correct. The bug shows up only when someone is less than an
hour late, and the tests have no such case. Remember from Article 1:
a check finds a bug only if one of its cases is a case where the bug
shows.

💡 The same flaw exists at the other end. Someone a day and half an hour
late gets 50 from your teammate's code instead of zero: 24 whole hours is
"no more than 24." Which cases to pick so that this gets caught ahead of
time is coming up later in the series.

### First, a test that shows the complaint

Your first urge is to fix the code right away. Hold off. First, write the
complaint down as a test. It goes into `DeadlineScoreTest`, after the four
tests from Article 2:

```java
    @Test
    void twentyMinutesLateGetsHalf() {
        // complaint: "submitted 20 minutes late, got 100"
        Instant submittedAt = DEADLINE.plus(Duration.ofMinutes(20));

        int score = DeadlineScore.score(DEADLINE, submittedAt);

        assertThat(score).isEqualTo(50);
    }
```

You run it, and it's red:

```
expected: 50
 but was: 100
```

This is a good red. It proves you understood the complaint correctly: the
bug is reproduced. And it's reproduced by a program, not by a person with
a stopwatch. If the test had come out green, the bug wouldn't be where you
think it is, and it would be too early to fix anything.

### Then the fix

Now the code. Bring back the comparison of points in time, as it was
before the "simplification":

```java
        if (!submittedAt.isAfter(deadline)) {                   // exactly on the deadline is still on time
            return FULL;
        }
        if (!submittedAt.isAfter(deadline.plus(GRACE))) {       // exactly a day late is still half
            return HALF;
        }
        return NONE;
```

Run `DeadlineScoreTest`: all five tests are green. And you can trust this
green: a minute ago you saw the new test red on a real bug.

🔑 **Red test first, fix second.** The order is: complaint → red test →
fix → green. Fix first and write the test afterward, and it's green from
the start: there's no telling whether it catches anything.

### The test stays forever

After the fix, `twentyMinutesLateGetsHalf` doesn't get deleted. It's
protection against regression (Article 1): six months from now, someone
will want to "simplify" the rule again. Then this test will go red before
the code reaches people. A bug you've found has to become a test, or it
will come back.

In the pull request checklist from Article 1, this is the line "a fixed
bug has a test that is red without the fix." Now you can see why it's
there.

---

## Part 2. How to read a red report

### "Expected" and "but was"

In the IDE, a failed test is marked red, with the message and the stack
trace next to it (more on that below). In Maven, the same message appears
at the end of the log, in the results. It looks roughly like this:

```
[ERROR] Failures:
[ERROR]   DeadlineScoreTest.twentyMinutesLateGetsHalf:61
expected: 50
 but was: 100
```

Line numbers here and below refer to the files from "The full example."
The first line of each file there is a comment with the path or a label,
and it counts too.

Read it top to bottom: which test (`twentyMinutesLateGetsHalf` in the
`DeadlineScoreTest` class), on which line of the test file (61), and what
didn't match. `expected` is what the test says should come back. `but was`
is what the code actually returned.

The first question to ask a red test: **who's right, the expectation or
the code?** More often it's the test: it was written calmly and in
advance, while the code was just changed. But not always: that's Part 4.

### The stack trace: which line is yours

Below the message is the **stack trace**: the chain of method calls the
program followed to get to where the error happened. Each line is
a method, a file, and a line number. At the top is the place where the
error occurred. Below it is whoever called that.

```
org.opentest4j.AssertionFailedError:
expected: 50
 but was: 100
	at example.testy.score.DeadlineScoreTest.twentyMinutesLateGetsHalf(DeadlineScoreTest.java:61)
	…
```

`AssertionFailedError` means "the check didn't hold": AssertJ throws it
when `isEqualTo` doesn't match. The `at` line from your code is line 61 of
the test, that very `assertThat`. So the test got as far as the check, and
the check failed.

Sometimes the error happens before the check. Here's a test written the
way you shouldn't write one: it's here only so you can see a different
kind of red. Someone forgot to pass the deadline:

```java
// fragment: a test that never reached its check — Errors
class ErrorTest {

    @Test
    void forgotTheDeadline() {
        Instant submittedAt = Instant.parse("2026-10-12T21:00:00Z");

        int score = DeadlineScore.score(null, submittedAt);         // forgot to pass the deadline

        assertThat(score).isEqualTo(100);
    }
}
```

In the full file, with `package` and `import`, the `score(null, …)` call
is on line 16. The stack trace looks like this:

```
java.lang.IllegalArgumentException: Deadline is not set
	at example.testy.score.DeadlineScore.score(DeadlineScore.java:24)
	at example.testy.score.ErrorTest.forgotTheDeadline(ErrorTest.java:16)
	…
```

Read it like this:

* the first line is what happened: an `IllegalArgumentException` with the
  text "Deadline is not set"; the text is ours, from the `null` check in
  `DeadlineScore`;
* the first `at` line is **where** it was thrown: `DeadlineScore.java`,
  line 24;
* the second is **who called**: `ErrorTest.java`, line 16;
* after that come lines from Java itself and from JUnit, the ones that ran
  your test. Skip them. JUnit removes most of its own lines from the stack
  trace, so there aren't many.

The rule for searching: go top to bottom and stop at the first line from
your own package; in the sandbox, that's `example.testy.score`. In the
IDE, stack trace lines are links: click one, and the file opens at that
line.

### Failures and Errors in practice

Now you can see the difference between `Failures` and `Errors` from
Article 1 in practice. `twentyMinutesLateGetsHalf` reached `assertThat`,
and the check didn't hold. That's `Failures`: the code returned the wrong
thing, so compare what was expected with what came back.

`forgotTheDeadline` never reached the check: an exception was thrown on
the way. That's `Errors`: follow the stack trace to find where it came
from.

Here the test itself is wrong. No deadline means the error "Deadline is
not set": that's by design, it's part of the scoring rule. The test
should **expect** this error, not fall over because of it.

You write that with `assertThatThrownBy`, which comes later in the
series. You first meet it in
[Article 0, "What to know before Spring"](https://hammerhall.io/en/ledger/articles/0-before-spring)
of the "From Java to Spring Boot" cycle. As for `ErrorTest`, delete it once
you've tried it.

### Where the details live: target/surefire-reports

The build log is long, and the test messages in it are mixed in with
everything else. The report files are easier. Surefire, which runs the
tests in the `test` phase (Article 1), puts them in
`target/surefire-reports`, two per test class:

```
target/surefire-reports/
├── example.testy.score.DeadlineScoreTest.txt         ← summary and stack traces of failures
└── TEST-example.testy.score.DeadlineScoreTest.xml    ← everything in detail, for searching
```

`*.txt` is a summary for humans: how many tests ran, which ones failed,
and the stack trace of each failure. `TEST-*.xml` has the same and more,
in **XML** format: text with markup in angle brackets, one layout for
every class. It's the one to search, across all the reports at once.

Especially when the error is layered. If one exception was caused by
another, Java prints the chain. The outer one is at the top; below it is
a `Caused by:` line with its cause, and sometimes this goes several levels
deep. The real cause is usually in the very last `Caused by:`. When a test
fails not on a check but during setup, there can be five levels before
you get to it: for example, when the application didn't start.

Here's a recipe for collecting the causes from all the reports at once:

```bash
# -h: don't print file names; -o: only the matched part; |: pass the output on
grep -ho 'Caused by:[^<&]\{0,250\}' target/surefire-reports/TEST-*.xml | sort -u
```

**grep** is a program that searches files for lines matching a pattern.
Linux and macOS have it out of the box; on Windows, it comes with
Git Bash. Run it from the project folder, and the result appears right in
the terminal.

Here `grep` pulls the part after `Caused by:` out of every report. It
takes up to 250 characters, stopping at `<` or `&`, that is, at XML
markup. Then `sort -u` sorts the lines and keeps each cause once. Ten
failed tests with one cause give you one line. Without `-h`, each line
would start with a file name, and one cause from two different reports
would stay as two lines.

### Reports from the build machine

Remember from Article 1: on the team, the pull request check saves the
test reports even when the build fails. These are those reports.
Open Details next to the red X, go to the run summary (Summary), and
at the bottom, under Artifacts, download the archive with the reports.
Inside are the same `*.txt` and `TEST-*.xml` files, only from the build
machine instead of yours.

---

## Part 3. Green on your machine, red in the build

### Midnight in Moscow

Deadlines are announced in human terms: "by midnight, October 13." It's
tempting to write the test the same way: starting from a date instead of
a ready-made `Instant`. Here's how people write such a test the first
time, and how you shouldn't write it:

```java
// fragment: a test that is green on your machine and red in the build
class ZoneTest {

    @Test
    void halfAnHourAfterMidnightIsLate() {
        Instant deadline = LocalDate.of(2026, 10, 13)
                .atStartOfDay(ZoneId.systemDefault())               // ⚠️ midnight by the machine's clock
                .toInstant();
        Instant submittedAt = Instant.parse("2026-10-12T21:30:00Z"); // 00:30 Moscow time

        assertThat(DeadlineScore.score(deadline, submittedAt)).isEqualTo(50);
    }
    // …
}
```

`LocalDate` is a date with no time and no time zone: just "October 13."
`atStartOfDay(zone)` is the start of that day, midnight, in the given
**time zone**. `toInstant()` turns it into a point on the timeline. And
`ZoneId.systemDefault()` is the time zone of the machine the test runs
on.

Your laptop is in Moscow. Midnight in Moscow is 21:00 UTC: the `Z` at the
end of a timestamp means UTC (Article 1). The work was submitted at 21:30,
half an hour after the deadline. Score 50, the test is green.

In the pull request, it's red:

```
expected: 50
 but was: 100
```

The build that checks a pull request is called **CI** (continuous
integration). In Article 1, that was the check in GitHub Actions. It runs
on its own when a pull request is opened and whenever a new push lands on
its branch.

Build machines usually run on UTC. There, "midnight, October 13" comes
three hours later, at 00:00 UTC. A submission at 21:30 the evening before
lands two and a half hours before the deadline: full score. One test, one
piece of code, and the result depends on where you run it.

### How to reproduce it yourself

Java takes the machine's time zone from the `user.timezone` setting, and
you can set it at launch:

```
./mvnw test -Dtest=ZoneTest -DargLine=-Duser.timezone=UTC
```

`-Dtest=ZoneTest` runs only this class, as in Article 1. Surefire runs
the tests in a separate Java process, which is why there are two `-D`s
here.

The first, `-DargLine=…`, is a Maven property: "here are the settings for
that process." The second, `-Duser.timezone=UTC`, is the setting itself:
"act as if the machine runs on UTC." In the IDE, you put it in the test's
run configuration, in the VM options field. The test goes red on your
machine, just like in the build.

### The fix: name the time zone

The test itself got it wrong: "midnight in Moscow" is a rule of the task,
not a property of the machine. So you name the time zone:

```java
                .atStartOfDay(ZoneId.of("Europe/Moscow"))                   // time zone named explicitly
```

Now the test is green anywhere: in Moscow, on UTC, in New York. It went
into `DeadlineScoreTest` as `halfAnHourAfterMoscowMidnightIsLate`.

And to be fair: with your teammate's version from Part 1, this test is red
too. Half an hour late is still 0 whole hours there. Had this test been in
the project earlier, the "simplification" wouldn't have passed the build.

⚠️ A common mistake: `LocalDate.now()` and `ZoneId.systemDefault()` in
code where time matters, that is, the date and time zone "of this
machine." You've seen them in courses, and for a learning program they're
fine. In the real project, time in code is an `Instant`, and the clock is
shared, on UTC. In the sandbox, the deadline is an `Instant` too, and
where a time zone can't be avoided, it's named explicitly. Otherwise the
result depends on the machine, and a project has many machines: yours,
your teammate's, the build, the server.

### Other reasons for "it's green on my machine"

The time zone is one reason. Here are three more common ones, which
Article 1 mentioned:

* **A file isn't in the commit.** A new class or test file is on your
  machine but didn't make it into the push. Before pushing, run
  `git status`: is anything left uncommitted?
* **A stale `target`.** Your build folder may hold leftovers from earlier
  builds: a compiled class you've since renamed, an old settings file. The
  CI build starts with `clean`, from an empty `target`, and doesn't see
  them. Do the same on your machine: `./mvnw clean verify`.
* **Test order and shared state.** One test changes something shared and
  doesn't put it back: a static field, a Java setting, rows in the
  database. Another passes only if it runs earlier. On your machine you
  run one class; the build runs all of them, in its own order. More on the
  database later in the series.

There's one rule: **reproduce the build on your machine**, as closely as
you can. All the tests, with `clean`, and on UTC if you suspect the time
zone. Until you've reproduced it, you don't know the cause, you're only
guessing.

### Re-running isn't fixing

The temptation to hit Re-run is understandable: maybe you'll get lucky.
Sometimes you do. A test that's sometimes red and sometimes green on the
very same code is called **flaky**.

It's worse than a red test. The team gets used to the idea that "red just
happens sometimes" and stops looking. And the next red will be real.
Martin Fowler calls such tests an infection.

Re-running fixes nothing. The cause stays, whether it's the time zone, the
order, or the clock, and it will go off in someone else's pull request. If
it turned green after a re-run, you've found a flaky test. Mention it in
the pull request or tell a senior teammate.

---

## Part 4. What not to do, and when changing the test is right

### Three ways to hide red

Article 1 had a rule: don't hide red. Here's how people most often hide it
anyway. All three ways make the build green, and all three are bad.

* **Delete the test.** The promise it guarded disappears with it. A month
  later, nobody will remember there was one.
* **Disable it.** `@Disabled` is a JUnit marker meaning "don't run this."
  In Maven's summary line, such a test lands under `Skipped`. A disabled
  test looks like protection and protects nothing.
* **Adjust the expectation to fit.** The test expected 50, the code
  returned 100, so someone changes `50` to `100`. The test is green and
  now guards the bug: "twenty minutes late gets the full score" is written
  down as a rule. And whoever fixes the bug later gets a red test.

⚠️ A common piece of advice: "if a test is in the way, slap `@Disabled` on
it, we'll sort it out later." The JUnit documentation at least asks you to
give a reason: `@Disabled("…")`. The checklist from Article 1 is stricter:
you don't disable or delete someone else's test without an explanation in
the pull request.

### When changing the test is right

Sometimes the test is the one that's wrong. There's only one honest case:
the **promise** changed, meaning the rule itself, not the code. Say it was
decided that being up to 20 minutes late, inclusive, doesn't count,
because the site is sometimes slow. Then `twentyMinutesLateGetsHalf` will
start expecting 100 and get a new name: "gets half" is no longer true.
That's a legitimate change to the test.

Here's what such a change looks like:

* the rule and the tests change in one pull request, together with the
  code;
* the description says plainly which promise changed, why, and which
  tests were rewritten because of it;
* the reviewer can check this against the task or a written-down decision
  instead of taking your word for it.

If you can't name which promise changed, the test is most likely right
and the code is wrong. Then fix the code.

### A test rewritten with a reason

An example with submissions. A task can be submitted several times, and
the rule used to be: a new submission replaces the previous one. A test
guarded it: submitted on time, then resubmitted late, and the score is 50.
Then the rule was deliberately changed: the best submission counts,
because otherwise resubmitting could only cost you points. Deleting the
test is the easiest option, but then the trail is lost.

The right way is different. The assertion is turned around: now the score
is 100. And next to it, you write down what changed and why. If the old
property is still needed, for example "which submission is the latest,"
it becomes a separate operation with its own test.

A reversed decision is as much a part of the history as one that was
made. A test rewritten silently looks like a weakened check.

### Someone else's red test: read it first

Your change broke a test you didn't write. Here's the order: read its
name, its `@DisplayName`, its comments, and its body. Then answer for
yourself **what it guards**. Only after that decide who's wrong: the test
or your change.

### The test that stopped compiling

This is the story from Article 1 where someone else's test saved access
that people had paid for.

It happened during a rework: subscriptions were being moved from fields on
the user account into a separate table. The old subscription test, with
twenty-two checks, stopped even compiling: the methods it tested were
being removed. The temptation was obvious: delete it and write a new one.
The developer doing the rework read it first, and found two losses nobody
would have noticed: a broken promise and a lost way to test something.

The first was the subscription with no end date. The move only took
subscriptions that had a date. The ones with no end date would have
dropped out, and people would have lost access they'd paid for. Not
a single check would have gone red: there would simply have been fewer
rows.

The second was a way to test a boundary. "Now" was passed into the
calculation as a parameter, and the test's header, the comment above the
class, explained why. Otherwise there's no way to test the boundary
"expires exactly now" except by waiting. The new version took "now" from
the system clock. The tests would have stayed green; one edge case would
simply have become untestable.

Both findings came from one file, in an hour, and both were written in it
in plain words. A test that doesn't compile isn't garbage: it describes
what the system promised. And what couldn't be carried over wasn't
deleted silently: at the end of the new file there's a list of "what
wasn't carried over and where it lives now."

🔑 Before you delete or rewrite someone else's test, don't ask "what is
being checked here"; ask **"what promise is written down here."** The
first you can see from the method name; the second, from the comments and
the header. The promise is what survives any rework.

### Asking a language model: fine, but about what

A rule of the real project, from Article 1: a junior there asks a language
model only to **explain**, never to write things for them. A red test is
exactly the kind of legitimate question it's for. Give the model the test
code, the message, and the stack trace, and ask "what is being checked
here, and why did it fail?", not "fix it."

On the team, the pull request description has lines for this: "what
I asked the model and what I understood" and "what was unclear." In the
second one, people write things like: "didn't understand why the test
failed only in the build." That's a perfectly normal line, and the
reviewer will help.

### A red test: step by step

1. Read the message: what was expected, what came back.
2. Find the first line from your own package in the stack trace.
3. `Failures` or `Errors`: did the result not match, or did the test never
   reach the check?
4. If the test isn't yours, read which promise it guards.
5. Red only in the build? Reproduce it on your machine: all tests,
   `clean`, time zone.
6. Fix the code. Change the test only if the promise changed, and say so
   in the pull request.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. Why did your teammate's version with `toHours()` pass all four tests
   from Article 2 but fail the 20-minute test?
2. Why write a test that reproduces the complaint **before** the fix, not
   after?
3. The report says `expected: 50`, `but was: 100`. Which of these is
   written in the test, and which did the code return?
4. How do you use the stack trace to find the line where the error
   happened and the line in your test? Which lines do you skip?
5. How is `Failures` different from `Errors`, and what does that tell you
   about where to look?
6. A test with `ZoneId.systemDefault()` is green on your machine and red
   in the build. Why, and how do you get the same red on your machine?
7. What's wrong with `@Disabled` and with "changing the expectation to
   whatever came back"? When is changing a test the right thing to do?
8. Your change broke someone else's test. What question should you ask
   yourself before touching it?

---

## What's next

Your teammate's bug was caught by a complaint, but the build could have
caught it, if the tests had included a "20 minutes late" case. The next
article in the series is about which cases to test so that bugs like this
get caught ahead of time: boundaries, classes of inputs, and a table of
cases in one test.

## Sources

* [JUnit 6: Disabling Tests](https://docs.junit.org/6.0.3/writing-tests/disabling-tests.html):
  `@Disabled`; the documentation recommends giving a reason;
* [JUnit 6: Stack Trace Pruning](https://docs.junit.org/6.0.3/running-tests/stack-trace-pruning.html):
  why there are so few JUnit lines in the stack trace;
* [Maven Surefire Plugin](https://maven.apache.org/surefire/maven-surefire-plugin/):
  the `*.txt` and `*.xml` reports in `target/surefire-reports`;
* [Maven Surefire: the test goal](https://maven.apache.org/surefire/maven-surefire-plugin/test-mojo.html):
  the `test` and `argLine` parameters from this article;
* [Martin Fowler: Eradicating Non-Determinism in Tests](https://www.martinfowler.com/articles/nonDeterminism.html):
  why a flaky test is dangerous and where it comes from: order, time,
  shared state.

---

## The full example, with imports

The learning example lives in the `testy` sandbox from Article 1. There
are two files here. `DeadlineScore` after the fix is the same as in
Article 1: it's here so you can see line 24 and have something to restore
after the experiments. `DeadlineScoreTest` fully replaces the test from
Article 2, at the same path. Leave `ManualCheck` and
`TestyApplicationTests` alone.

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

```java
// src/test/java/example/testy/score/DeadlineScoreTest.java
package example.testy.score;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

import static org.assertj.core.api.Assertions.assertThat;

class DeadlineScoreTest {

    // midnight, October 13, Moscow time
    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Test
    void beforeDeadlineGetsFull() {
        Instant submittedAt = DEADLINE.minus(Duration.ofMinutes(1));

        int score = DeadlineScore.score(DEADLINE, submittedAt);

        assertThat(score).isEqualTo(100);
    }

    @Test
    void onDeadlineIsStillOnTime() {
        int score = DeadlineScore.score(DEADLINE, DEADLINE);

        assertThat(score).isEqualTo(100);
    }

    @Test
    void lateWithinDayGetsHalf() {
        Instant submittedAt = DEADLINE.plus(Duration.ofHours(1));

        int score = DeadlineScore.score(DEADLINE, submittedAt);

        assertThat(score).isEqualTo(50);
    }

    @Test
    @DisplayName("more than a day late — zero")
    void lateByMoreThanDayGetsNothing() {
        Instant submittedAt = DEADLINE.plus(Duration.ofDays(2));

        int score = DeadlineScore.score(DEADLINE, submittedAt);

        assertThat(score).isEqualTo(0);
    }

    @Test
    void twentyMinutesLateGetsHalf() {
        // complaint: "submitted 20 minutes late, got 100"
        Instant submittedAt = DEADLINE.plus(Duration.ofMinutes(20));

        int score = DeadlineScore.score(DEADLINE, submittedAt);

        assertThat(score).isEqualTo(50);
    }

    @Test
    void halfAnHourAfterMoscowMidnightIsLate() {
        Instant deadline = LocalDate.of(2026, 10, 13)
                .atStartOfDay(ZoneId.of("Europe/Moscow"))                   // time zone named explicitly
                .toInstant();
        Instant submittedAt = Instant.parse("2026-10-12T21:30:00Z");        // 00:30 Moscow time

        int score = DeadlineScore.score(deadline, submittedAt);

        assertThat(score).isEqualTo(50);
    }
}
```

Two files for experiments: this is not how tests are written. Put them in
the same folder, `src/test/java/example/testy/score/`, as `ErrorTest.java`
and `ZoneTest.java`, and delete them after the experiment. While they're
there, the results are different: there are more tests, `ErrorTest` is
always red, and `ZoneTest` is red on a machine that runs on UTC.

```java
// fragment: a test that never reached its check — Errors
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class ErrorTest {

    @Test
    void forgotTheDeadline() {
        Instant submittedAt = Instant.parse("2026-10-12T21:00:00Z");

        int score = DeadlineScore.score(null, submittedAt);         // forgot to pass the deadline

        assertThat(score).isEqualTo(100);
    }
}
```

```java
// fragment: a test that is green on your machine and red in the build
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

import static org.assertj.core.api.Assertions.assertThat;

class ZoneTest {

    @Test
    void halfAnHourAfterMidnightIsLate() {
        Instant deadline = LocalDate.of(2026, 10, 13)
                .atStartOfDay(ZoneId.systemDefault())               // ⚠️ midnight by the machine's clock
                .toInstant();
        Instant submittedAt = Instant.parse("2026-10-12T21:30:00Z"); // 00:30 Moscow time

        assertThat(DeadlineScore.score(deadline, submittedAt)).isEqualTo(50);
    }

    @Test
    void halfAnHourAfterMoscowMidnightIsLate() {
        Instant deadline = LocalDate.of(2026, 10, 13)
                .atStartOfDay(ZoneId.of("Europe/Moscow"))           // time zone named explicitly
                .toInstant();
        Instant submittedAt = Instant.parse("2026-10-12T21:30:00Z");

        assertThat(DeadlineScore.score(deadline, submittedAt)).isEqualTo(50);
    }
}
```

Try it yourself:

1. With the first two files in place, run `./mvnw test`: everything is
   green, `Tests run: 7`, that is, the six tests in `DeadlineScoreTest` and
   `TestyApplicationTests` from start.spring.io.
2. In `DeadlineScore`, replace the checks that come after the `null`
   checks with your teammate's version from Part 1. Run again: the four
   tests from Article 2 are green, while `twentyMinutesLateGetsHalf`
   (line 61) and `halfAnHourAfterMoscowMidnightIsLate` (line 73) are red,
   both with `expected: 50`, `but was: 100`. Put the code back.
3. Add `ErrorTest` and run: the result shows `Errors: 1`, not `Failures`.
   The stack trace has `DeadlineScore.java:24` and `ErrorTest.java:16`.
   Open `target/surefire-reports`: `*.txt` has the summary and this
   test's stack trace, `TEST-*.xml` has the same in more detail. The
   `grep` from Part 2 prints nothing here: this exception has no cause,
   so there's no `Caused by:`. Delete `ErrorTest`.
4. Add `ZoneTest` and run it with the Moscow time zone, and both tests are
   green:
   `./mvnw test -Dtest=ZoneTest -DargLine=-Duser.timezone=Europe/Moscow`.
   Now the same with `-Duser.timezone=UTC`: the first one is red,
   `expected: 50`, `but was: 100`, and the second is green. Delete
   `ZoneTest`.

Now you have six tests, and you've seen every one of them red. And a red
report reads like an address: which test, on which line, what was
expected, and what came back.
