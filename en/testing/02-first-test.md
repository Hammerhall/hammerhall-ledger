# Your first unit test: from an empty file to a green report

> "From Red to Green" · Article 2 · 25 min read
>
> **Who it's for.** You've read Article 1 of this series, and you have its
> `testy` sandbox. You've read tests but haven't written one yet, or
> you've written them from a sample found online. You don't need the
> "From Java to Spring Boot" series.
>
> **What's inside.** How to write a unit test from scratch and why each
> line is there; why the expectation in a test is a number and why one
> test covers one behavior; how to name a test, run it, and make sure it
> can go red.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why write a test from scratch

It's your first task on the project, and it won't be accepted without
tests. You open the IDE, and `src/test/java` is empty or holds other
people's files. Where do you create your file? What goes on the first
line? What do you name the method?

The internet is happy to answer, but often from the past. Many examples
were written for JUnit 4, and they won't compile in this series'
sandbox. And a test stitched together from other people's pieces without
understanding them can't be defended in review. The reviewer will ask
why the expectation is a number and not a constant, and why there are
four tests instead of one. The answer has to be yours.

So this article takes one test class from an empty file to a green
report, line by line. A unit test, as in the table from Article 1, checks
one class without a database, a network, or Spring. It's the fastest and
the most common kind of test.

The example is the same deadline scoring. Submit before the deadline or
exactly on it, and you get 100. Up to a day late: 50. Later than that: 0.

The score comes from the static method `DeadlineScore.score(deadline, submittedAt)`.
It takes the deadline and the submission time, both `Instant`, and
returns the score. We'll write four tests, one for each case. The case
with no deadline (`null`) comes later in the series.

The sandbox is the same `testy` from [Article 1, "Why tests, and what the project expects from you"](https://hammerhall.io/en/ledger/testing/1-why-tests).
It already has `DeadlineScore`, `ManualCheck`, the `TestyApplicationTests`
test from Initializr, and our `DeadlineScoreTest` with one test. We'll
write the contents of `DeadlineScoreTest` from scratch. No sandbox? How
to build it is at the end of Article 1.

The short examples below have no `import` lines. The full files are at
the end of the article.

---

## Part 1. An empty file, the first method

### Where to create the file

A test for a class lives in `src/test/java`, in the same package as the
class. It's named after the class plus `Test`: that ending is how Maven
finds it (Article 1). For `DeadlineScore` from the `example.testy.score`
package, the path is `src/test/java/example/testy/score/DeadlineScoreTest.java`.

In the IDE, find the `src/test/java` folder in the project tree and
create the `example.testy.score` package in it, if it isn't there yet.
Create a class in the package. The package is written with dots; the IDE
creates the nested folders itself.

There are two reasons for the same package. The test can see what's
declared without an access modifier. And it's easy to find: the same
path, only the top folder is different. That's exactly where the
reviewer will look for it.

### An empty class

```java
package example.testy.score;

class DeadlineScoreTest {
}
```

This is already a real test class; it just has zero tests so far.
Notice: there's no `public` before `class`. In courses, classes are
almost always public, and your hand reaches for the word.

A test class doesn't need `public`. JUnit 5 and 6 find and run classes
and methods without it; only `private` isn't allowed. The JUnit
documentation recommends leaving `public` out unless there's a specific
reason. It doesn't break anything; it's just an extra word.

### A method marked @Test

```java
class DeadlineScoreTest {

    @Test
    void beforeDeadlineGetsFull() {
        // …
    }
}
```

`@Test` is an annotation, a marker for a tool (Article 1). JUnit looks
in the class for methods with this marker and runs each one as a
separate test. Its import is `org.junit.jupiter.api.Test`.

The method itself is simple:

* **`void`**: a test returns nothing; JUnit requires it. The result of
  a test isn't a value but an outcome: it passed or it failed.
* **No parameters.** The test is called by JUnit, not by your code, and
  our tests don't need parameters. Some tests receive their data as rows of
  a table. The series covers them later, and there's a first look in
  [Article 0, "What to know before Spring"](https://hammerhall.io/en/ledger/articles/0-before-spring)
  of the "From Java to Spring Boot" cycle.
* **No `public`**, just like the class.
* **The name**: more on it in Part 3.

⚠️ Online you'll see `import org.junit.Test`, `public` on the class and
on every method, and checks like `Assert.assertEquals(…)`. That's
JUnit 4, and there `public` was required. The sandbox has JUnit 6, which
is written like JUnit 5: annotations from `org.junit.jupiter.api`, no
`public`, checks with AssertJ. There's no JUnit 4 in the sandbox, so
such a test won't compile: on `import org.junit.Test` the compiler
answers `cannot find symbol`. It does find the `org.junit` package:
JUnit 6 lives inside it, in `org.junit.jupiter`. But there's no `Test`
class there.

It's worse if JUnit 4 sneaks into the project along with someone else's
library. Then the test compiles, but the build most likely won't run it,
while the IDE might. "Green only in the IDE" again, as in Article 1.
JUnit 3 and 4 tests are run by a separate JUnit engine for old tests,
Vintage, and the sandbox doesn't have it. The check is the same: you
added a test, and the number of tests in the report grew by exactly
that much.

### The DEADLINE constant

The first lines inside the class:

```java
    // midnight, October 13, Moscow time
    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");
```

All four tests need the deadline, and it's the same for all of them. You
could write it again in each test, but that's four identical lines. The
reader would have to check whether they really are identical. So the
deadline is a **constant**: a named value written once. Then each test
shows only what sets it apart from its neighbors: the submission time.

Every word in the declaration means something.

* `private`: only this class needs the constant.
* `static`: there's one for the whole class. Before **each** test, JUnit
  creates a new object of the test class: that way tests can't affect
  each other through fields. A regular field would be created anew for
  every test. A `static` field is one for all of them, and it tells you
  right away: the value is shared, not the state of a single test.
* `final`: the constant can't be given another value. No test can move
  the deadline for the others.
* A name in capital letters with underscores: that's how constants are
  named in Java.

And one more property, this time of `Instant` itself: it's **immutable**.
`DEADLINE.plus(…)` doesn't move the deadline; it returns a new moment in
time. So one constant can safely be shared between tests: nobody can
spoil it.

---

## Part 2. The body of a test: given, when, then

### Three blocks

Here's the first test in full:

```java
    @Test
    void beforeDeadlineGetsFull() {
        Instant submittedAt = DEADLINE.minus(Duration.ofMinutes(1));

        int score = DeadlineScore.score(DEADLINE, submittedAt);

        assertThat(score).isEqualTo(100);
    }
```

It's made of three blocks separated by blank lines.

* **Given**: the setup. The deadline is already there, it's a constant.
  The submission time is a minute before the deadline: `minus` subtracts
  a span of time, a `Duration` (Article 1), and `ofMinutes(1)` makes it
  one minute.
* **When**: exactly one action, the one we're checking: the call to
  `score`.
* **Then**: the check: the score equals 100.

The pattern is named after its three blocks: **"given, when, then"**.
Another name for it is arrange, act, assert. The blank lines aren't
there for looks. They let your eye find the setup, the action, and the
check at a glance.

Some teams also write `// given`, `// when`, `// then` comments. In
a short test, blank lines are enough.

The second test has two blocks:

```java
    @Test
    void onDeadlineIsStillOnTime() {
        int score = DeadlineScore.score(DEADLINE, DEADLINE);    // submitted exactly on the deadline

        assertThat(score).isEqualTo(100);
    }
```

There's nothing to set up: the work came in exactly on the deadline, so
the submission time is `DEADLINE` itself. A block can be empty, but the
order can't change. The check always comes after the action, and there's
only one action.

### The check and import static

`assertThat(score).isEqualTo(100)` is the AssertJ check from Article 1:
"I assert that the score equals 100." Inside `assertThat(…)` goes what
the code returned. Inside `isEqualTo(…)`, what you expect. They're hard
to mix up: the words themselves tell you the order.

If they don't match, the test is red, and AssertJ prints both values:
what was expected and what came back. How to read a red report in full
comes later in the series.

Where does `assertThat` without a class name come from? It's a static
method of the `org.assertj.core.api.Assertions` class. The full call
would look like this: `Assertions.assertThat(score)`. A line at the top
of the file makes it shorter:

```java
import static org.assertj.core.api.Assertions.assertThat;
```

A regular `import` brings in a class. **`import static`** brings in
a static member of a class, a method or a constant, so you can write it
without the class name. The Java documentation advises using this
sparingly, only for things you call all the time. `assertThat` is called
in every test, so everyone writes it this way.

⚠️ For `assertThat`, the IDE may offer several options from different
libraries. The same `spring-boot-starter-test` set brings in
**Hamcrest**, another assertion library. It has its own `assertThat`
with two arguments, in the `org.hamcrest.MatcherAssert` class. Pick
that one, and the line `assertThat(score).isEqualTo(100)` won't compile.
We need `org.assertj.core.api.Assertions`.

### Why 100 and not DeadlineScore.FULL

`DeadlineScore` has a constant, `FULL = 100`. It's tempting to write the
check with it. It's shorter, and the check has no **magic number**,
a number whose meaning isn't explained. This is the wrong way, shown
only so we can take it apart:

```java
// don't write it this way: the expectation comes from the code under test
assertThat(score).isEqualTo(DeadlineScore.FULL);
```

Imagine someone made a typo while editing the class: `FULL = 10`. Now
the code gives 10 points for work submitted on time. The test with
`FULL` is really asking the code: "did you return what you yourself
consider a full score?"

The code says "yes": 10 equals 10. The test is green, and the bug ships.
The test with the number `100` goes red: expected 100, got 10.

The expectation is what the test considers the right answer. It's
written **independently of the code** under test: from the promise,
that is, from the line of the rule "on time: 100". A test that takes its
expectation from the code under test checks the code against itself.
That's like a student grading an exam against their own rough draft.

The number in the test repeats the number in the code on purpose. The
promise is written down twice, in two independent places, and the build
makes sure the two match. This duplication isn't a sin; it's the whole
point of the test.

🔑 **The expectation in a test comes from the promise, not from the
code.** A test that took its expectation from a constant will agree with
a bug in it.

`DEADLINE` is a different matter: it's not an expectation but
a condition the test sets itself. That's why the constant lives in the
test, not in the class under test.

---

## Part 3. Four behaviors, four names

### The other tests

Two more tests, for late work:

```java
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
```

Now there are four submission moments: a minute before the deadline,
exactly on it, an hour late, and two days late. Their scores: 100, 100,
50, and 0. Each test checks one **behavior**: one promise of the rule in
one case. We'll get to the `@DisplayName` marker on the last one below.

### One test, one behavior

Why not one test with four checks in a row? There are three reasons.

**The first failed check stops the test.** AssertJ throws an error, and
the lines below it don't run. If two rules break, you see one. Fix it,
and only then do you see the second. Four separate tests show both
breaks at once.

**The name says what's broken.** A red `scoreWorks` test only tells you
"something's wrong with the scores." A red `lateWithinDayGetsHalf` names
the broken promise before you even open the code.

**Each test can run on its own.** When you're fixing one rule, you run
only its test. So tests must not depend on each other. JUnit doesn't
even promise to keep the order of the file. Its order, as the
documentation puts it, is "deterministic but intentionally nonobvious."
Each test prepares everything itself; the only thing they share is an
immutable constant.

One behavior doesn't have to mean one `assertThat` line. If the method
returns an object with two fields, there can be two checks.

### A test's name is the first thing you read when it fails

In the sandbox, a name is a short phrase. The words are run
together, each new one capitalized: the case and what happens
in it. `lateWithinDayGetsHalf` means "late within a day, gets half."
`onDeadlineIsStillOnTime` means "submitted exactly on the deadline, and
that's still on time". The word `test` in the name is redundant: it's
obvious that it's a test.

Bad names: `test1`, `testScore`, `scoreWorks`. In a project with
hundreds of tests, `test3` goes red, and its name tells you nothing.
You'll have to read the code just to figure out what was being checked.

In another style, the name is made of three parts joined with
underscores: `method_Should…_When…`. That's the method, what should
happen, and under what condition. The style is longer, but it's handy
when one class holds tests for several methods: the first part of the
name groups them by method. Our class checks one method, `score`, and
the first part would repeat in every name. So here we use the short
style.

In the real project, it's the other way around: almost all tests are
named with underscores. The order of the parts there is sometimes
different: the method, then the condition, then the result. Both styles
are alive and well. In someone else's project, write the way they do
there.

### @DisplayName: a name for people

**`@DisplayName`** is a JUnit marker that gives a test a second name,
for the report. It can hold what a method name can't: spaces, dashes,
punctuation, any language. In our file it's on one test so you can see
the difference. In the IDE, this test is labeled not
`lateByMoreThanDayGetsNothing()` but "more than a day late — zero".

When it helps. When a phrase is easier to read as a plain sentence than
as words glued together in camelCase. When the case has numbers and
conditions that turn into mush in a method name.

When it gets in the way. When the method name already reads well: then
it's a second name you have to keep in sync with the first. You changed
the behavior, fixed the method name, forgot about `@DisplayName`, and
now the report lies.

And most importantly: by default, Maven doesn't show the display name.
Its green log lists only classes, and it calls a failed test by its
method name. This can be configured, but the sandbox doesn't do it. So
`@DisplayName` doesn't replace a good method name; it only adds to it.

A good `@DisplayName` is the whole promise: the case and the outcome.
"More than a day late" names only the case. "More than a day late —
zero" also tells you what happens then.

On the team, settings tests have a `@DisplayName`. You'll find both
kinds there: a name with just the case, and a full phrase with both the
case and the outcome.

### Tests from the task's items

Remember the "Test requirements" section from Article 1? In the real
project, a junior's coding tasks have one, and it usually starts with
the class name and the note "no Spring". Then come items "Test 1: …",
"Test 2: …": each has a phrase about a behavior and what to check.

You can turn such a section into code with what you already know:

* name the class exactly as in the task: the reviewer finds it by that
  name, and the build by the `Test` ending;
* "no Spring" means a unit test, like ours;
* one item, one method: an item is exactly one behavior;
* take the method name from the item's phrase, in the short style.

An item number isn't a name: `test1` in a red report tells you nothing.
If the task gives you a test template with a method name, take the name
as is.

---

## Part 4. Run it, read the green, break it

### Three ways to run

* **One test**: the green triangle next to the method in the IDE. That's
  how you check what you're writing right now: a second, and you have
  the answer. From the command line: `./mvnw test -Dtest=DeadlineScoreTest#lateWithinDayGetsHalf`:
  the class, the `#` sign, and the method name.
* **A class**: the triangle next to the class, or the command
  `./mvnw test -Dtest=DeadlineScoreTest`.
* **Everything**: `./mvnw test`. Before you send your changes, run
  `./mvnw verify`, as in Article 1.

### A green report in the IDE

After the run, the IDE opens a panel with a tree. It shows the
`DeadlineScoreTest` class, and under it four tests with green check
marks, each with its time in milliseconds. Next to it is a summary: how
many passed out of how many. The two-days-late test is labeled with the
name from `@DisplayName`.

### A green report in Maven

In the sandbox, `./mvnw test` ends like this:

```
[INFO] Tests run: 5, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

Five tests: our four and `contextLoads` from Initializr. After Article 1
there were two. We rewrote one test and added three, and the count grew
by exactly as many as we added.

Higher up in the log there's a line for each class. For example,
`Running example.testy.score.DeadlineScoreTest`, and under it the class
total: `Tests run: 4, …`. In a green log, Maven doesn't print test names,
only classes.

### Every test red at least once

Four tests are green. Can you trust them? Not yet: you trust a green
test only if you've seen it red (Article 1). There we checked one test
this way; now we'll check each of the four. Here's the method we'll
break:

```java
    public static int score(Instant deadline, Instant submittedAt) {
        // … null checks: in the full example of Article 1
        if (!submittedAt.isAfter(deadline)) {                   // exactly on the deadline is still on time
            return FULL;
        }
        if (!submittedAt.isAfter(deadline.plus(GRACE))) {       // exactly a day late is still half
            return HALF;
        }
        return NONE;
    }
```

Break one line at a time, and each time it's one loop: change it, run
the class, see red, put it back, green again.

| what to break | what goes red | what it says |
|---|---|---|
| the first `return FULL;` → `return HALF;` | `beforeDeadlineGetsFull` and `onDeadlineIsStillOnTime` | expected 100, got 50 |
| `return HALF;` → `return FULL;` | `lateWithinDayGetsHalf` | expected 50, got 100 |
| `return NONE;` → `return HALF;` | `lateByMoreThanDayGetsNothing`, in the IDE "more than a day late — zero" | expected 0, got 50 |

Only one break at a time. Break two at once, and you can no longer tell
which test went red on which.

What did this give us? Every test went red at least once, and on its own
break. The first break took down two tests at once, and that's not
a duplicate. Both guard the full score, but at different points: before
the deadline and exactly on it.

And the break from Article 1, `isBefore` instead of `!isAfter`, is
caught by only one of the four: `onDeadlineIsStillOnTime`. "Before the
deadline" and "not after the deadline" differ only at the deadline
itself.

💡 Remember how in Article 1 the day turned into 23 hours? The four
tests don't see this break either: they all stay green. None of them
submits the work between 23 and 24 hours late. Which cases to pick so there are no such holes comes later in
the series.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. Why can the test class and methods be written without `public`, while
   the examples online have it? What happens to a test with
   `import org.junit.Test`?
2. Why is the deadline moved into a constant, and what do the words
   `private`, `static`, and `final` give it?
3. One test calls `DEADLINE.plus(Duration.ofHours(1))`. Does the
   deadline change in the next test? Why?
4. Find "given", "when", and "then" in `lateWithinDayGetsHalf`. Why does
   `onDeadlineIsStillOnTime` have two blocks?
5. A teammate suggests writing `isEqualTo(DeadlineScore.FULL)`: "no
   magic numbers". What happens to such a test if someone sets
   `FULL = 10`?
6. Why are four tests better than one with four checks?
7. Why is `lateWithinDayGetsHalf` better than `test3`? When is a name
   like `method_Should…_When…` more convenient, and why doesn't
   `@DisplayName` replace a good method name?
8. All four tests are green. What should you do so you can trust that
   green, and why break only one line at a time?

---

## What's next

The next article in the series is "The test went red: what to do". We'll
take apart a teammate's bug that the four tests from this article
missed, and then read the report and the stack trace and look for our
own line in them.

## Sources

* [JUnit 6: Test Classes and Methods](https://docs.junit.org/6.0.3/writing-tests/test-classes-and-methods.html):
  what JUnit considers a test class and a test method, and why `public`
  isn't needed.
* [JUnit 6: Display Names](https://docs.junit.org/6.0.3/writing-tests/display-names.html):
  `@DisplayName` and what you can put in it.
* [JUnit 6: Migrating from JUnit 4](https://docs.junit.org/6.0.3/migrating-from-junit4.html):
  how JUnit 4 from online examples differs.
* [AssertJ: documentation](https://assertj.github.io/doc/): the Quick
  start section, with `import static` and the first checks.
* [Maven Surefire: Using JUnit Platform](https://maven.apache.org/surefire/maven-surefire-plugin/examples/junit-platform.html):
  how Maven runs JUnit and how to show `@DisplayName` in its reports.

---

## The full example, with imports

The learning example lives in the `testy` sandbox from Article 1. How to
build it is described there, in "The full example". `DeadlineScore` and
`ManualCheck` stay as they were in Article 1, so they aren't here.
`DeadlineScoreTest` fully replaces the one-test version from Article 1,
at the same path. Leave `TestyApplicationTests` alone.

```java
// src/test/java/example/testy/score/DeadlineScoreTest.java
package example.testy.score;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

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
}
```

Try it yourself:

1. `./mvnw test`: `Tests run: 5, Failures: 0, Errors: 0, Skipped: 0`
   and `BUILD SUCCESS`.
2. In the IDE, run one test with the triangle next to the method, then
   the whole class. Find the display name in the tree. From the command
   line, `-Dtest=DeadlineScoreTest#lateWithinDayGetsHalf` gives
   `Tests run: 1`, and `-Dtest=DeadlineScoreTest` gives `Tests run: 4`.
3. The three breaks from the table in Part 4: one at a time, putting the
   line back each time.
4. Set `FULL = 10`. `beforeDeadlineGetsFull` and `onDeadlineIsStillOnTime`
   go red: expected 100, got 10. Put it back.
5. Change 24 hours to 23 in `GRACE`: everything is green. Put it back and
   remember this hole: we'll come back to it later in the series.

Now each of the four tests has what it was written for: it can go red,
and it goes red exactly when its promise is broken.
