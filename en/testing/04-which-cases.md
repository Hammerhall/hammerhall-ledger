# Which cases to test

> "From Red to Green" · Article 4 · 30 min read
>
> **Who it's for.** You've read Articles 1–3 of this series: you have the
> `testy` sandbox and six tests for the deadline scoring rule. You know
> how to write a test; the question is which ones. You don't need the
> "From Java to Spring Boot" series.
>
> **What's inside.** How to find input classes and boundaries, both in
> your own code and in the task's table; how to write the cases down as
> a table and turn it into a single parameterized test; how to test
> errors, an empty list, and `null`.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why choose cases

In [Article 3, "The test went red: what to do"](https://hammerhall.io/en/ledger/testing/3-red-test),
four green tests missed a bug that a real person complained about. The
tests didn't lie: each one checked its own case, and in each of those
cases the code was right. The bug lived where no test ever looked: in
the first hour after the deadline.

You can't test every input. A day after the deadline has 86,400 seconds,
and `Instant` tells apart a billion points inside each second. Testing
at random means hoping you get lucky.

Article 1 already said it: a check finds a bug only if one of its cases
is a case where the bug shows. So you pick cases where a bug is most
likely. There are two simple techniques for that: input classes and
boundaries. Then we'll break the code and check our choice.

The example is the same deadline scoring rule:

| when submitted | score |
|---|---|
| before the deadline or exactly on it | 100 |
| later, but no more than a day late | 50 |
| later than that | 0 |
| no deadline or no submission time | an error with a clear message |

A small class, `Attempts`, joins it: a task can be submitted several
times, and the best submission counts. The sandbox is the same `testy`
as in [Article 1, "Why tests, and what the project expects from you"](https://hammerhall.io/en/ledger/testing/1-why-tests).
Short examples leave out the `import` lines: the full files are at the
end of the article.

---

## Part 1. Classes and boundaries

### The happy path and the unhappy one

The **happy path** is the case where everything goes as planned: you
submitted on time and got 100. The **unhappy path** is everything else:
you were late, there's no deadline, something odd came in.

The happy path comes to mind first: you just wrote it and checked it.
But a rule exists mostly for the unhappy ones. The line "not after
the deadline" isn't there for someone who submitted early; it's there
for someone who was a minute late. A test of the happy path alone checks
the part of the code where it's hardest to make a mistake.

The four tests from Article 2 do have late submissions, but not a single
"no deadline" case. We'll see what that costs us in Part 3.

### Scenarios green, rules unchecked

One real project had a module where every scenario, that is, every
action a person takes from start to finish, was covered by a test. All
the tests were green, but a coverage measurement showed 58% of
branches, the paths through `if` (Article 1). The gaps were in rules
like "repeating the same action is harmless, but changing a recorded
result isn't allowed." Not one of them was checked by a test.

A scenario proves that the happy path works. A rule exists so that the
unhappy one does **not** work, and it has to be checked separately: not
"you can," but "you can't." Every "you can't" in the code is an `if`,
and the tests had never once gone down its "you can't" branch.

On the team, the endpoint that changes a record's status has seven
tests: two happy paths and five unhappy ones. The unhappy ones are a
request without logging in, a record that doesn't exist, an empty
request, an unknown status, and a status that can't be set by hand.

### Input classes

`DeadlineScore` has infinitely many inputs, but the code does only a
few different things with them. An **input class** is a group of inputs
the code treats the same way; in books, it's called an equivalence
class. If the code is right for one input from a class, it's almost
certainly right for the rest, and one or two representatives of each
class are enough. You don't make classes up; you read them out of the
rule:

| class | example | score |
|---|---|---|
| before the deadline | 30 days early | 100 |
| exactly on the deadline | to the second | 100 |
| within a day | an hour late | 50 |
| more than a day late | two days late | 0 |
| missing data | the deadline is `null` | an error |

"Exactly on the deadline" is a class with a single point. The rule names
it separately, "before the deadline **or exactly** on it," so it gets
tested separately too. The fifth class is the unhappy path that's
easiest to forget: it has no score at all.

The rule is simple: **at least one case from every class**. The tests
from Article 2 covered four classes out of five.

### Boundaries are the most dangerous points

The place where one class turns into another is a **boundary**. We have
two: the deadline itself, and the deadline plus a day.

This is exactly where mistakes happen most often. `<` instead of `<=`,
`isBefore` instead of `!isAfter`, 23 instead of 24: that's an
**off-by-one error**. Code with one is right everywhere except at the
boundary itself or in a narrow strip next to it. The `isBefore` change
from Article 1 changed the score at exactly one point, the deadline
itself. Tests for "a minute early" and "an hour late" will never see
mistakes like that: they're far from the boundaries.

🔑 **Bugs live on boundaries.** Each boundary is tested from both sides:
the last point of one class and the first point of the next. For the
deadline, that's "exactly on the deadline" (100) and "right after" (50).
For the day, it's "exactly a day late" (50) and "right after" (0).

### What "right after" means

With integers, 91 comes after 90. But what comes right after the
deadline?

`Instant` stores time down to the **nanosecond**, a billionth of
a second. So the first point of the "late" class is the deadline plus
one nanosecond. In the table we'll write shortly, that's
`PT0.000000001S`. The first point of the "more than a day late" class
is `PT24H0.000000001S`.

⚠️ A common mistake is to take "plus or minus one" at a boundary out of
habit: a second, or a day. For `Instant`, the unit is a nanosecond, and
a row for "a second late" isn't the edge here. If someone starts
comparing times with the fractions of a second dropped, a submission half
a second after the deadline will get 100. And the "a second late" test
will stay green.

### Two points at a boundary

The real project has a setting, a window in days from 1 to 90. It's
guarded by a settings test from the table in Article 1: with a wrong
setting, the application doesn't start.

The test takes the upper boundary with two points: with 90, the
application starts and the window is 90; with 91, it doesn't start.
That's the last valid point and the first invalid one. The values 50 and
200 would also land on different sides, but they wouldn't tell you where
exactly the boundary is.

---

## Part 2. From a table of cases to code

### An "input → result" table

Before writing tests, write the cases down as a table: the input on the
left, the result on the right. Here it's easier to give the input not as
a submission time but as **lateness**: how much later than the deadline
the task was submitted. Negative lateness means it was submitted early.

| lateness | result | where the row comes from |
|---|---|---|
| −30 days | 100 | "early," far from the boundary |
| −1 second | 100 | "early," at the boundary |
| 0 | 100 | "exactly on the deadline": the boundary |
| +1 nanosecond | 50 | right after the deadline |
| +20 minutes | 50 | the complaint from Article 3 |
| +1 hour | 50 | "within a day" |
| +24 hours | 50 | exactly a day late: the boundary |
| +24 hours and 1 nanosecond | 0 | right after the day |
| +2 days | 0 | "more than a day late" |
| no deadline | the error "Deadline is not set" | the unhappy path |
| no submission time | the error "Submission time is not set" | the unhappy path |

A reviewer reads a table like this in half a minute and sees what's
missing from it. The tests from Articles 2 and 3 became rows in it,
except for the midnight test; more on that below. "A minute before the
deadline" became "a second before": the boundary itself lies between
zero and one nanosecond, and a second before the deadline is simply
"early," close to it.

### A parameterized test

Nine rows means nine nearly identical methods? On a project, twin
methods drift apart: someone fixes the expectation in one and forgets
the one next to it. A loop inside a single test is no better: it fails
on the first bad row and says nothing about the rest (Article 2).

A **parameterized test** is a test that JUnit runs once for each row of
data. It's the JUnit module `junit-jupiter-params`, and you don't need
to add it: `spring-boot-starter-test` brings in all of `junit-jupiter`,
with api, params, and engine. It runs like any test, and in the report
each row is a separate run. If one fails, you can see which.

You first met tests like this in
[Article 0, "What to know before Spring"](https://hammerhall.io/en/ledger/articles/0-before-spring)
of the "From Java to Spring Boot" cycle. Here we'll go through them from scratch.

```java
    @ParameterizedTest(name = "late by {0} → {1}")
    @CsvSource(delimiter = '|', textBlock = """
            -P30D              | 100
            -PT1S              | 100
            PT0S               | 100
            PT0.000000001S     | 50
            # complaint from Article 3: submitted 20 minutes late, got 100
            PT20M              | 50
            PT1H               | 50
            PT24H              | 50
            PT24H0.000000001S  | 0
            P2D                | 0
            """)
    void scoreByLateness(Duration lateness, int expected) {
        int score = DeadlineScore.score(DEADLINE, DEADLINE.plus(lateness));

        assertThat(score).isEqualTo(expected);
    }
```

How to read it:

* `@ParameterizedTest` instead of `@Test`: "run this once for each row."
  The rows come from a **source**, the next annotation.
* `@CsvSource` is a table source. CSV is a "values separated by
  a delimiter" format; each row is one run.
* `"""` … `"""` is a **text block**: a Java string that spans several
  lines. Java strips the common indentation on the left by itself.
* `delimiter = '|'` is the column separator. The default is a comma,
  but a bar reads like a table. JUnit trims the spaces around values.
* The method now has parameters. In Article 2 the tests didn't need any,
  but here JUnit fills them in: the first column goes into `lateness`,
  the second into `expected`.
* `-P30D`, `PT20M`, `P2D` are time spans in ISO-8601 format: minus
  30 days, 20 minutes, 2 days. More on that below.
* `DEADLINE.plus(lateness)` is the deadline plus the lateness. `DEADLINE`
  is the constant from Article 2.

### The complaint row with a comment

A line that starts with `#` is a comment, and JUnit skips it. This only
works in `textBlock`. The `twentyMinutesLateGetsHalf` test from Article 3
became the row `PT20M`, but its story stayed next to it. If someone
wants to "clean up" the table by removing an odd-looking row, the
comment tells them: this is the memory of a real bug.

⚠️ A hash is a comment only if it's **first** on the line, with no
spaces before it. The closing `"""` also counts when Java works out the
common indentation. Move it further left than the table rows, and every
row keeps some spaces on the left: the comment becomes a data row. JUnit
will try to turn it into a `Duration` and fail that run: `Failed to convert
String "# complaint from Article 3: …" to type java.time.Duration`. Keep `"""`
at the same indentation as the table.

### A Duration from text

How does the text `PT20M` become a `Duration`? JUnit does it on its own:
an **implicit conversion**. The parameter is declared as a `Duration`,
a string arrives, so JUnit calls `Duration.parse`. In the same way, `"50"`
becomes an `int`.

`Duration.parse` reads the **ISO-8601** format, an international
standard for writing dates and time spans:

* `P` starts the span and is always there;
* `D` is days; a day here is exactly 24 hours;
* `T` means hours, minutes, and seconds follow;
* `H`, `M`, `S` are hours, minutes, seconds; seconds can have a fraction,
  up to nine digits after the point;
* a minus before `P` makes the whole span negative. The sign is a Java
  addition; the standard itself doesn't have it.

`-PT1S` is minus one second, that is, one second before the deadline.
`PT0S` is zero. `PT24H0.000000001S` is 24 hours and 0.000000001 seconds:
a day and one nanosecond. Nine digits after the point are exactly
nanoseconds, and `Duration.parse` won't accept a tenth.

A typo like `PT20` with no unit won't give you a green test. The run
fails with `Failed to convert String "PT20" to type java.time.Duration`.

### The name of each run

`name = "late by {0} → {1}"` is how each run is labeled: the first
argument takes the place of `{0}`, the second the place of `{1}`. In the
IDE, there will be nine lines under `scoreByLateness`, roughly like this:

```
late by "-P30D" → "100"
late by "PT0.000000001S" → "50"
late by "PT24H0.000000001S" → "0"
```

⚠️ Online, you'll see names like these without quotes:
`late by PT20M → 50`. That's how it was before JUnit 6. The sandbox has
JUnit 6, and it puts text arguments in quotes.

And from `@CsvSource`, every argument arrives as text: the name is put
together **before** the conversion to `Duration` and `int`. That's why
both the lateness and the number get quotes: `late by "PT20M" → "50"`.
This isn't a bug. You can turn the quotes off with the setting
`quoteTextArguments = false`, but there's no reason to.

### The unhappy path: an exception with a type and a message

Two rows of the table are left where we expect an error, not a score.
One of them is the "no deadline" case that Article 2 put off for later.
In Article 3, `ErrorTest` failed on it with `Errors`, but a test should
**expect** an error like that:

```java
    @Test
    void noDeadlineIsAnError() {
        assertThatThrownBy(() -> DeadlineScore.score(null, DEADLINE))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Deadline is not set");
    }
```

Read it like this: "I assert that this piece of code throws an exception
of type `IllegalArgumentException` with exactly the message 'Deadline
is not set'." `IllegalArgumentException.class` is how you name the
class of the exception you expect.

`() -> DeadlineScore.score(null, DEADLINE)` is a **lambda**: a bit of
code that's passed around as a value without being run right away. The
parameters are to the left of the arrow, what to do is to the right;
there are no parameters here. Call `score(null, …)` directly, and the
exception flies out before the check. A lambda, though, is called by
AssertJ itself: it catches the exception and checks it. If there's no
exception, the test is red: `Expecting code to raise a throwable.`

Why the type alone isn't enough. `DeadlineScore` has two `null` checks,
and both throw `IllegalArgumentException`: only the message tells them
apart. If someone mixes up the messages, a test that checks "only the
type" stays green.

Besides, the message is part of the rule: "an error **with a clear
message**." It was promised, so we check it. `hasMessage` compares the
whole message, and if only one word matters, there's
`hasMessageContaining`, "contains."

```java
    @ParameterizedTest
    @NullSource
    void noSubmissionTimeIsAnError(Instant submittedAt) {
        assertThatThrownBy(() -> DeadlineScore.score(DEADLINE, submittedAt))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Submission time is not set");
    }
```

**`@NullSource`** is a source with a single value, `null`: the test runs
once, with `submittedAt = null`. For a single `null`, `@Test` would have
been enough; it's here so you see both ways. The source is useful when
there are several invalid values: you put it next to another source, and
`null` is added to its rows. It doesn't work for a parameter of
a primitive type, `int` or `long`.

The `halfAnHourAfterMoscowMidnightIsLate` test from Article 3 stays
a separate method. It has a different deadline: midnight in Moscow, built
from a date and a time zone. The table only changes the lateness from
a single `DEADLINE`. In total, `DeadlineScoreTest` has four methods and
twelve runs.

---

## Part 3. The proof: let's break the code

The table is longer than four tests. But does it catch more? Let's break
the code, as in Article 1, and see what goes red. The break numbers
come from a shared list. The next article shows it in full, with M3.

Break M2: a day became 23 hours. This is the very gap from Article 2:

```java
    static final Duration GRACE = Duration.ofHours(23);         // how late you can be and still get half
```

Break M5: at the second boundary, "not after" became "before."
The comment is left over from the correct code and now lies:

```java
        if (submittedAt.isBefore(deadline.plus(GRACE))) {       // exactly a day late is still half
```

Break M4: there's no deadline, and instead of an error, the score is 100.

```java
        if (deadline == null) {
            return FULL;
        }
```

| break | the 4 tests from Article 2 | the tests from Article 4 |
|---|---|---|
| M1: `isBefore` at the deadline, from Article 1 | `onDeadlineIsStillOnTime` red | row `PT0S` red |
| M2: a day became 23 hours | all green | row `PT24H` red: `expected: 50`, `but was: 0` |
| M5: `isBefore` at the second boundary | all green | row `PT24H` red: `expected: 50`, `but was: 0` |
| M4: no deadline, yet the score is 100 | all green | `noDeadlineIsAnError` red |
| your teammate's "simplification" from Article 3 | all green | rows `PT0.000000001S`, `PT20M`, `PT24H0.000000001S` and the midnight test red |

The six tests from Article 3 are also green under M2, M4, and M5. Let's
see why.

**M2.** The "an hour late" and "two days late" tests are far from the
boundary, and the bug lives between hour 23 and hour 24, where there's
no test. The `PT24H` row sits right there.

**M5.** The code is wrong at a single point, exactly a day late. It's
the `isBefore` break from Article 1, only at the second boundary.
Only a row "exactly on the boundary" can catch it. Two different
breaks, M2 and M5, were caught by one row.

**M4.** The tests from Article 2 had no "missing data" class, so there
was nothing to catch it with. A forgotten class is a whole unchecked
piece of the rule.

**Your teammate's bug.** The tests from Article 3 caught it at 20
minutes. Its second face was in the 💡 of Article 3: for `toHours()`,
a day and some minutes is still "24 hours," and the submitter gets 50
instead of 0. Now that's the row `PT24H0.000000001S`. The `PT1H` row,
though, is green with this bug: an hour late, both the correct and the
broken code give 50.

We've seen the rows on both boundaries and the "no deadline" test go
red, each on its own break. So their green can be trusted (Article 1).
It's not about the number of rows: a hundred
"an hour late" tests wouldn't catch a single one of these breaks.

---

## Part 4. Lists, emptiness, and the task's table

### Zero, one, many

Here's the promised `Attempts`, the best of several submissions:

```java
    /** The best score across all submissions; never submitted means zero. */
    public static int best(Instant deadline, List<Instant> submissions) {
        if (submissions == null) {
            throw new IllegalArgumentException("The list of submissions is missing");
        }
        return submissions.stream()
                .mapToInt(submittedAt -> DeadlineScore.score(deadline, submittedAt))
                .max()                                          // the best submission
                .orElse(DeadlineScore.NONE);                    // no submissions: zero
    }
```

`stream()` … `max()` is a way to go through a list and take the largest
value. `submittedAt -> …` is a lambda again, this time with one
parameter: what to do with each submission. For an empty list, `max()`
finds nothing, and then `orElse` puts in zero.

For anything that takes a list, there's an old rule: **zero, one,
many**. An empty list breaks "take the first one" and dividing by the
count. A single element hides comparison bugs: there's nothing to compare
it with. Many is what the code was written for.

```java
    @Test
    void noAttemptsGetNothing() {
        assertThat(Attempts.best(DEADLINE, List.of())).isEqualTo(0);
    }

    @Test
    void singleAttemptCountsAsIs() {
        Instant late = DEADLINE.plus(Duration.ofHours(3));

        assertThat(Attempts.best(DEADLINE, List.of(late))).isEqualTo(50);
    }

    @Test
    void bestOfSeveralAttemptsCounts() {
        Instant early = DEADLINE.minus(Duration.ofDays(1));
        Instant late = DEADLINE.plus(Duration.ofDays(3));

        assertThat(Attempts.best(DEADLINE, List.of(late, early))).isEqualTo(100);
    }
```

Zero for an empty list is also a decision of the rule, and the test pins
it down. And in "many," the best submission is **not first**. Put it
first, and code that takes the first submission instead of the best one
by mistake would pass the test. Order doesn't matter to the rule, so
it's chosen so that it doesn't help a bug.

### null outside and inside the list

Two more unhappy paths: there's no list at all, or there is a list, but
it has a hole in it.

```java
    @Test
    void missingListIsAnError() {
        assertThatThrownBy(() -> Attempts.best(DEADLINE, null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("The list of submissions is missing");
    }

    @Test
    void missingTimeInsideListIsAnError() {
        List<Instant> withHole = Arrays.asList(DEADLINE, null);     // List.of doesn't allow null

        assertThatThrownBy(() -> Attempts.best(DEADLINE, withHole))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Submission time is not set");
    }
```

The hole inside the list gets the message from `DeadlineScore`. That way
the test also shows that every submission went through the shared rule.

⚠️ `List.of(…)` is usually the best way to build a list, but it doesn't
allow `null` and throws a `NullPointerException`. The test would fail
before `best` is even called, with `Errors`, having checked nothing. For
the list with a hole, we use `Arrays.asList` here: it allows `null`.

### The same checklist on real code

On the team, the tests for calculating a price with discounts are laid
out the same way:

* no active rules: the price doesn't change; one rule; many rules and the
  order between them;
* there's a rule, but it has expired;
* no person is given, `null`: personal discounts don't apply;
* a 100% discount gives a total of 0, not a negative number; a discount
  larger than the price also gives 0;
* an uneven number: the total gets rounded, not the discount;
* an unknown or inactive plan: an exception.

Unlike in `Attempts`, order matters here, and the order test is set up
so that the wrong order gives a different total.

### How to read the task's table

In the real project, a task's "Test requirements" section (Article 1)
usually starts with where the tests go and what to name the class. Then
come items "Test N: …": what to pass in, and a line "Check: …".
Sometimes there's a table instead of items, where each row is a case.

Read the section as an "input → result" table: each item is a row.
"Check" gives the result, and if an error message is named, the message
too. The rule there says it in so many words: a table row is a check.
Write the rows down before the code, and you'll see right away which
classes are missing.

Say a task about `Attempts` gives you this table:

| submissions | result |
|---|---|
| none | 0 |
| one, 3 hours after the deadline | 50 |
| two: 3 days late and a day before the deadline | 100 |

Zero, one, and many are all here. But `null` isn't, neither outside the
list nor inside it. You need every single row from the task; add your two
on top of them and explain them in the pull request: the reviewer will
see that you thought about the unhappy path.

Then go through the task text with a pencil. Numbers, "no more than,"
"from … to," "empty," "not given": these are classes and boundaries.
Do the requirements cover both sides of every boundary? An empty list,
one element, several? `null`?

### A check that looked one way

The real project has completeness checks: tests compare the list of
addresses in the description with the addresses in the code. You can
compare in two directions: "every address in the description exists in
the code," and "every address in the code exists in the description."
Some of the checks looked only one way: they went through the
description and looked for the address in the code. Three endpoints
that weren't in the description at all slipped past them: there was
nothing to compare against. A check in the other direction goes through
the code, and it immediately found five endpoints with no entry in the
description, those three among them.

Ask every check which way it looks and what slips past it. Tests built
from the requirements look from the promises to the code. The opposite
question is whether the code has something nobody promised or checked,
an extra branch, for example. The coverage report answers that one: how
to read it is shown in [Article 0](https://hammerhall.io/en/ledger/articles/0-before-spring),
with more later in the series.

💡 There's an approach where a machine comes up with the cases:
**property-based testing**. You describe a property, for example "as
lateness grows, the score doesn't go up," and the library picks hundreds
of inputs by itself, looking for one that breaks the property.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. How does the happy path differ from the unhappy one, and why do tests
   of the happy path alone check the easiest part of the code?
2. What classes do the inputs of `DeadlineScore` fall into? Which class
   was missing from the four tests in Article 2, and which break took
   advantage of that?
3. Why don't the "a minute early" and "an hour late" tests notice that
   a day became 23 hours, while the `PT24H` row does?
4. Why is "right after the deadline" `PT0.000000001S` in the table, and
   not `PT1S`? Read `PT24H0.000000001S` out loud.
5. How does the row `PT20M | 50` end up in the parameters
   `Duration lateness` and `int expected`? Why does the number 50 have
   quotes in the run's name?
6. Why check an exception's message and not just its type? Explain using
   the two checks in `DeadlineScore`.
7. What does "zero, one, many" mean for `Attempts`? Why is the best
   submission not first in the "many" test, and why is the list with
   `null` inside built with `Arrays.asList`?
8. A task's "Test requirements" have three items, and the task text says
   "no more than 10 items." Which rows might be missing, and what will
   you do about it?

---

## What's next

The next article in the series is a test that checks nothing: green no
matter what you break. We'll break the code by hand, one step at a
time, and look at what coverage tells you and what it keeps quiet about.

## Sources

* [JUnit 6: Parameterized Classes and Tests](https://docs.junit.org/6.0.3/writing-tests/parameterized-classes-and-tests.html):
  `@CsvSource`, `@NullSource`, implicit conversion (the table of types),
  run names and the JUnit 6 quotes;
* [AssertJ: Exception assertions](https://assertj.github.io/doc/#assertj-core-exception-assertions):
  `assertThatThrownBy`, `hasMessage`, and related assertions;
* [Java 25: `Duration.parse`](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Duration.html#parse(java.lang.CharSequence)):
  the `PnDTnHnMn.nS` format, with examples;
* [Java 25: `Instant`](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Instant.html):
  the first paragraphs, on how time is stored and why the precision is
  a nanosecond;
* [Java 25: `List`, Unmodifiable Lists](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/List.html#unmodifiable):
  why `List.of` doesn't allow `null`.

---

## The full example, with imports

The learning example lives in the `testy` sandbox from Article 1. No new
dependencies are needed: parameterized tests come with
`spring-boot-starter-test`. `DeadlineScore` is the same as in Article 1:
it's here so you have something to restore after the breaks.
`DeadlineScoreTest` fully replaces the test from Article 3, at the same
path. `Attempts` and `AttemptsTest` are new. Leave `ManualCheck` and
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

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.NullSource;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class DeadlineScoreTest {

    // midnight, October 13, Moscow time
    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @ParameterizedTest(name = "late by {0} → {1}")
    @CsvSource(delimiter = '|', textBlock = """
            -P30D              | 100
            -PT1S              | 100
            PT0S               | 100
            PT0.000000001S     | 50
            # complaint from Article 3: submitted 20 minutes late, got 100
            PT20M              | 50
            PT1H               | 50
            PT24H              | 50
            PT24H0.000000001S  | 0
            P2D                | 0
            """)
    void scoreByLateness(Duration lateness, int expected) {
        int score = DeadlineScore.score(DEADLINE, DEADLINE.plus(lateness));

        assertThat(score).isEqualTo(expected);
    }

    @Test
    void noDeadlineIsAnError() {
        assertThatThrownBy(() -> DeadlineScore.score(null, DEADLINE))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Deadline is not set");
    }

    @ParameterizedTest
    @NullSource
    void noSubmissionTimeIsAnError(Instant submittedAt) {
        assertThatThrownBy(() -> DeadlineScore.score(DEADLINE, submittedAt))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Submission time is not set");
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

```java
// src/main/java/example/testy/score/Attempts.java
package example.testy.score;

import java.time.Instant;
import java.util.List;

/** Several submissions of one task: the best one counts. */
public final class Attempts {

    private Attempts() {
    }

    /** The best score across all submissions; never submitted means zero. */
    public static int best(Instant deadline, List<Instant> submissions) {
        if (submissions == null) {
            throw new IllegalArgumentException("The list of submissions is missing");
        }
        return submissions.stream()
                .mapToInt(submittedAt -> DeadlineScore.score(deadline, submittedAt))
                .max()                                          // the best submission
                .orElse(DeadlineScore.NONE);                    // no submissions: zero
    }
}
```

```java
// src/test/java/example/testy/score/AttemptsTest.java
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class AttemptsTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Test
    void noAttemptsGetNothing() {
        assertThat(Attempts.best(DEADLINE, List.of())).isEqualTo(0);
    }

    @Test
    void singleAttemptCountsAsIs() {
        Instant late = DEADLINE.plus(Duration.ofHours(3));

        assertThat(Attempts.best(DEADLINE, List.of(late))).isEqualTo(50);
    }

    @Test
    void bestOfSeveralAttemptsCounts() {
        Instant early = DEADLINE.minus(Duration.ofDays(1));
        Instant late = DEADLINE.plus(Duration.ofDays(3));

        assertThat(Attempts.best(DEADLINE, List.of(late, early))).isEqualTo(100);
    }

    @Test
    void missingListIsAnError() {
        assertThatThrownBy(() -> Attempts.best(DEADLINE, null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("The list of submissions is missing");
    }

    @Test
    void missingTimeInsideListIsAnError() {
        List<Instant> withHole = Arrays.asList(DEADLINE, null);     // List.of doesn't allow null

        assertThatThrownBy(() -> Attempts.best(DEADLINE, withHole))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Submission time is not set");
    }
}
```

Try it yourself:

1. Run `./mvnw test`. Everything is green; if the sandbox has only the
   files from Articles 1–4, the total is `Tests run: 18`: twelve runs of
   `DeadlineScoreTest`, five of `AttemptsTest`, and the test from start.spring.io.
2. In `DeadlineScore`, change `Duration.ofHours(24)` to
   `Duration.ofHours(23)`. One row goes red: `expected: 50`,
   `but was: 0`. In the IDE it's labeled `late by "PT24H" → "50"`,
   and in the Maven log by the method name with the run number: the
   `PT24H` row is seventh in the table. Change it back.
3. In `DeadlineScore`, replace the checks after `null` with the
   teammate's version from Article 3. The rows `PT0.000000001S`, `PT20M`,
   `PT24H0.000000001S` and the midnight test go red, while `PT1H` stays green. Change it back.
4. Replace `throw new IllegalArgumentException("Deadline is not set");`
   with `return FULL;`. `noDeadlineIsAnError` goes red:
   `Expecting code to raise a throwable.` Change it back.
5. Move the table's closing `"""` four spaces to the left. There will be
   thirteen runs, and the red one will be the comment that turned into
   a data row. Change it back.

Now every row in the table has a reason to be there, and every boundary
has a break that turns it red.
