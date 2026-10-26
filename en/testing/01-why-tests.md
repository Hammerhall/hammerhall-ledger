# Why tests, and what the project expects from you

> "From Red to Green" · Article 1 · 30 min read
>
> **Who it's for.** You know Java from a course: classes, methods, `if`,
> loops, lists. You've written a test once or twice, or never. Your first
> project is ahead, and with it your first pull request with a red X.
>
> **What's inside.** What a test is and why it beats checking by eye; where
> tests live, how to run them and read the result; what kinds of tests
> there are, and what the project expects from yours.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why this series

Your first task on a project often ends like this. The code is written
and it works: you ran it and looked. You open a **pull request**,
a request to merge your changes into the shared code. A couple of minutes
later, a red X appears next to it: the "Build & Test" check failed.

Inside are a few hundred lines of build log. And the **reviewer**, the
colleague who reads the code before it's merged, asks just one thing in
a comment: "Where are the tests?"

In courses, tests usually come in the last chapter: "and there are also
tests." On a project it's the other way around. Tests are the first thing
a reviewer looks at and the last thing the build lets through. On the
team it's a written rule: a task without tests isn't accepted, no matter
how well it works.

This series is about tests from the very beginning, in seven articles:

1. why tests, and what's expected from you: this article;
2. your first unit test;
3. the test went red: what to do;
4. which cases to test;
5. a test that checks nothing;
6. when your code is surrounded by other code: stubs;
7. a test with a real database.

You don't need to read the big "From Java to Spring Boot" series first.
Where a topic is already covered there, the article will tell you where
to look.

**The running example: deadline scoring.** A task is due by a deadline,
and its score depends on when it was submitted:

| when submitted | score |
|---|---|
| before the deadline or exactly on it | 100 |
| later, but no more than a day late | 50 |
| later than that | 0 |
| no deadline or no submission time | an error with a clear message |

The rule is a learning one, and you can check it yourself: the full code
is at the end of the article. Alongside it, you'll see how the real
project works with tests: which rules are written down there and what
happens when people forget them.

🔑 The main idea of the series, which we'll keep coming back to: **you
trust a green test only if you've seen it red.** You'll see why in Part 1.

---

## Part 1. A test is a program that checks a program

### Checking by eye

Here's the scoring rule in code. The deadline and the submission time are
`Instant`s: a point on the timeline, with no time zone. `Duration` is
a span of time.

```java
public final class DeadlineScore {

    public static final int FULL = 100;
    public static final int HALF = 50;
    public static final int NONE = 0;

    static final Duration GRACE = Duration.ofHours(24);         // how late you can be and still get half

    public static int score(Instant deadline, Instant submittedAt) {
        // … the null checks are in the full example
        if (!submittedAt.isAfter(deadline)) {                   // not after the deadline: on time
            return FULL;
        }
        if (!submittedAt.isAfter(deadline.plus(GRACE))) {       // not after the deadline plus a day: half
            return HALF;
        }
        return NONE;
    }
}
```

`isAfter` answers "is it later?"; the `!` in front of it means "not
later," that is, earlier **or exactly at**. The short examples have no
`import` lines; the complete files are at the end of the article.

How do you check that the rule works? In courses, it's usually like this:
you write a `main`, run it, and eyeball the output.

```java
class ManualCheck {

    void main() {
        Instant deadline = Instant.parse("2026-10-12T21:00:00Z");   // midnight, October 13, Moscow time

        IO.println(DeadlineScore.score(deadline, deadline.minusSeconds(60)));          // expect 100
        IO.println(DeadlineScore.score(deadline, deadline.plusSeconds(3600)));         // expect 50
        IO.println(DeadlineScore.score(deadline, deadline.plus(Duration.ofDays(2))));  // expect 0
    }
}
```

⚠️ In courses you saw `public static void main(String[] args)`
and `System.out.println`. That still works. Since Java 25 you can write
it shorter: Java runs `void main()` without `static` or parameters on its
own, and `IO` is a class from `java.lang`, so there's nothing to import.
The series uses Java 25, so that's how we write it.

The `Z` at the end of the time means Greenwich time (UTC). Moscow is
three hours ahead, so 21:00 in Greenwich is midnight in Moscow.

You run it, and the console shows `100`, `50`, `0`. You compare them with
the comments, and they match. Done?

For a homework exercise, yes. For a project, a check like this has three
problems.

**A person compares, not a program.** The program prints numbers, and
you're the one checking them. People get tired, they rush, and they see
what they expect to see.

**It has to be repeated, and nobody will.** A month from now, someone else
will come to this class with their own task. They don't know about
`ManualCheck`, and even if they do, they'll have to check by eye all over
again.

**There are more than three cases.** Exactly on the deadline, to the
second? Exactly a day later? No deadline at all? Every case means one
more print line and one more comparison by eye.

### A bug that checking by eye doesn't see

Imagine someone decided to "simplify" the first condition:

```java
if (submittedAt.isBefore(deadline)) {                           // was: !submittedAt.isAfter(deadline)
    return FULL;
}
```

It reads almost the same: "submitted before the deadline, full score."
We run `ManualCheck`: `100`, `50`, `0` again. Everything matches.

But there is a bug. Before the change, someone who submitted **exactly on
the deadline** got 100; after it, they get 50. "Before the deadline" and
"not after the deadline" differ at exactly one point: the deadline itself.
None of our three checks hits that point, so none of them noticed.

A check finds a bug only if one of its cases is a case where the bug
shows. Which cases to pick comes later in the series. For now, let's make
it so the check doesn't have to be repeated by hand.

### An automated test

A **test** is a program that calls your code itself, knows the correct
result itself, and compares them itself. It tells a person one of two
things. Everything matched: the test is **green**. Something didn't: the
test is **red**, and here's exactly what didn't match.

Here's a test for that very case, "exactly on the deadline." We'll go
over `@Test` and `assertThat` right below it.

```java
class DeadlineScoreTest {

    @Test                                                       // "this is a test": JUnit finds and runs it
    void onDeadlineIsStillOnTime() {
        Instant deadline = Instant.parse("2026-10-12T21:00:00Z");

        int score = DeadlineScore.score(deadline, deadline);    // submitted to the second

        assertThat(score).isEqualTo(100);                       // "I assert that the score is 100"
    }
}
```

**The expectation is written in the test itself**: you don't have to
remember it, you have to run the test. With the correct condition, it's
green. With the "simplified" one, it goes red and says:

```
expected: 100
 but was: 50
```

"Expected 100, got 50." There's nothing left to check by eye. And notice:
we've **seen this test red** on a real bug. So when it's green, you can
trust it. A test that has never gone red may not check anything at all;
more on those later in the series.

You'll see the two tools from this example every day.

**JUnit** is the most widely used testing library in Java. You write
methods and mark them with `@Test`. That's an **annotation**: a marker
above a method. On its own it does nothing; a tool reads it. JUnit finds
the marked methods, runs them, and reports which passed and which failed;
no `main` needed. It comes with `spring-boot-starter-test`, a set of
libraries that projects generated at start.spring.io include right away.

⚠️ Online you'll see JUnit 4 (`org.junit.Test`) and JUnit 5. The series
uses JUnit 6, and it's written the same way as 5: the same
`org.junit.jupiter` packages. Examples for 5 almost always work; examples
for 4 don't.

**AssertJ** is an assertion library from the same set.
`assertThat(score).isEqualTo(100)` reads like a sentence: "I assert that
the score equals 100." When it doesn't match, it says what was expected
and what came instead. How to run tests and where to see the result is
in Part 2.

### A green test answers its own question

The test is green. What does that tell us about the scoring rule? Exactly
one thing: someone who submits right on the deadline, to the second,
gets 100. The test didn't ask about being an hour or two days late, and
it won't tell you anything about that.

Change the day in `DeadlineScore` to 23 hours: `Duration.ofHours(23)`.
The rule is broken, and the test is still green. It doesn't check the
one-day limit.

🔑 **A green test answers exactly the question it was asked.**
Asking the right questions is the job of whoever writes the test.

### Regression: a test is for whoever comes next

Today your test is barely needed: you just checked everything anyway.
It's needed **tomorrow**, when someone else changes the code, or when you
do a month from now, having forgotten the details.

A **regression** is a bug in something that used to work: a change in one
place broke another. There's only one defense: after every change, run
**all** the tests, not just yours. Every test is someone's knowledge,
written down: "this is how it should be here." When you run them, you're
asking everyone who wrote code before you: "Did I break anything of
yours?"

In the real project, there are more than 1,300 such questions.
The build, with all of them, takes about three minutes, and every change
goes through it. Nobody remembers what each test checks, and nobody has to.

---

## Part 2. Where tests live and how to run them

### The src/test folder

Code and tests sit side by side, but separately:

```
src/
├── main/java/example/testy/score/DeadlineScore.java       ← the code
└── test/java/example/testy/score/DeadlineScoreTest.java   ← its test
```

* A class's test goes in `src/test/java`, **in the same package** as the
  class. That way the test can see what's declared without an access
  modifier, like `GRACE` in `DeadlineScore`. And it's easy to find: the
  same path, a different top folder.
* The test class is named after the class plus `Test`: `DeadlineScoreTest`.
* Files that only tests need go in `src/test/resources`: sample
  responses, special settings.

### Maven: build phases and name patterns

At work, tests are run by the build, not the IDE.

**Maven** is a program that builds a project from the description in
`pom.xml`: it downloads libraries, compiles the code and the tests, and
runs the tests. It comes into the project as the `mvnw` wrapper, which
downloads the right version itself. More on it in
[Article 0, "What to know before Spring"](https://hammerhall.io/en/ledger/articles/0-before-spring)
of the "From Java to Spring Boot" cycle.

A build runs in **phases**, in order: compile, `test`, package, …,
`verify`. A command with a phase name runs all the phases up to it:
`./mvnw verify` goes through `test` too. Libraries meant only for tests
are marked in `pom.xml` with `<scope>test</scope>` and don't end up in
the finished application.

In the `test` phase, tests are run by **Surefire**, a plugin, an add-on
that Maven brings in on its own. It decides which classes count as tests
**by name**. By default, it takes classes whose name:

* starts with `Test`: `TestDeadline`;
* ends with `Test`: `DeadlineScoreTest`;
* ends with `Tests`: `TestyApplicationTests`;
* ends with `TestCase`: `DeadlineTestCase`.

Everything else it skips **silently**. Maven will never run
a `ScoreRulesCheck` class with a dozen tests, while in the IDE it'll be
green: the IDE runs whatever you point it at.

**Integration** tests check code together with a real database; they come
later in the series. On the team, their names end in `IT`, and that ending
isn't on the list. That's why the patterns in `pom.xml` there are set
from scratch: `*Test` and `*IT`. Your own list **replaces** the defaults
instead of adding to them. A `…Tests` class won't run there, so tests are
named only `…Test` or `…IT`.

A name like `…IntegrationTest` ends in `Test`, so Surefire finds it even
without configuration. How to set your own patterns in `pom.xml` is shown
in [Article 3a, "Data, part 1: a table and a migration"](https://hammerhall.io/en/ledger/articles/3a-table-and-migration)
of the same cycle.

In many projects, `*IT` is run by a separate plugin, Failsafe, later in
the build. On the team it's simpler: Surefire runs `*Test` and `*IT`
in one run.

### Tests that are green only in the IDE

It happens: two integration test classes are green, but only in the IDE.
The build doesn't run them: the name ends in `IT`, and `pom.xml` has no
pattern for it. Nobody guards the code they're supposed to guard, and
everyone thinks it's guarded.

**A test that doesn't run is worse than no test**: you can't see that it's
idle, and it looks like protection. The check is simple. You added a test,
so the number of tests in the build report should go up by exactly that
much.

### Running

* **In the IDE**: the green triangle next to the test class or a single
  method. Handy while you're writing: you run only your own.
* **All tests**: `./mvnw test`. On Windows, the same in Git Bash;
  in the regular command prompt, `mvnw.cmd test`.
* **One class**: `./mvnw test -Dtest=DeadlineScoreTest`.
* **Everything the pull request will check**: `./mvnw verify`, the tests
  plus the phases after them. On the team, those include a coverage
  check; more on it in Part 4. Run `verify` before you push your changes,
  and run all of it. Your green tests are only half the question. The
  other half is whether you broke anyone else's.

### The report

At the end of a run, Maven writes a summary. In the sandbox from "The
full example," green looks like this, with two tests: yours and the one
from start.spring.io:

```
[INFO] Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

Red looks roughly like this:

```
[ERROR] Tests run: 2, Failures: 1, Errors: 0, Skipped: 0
[INFO] BUILD FAILURE
```

* **Failures**: an assertion didn't match. One thing was expected,
  another came, like our `expected: 100 but was: 50`.
* **Errors**: the test never reached the assertion. Along the way,
  an exception nobody expected flew out, for example
  a `NullPointerException`.
* **Skipped**: the test was skipped: disabled, or its run conditions
  weren't met.

Where to find the details comes later in the series. For now, remember:
a red build isn't a verdict, it's an address. It tells you where to look.

### The pull request check on GitHub

A run on your own machine isn't enough: you can forget, run only part of
it, and your machine may have things that others don't.

**GitHub Actions** is a GitHub service that runs commands on a GitHub
machine when something happens in a repository. Something like: a pull
request was opened, or commits were added to it. What to run is described
in the repository's own `.github/workflows/*.yml` files; there's nothing
to install. The result shows up in the pull request: a check mark or
an X next to each check, and the full log behind the Details link.

On the team, the pull request check runs the same build you do, but from
scratch: `clean verify`. `clean` first wipes the `target` folder with the
previous build. The check always saves the test reports, even when the
build fails: you can download them from the check's page.

A pull request isn't merged there while the build is red. The merge button
doesn't work until the "Build & Test" check is green and there are two
approvals. One of them is from the team lead, the senior person on the
team. That's set up in GitHub itself: required checks before merging; the
link is in the sources.

Once, the check there was set up only for pull requests into the main
branch, while the work was going on in another one. The check existed,
looked like protection, and didn't fire even once until somebody noticed.
The same trouble as with tests that are green only in the IDE.

⚠️ Green on your machine and red in the pull request isn't "GitHub being
glitchy." Most often the culprit is a file you forgot to commit; a test
that passes only in a certain order; or old files in your `target` that
a build from scratch doesn't have. Rerunning until it turns green is not
the answer. How to dig in comes later in the series.

---

## Part 3. What kinds of tests there are

### From unit to load

Different teams name tests differently. Below are the words the team
uses. For the table: **Spring** is the library the team writes services
with. It creates and wires the application's objects itself, but it
doesn't start up instantly. An **endpoint** is an address that a service
answers at.

| kind | what it checks | how long it takes |
| --- | --- | --- |
| **unit** | one class, with no database, network, or Spring | milliseconds |
| **settings test** | the application won't start with a wrong setting | fractions of a second |
| **web layer** | an endpoint: the response code and body, with no database | seconds |
| **integration** | code together with a real database | seconds |
| **end-to-end** | the whole application, from request to database | seconds and longer |
| **configuration and smoke** | the files parse; everything starts up together | minutes |
| **guard** | a project rule, checked against the files: "a package cycle fails the build," "migrations stay in their own schema" | seconds |
| **contract** | two services understand shared data the same way | seconds |
| **load** | how much the system can take and where it hits its limit | minutes and hours |

Unit, web layer, integration, and end-to-end tests are all written with
the same JUnit. They differ in **how much of the real thing** surrounds
the code: nothing; a slice of Spring; a database; the whole application.
A guard test is JUnit too, but it checks the project's files. Guard tests
are covered in [Article 11, "Guard tests"](https://hammerhall.io/en/ledger/articles/11-guard-tests)
of the "From Spring to a System" cycle. Configuration checks, smoke tests,
and load tests have tools of their own.

The **smoke** test, as the best-known story goes, takes its name
from electronics: you power up a new board and see whether smoke comes
out. Not "is everything right," but "is it alive at all."

A **load** test doesn't check whether the answer is right: it asks how
much the system can take and what breaks first.

### The pyramid

The more of the real thing around the code, the slower the test, the
longer it takes to write, and the worse it shows **where** the bug is.
A unit test failed: one method is to blame. An end-to-end test failed:
something somewhere between the request and the database. On the other
hand, the more of the real thing, the closer the test is to real life:
a unit test won't notice a bug in an SQL query, because there's no
database in it.

Hence the picture that every book on testing draws:

```
            ╱╲
           ╱  ╲          end-to-end: a handful; costly, slow, "something broke somewhere"
          ╱────╲
         ╱      ╲        integration: dozens; a database, seconds
        ╱────────╲
       ╱          ╲      unit: hundreds; milliseconds, the exact address of the bug
      ╱────────────╲
```

**The test pyramid**: many cheap tests at the bottom, few expensive ones
at the top. Mike Cohn came up with it; Martin Fowler wrote a short note
about it, linked in the sources. Its rule is simple: test every case **on
the lowest level where it shows**. A bug in the scoring formula is caught
by a unit test in milliseconds; a bug in SQL, only by an integration test.
And there's no reason to start the whole application for the sake of
a formula. Load tests aren't part of the pyramid: they're a separate
kind, more expensive than any of these.

But the lower levels alone aren't enough either: each check answers only
its own question. "The settings file parsed" doesn't yet mean "the
programs with these settings found each other." That's why, on the team,
after the files are checked, everything is started up together to see
what happens. That's the smoke test from the table.

---

## Part 4. What's expected from you

### Rules of the real project

On the team, the rules about tests are written down plainly. In short:

1. **A task is accepted only with tests**, in the same pull request as
   the solution.
2. **Tests follow the task's table**: one row of the table, one check.
3. **The task's new code is fully covered**: every line and every
   branch. Whatever a test can't execute is named in the pull request,
   with the reason.
4. **The coverage threshold for the whole project is 80% of lines and 70%
   of branches.** Below the threshold, the build is red. The threshold
   only goes up: to merge a task, you write more tests, you don't lower
   the threshold.
5. **Coverage isn't proof.** A test that doesn't check the result adds
   coverage and catches nothing. The reviewer looks at **what** the test
   checks.

**Coverage** is the share of the code the tests executed. It's measured
by **JaCoCo**, a Maven plugin that, during the run, marks the lines that
were executed and the **branches** taken: the paths through an `if`,
"yes" and "no." Don't confuse them with git branches. JaCoCo checks the
threshold on `./mvnw verify` and puts the report in
`target/site/jacoco/index.html`. How to read the report is shown
in [Article 0](https://hammerhall.io/en/ledger/articles/0-before-spring);
more comes later in the series. Your new code gets 100% coverage; the
project as a whole, 80% and 70%.

And about assistants. Under the same rules, a junior may ask
a language model only to **explain** things: a failed test, someone
else's code. It must not **write** the test for them. The reason isn't
a formality, and it holds for any project: a test is your understanding
of the task, written as code. You can't defend someone else's
understanding in a review.

### Test requirements in a task

In the real project, a junior's coding tasks have a "Test requirements"
section: which tests to write, what to name them, and what each one
checks, point by point. It's not a hint, it's part of the task. It's the
very task table from the rules: each point is a check. Without these
tests, the task isn't done, even if everything works.

### Unwritten rules

These aren't in the rules, but the reviewer will ask.

* **Someone else's test is a recorded promise.** If your change broke
  someone else's test, read it first: what does it guard, and why?
  Maybe it's your change that's wrong, not the test. Once, reading a test
  like that saved access people had paid for; that story comes later in
  the series.
* **Red isn't hidden**: you don't delete the test, disable it, or adjust
  the expectation to fit whatever came out. An adjusted test is green and
  now guards the wrong behavior. What to do instead comes later in the
  series.
* **A test must be able to go red.** Once you've written it, break the
  code by hand and see whether it goes red, as we did in Part 1. If it
  doesn't, it checks nothing.
* **A test cleans up after itself.** The project's tests run one after
  another in one program and with one database. A test that changed
  something shared and didn't put it back breaks other tests, and only
  in a certain run order. More on the database later in the series.

### Checklist for a pull request with tests

- [ ] every new behavior has a test; a fixed bug has a test that is
      red without the fix;
- [ ] every new test has been red at least once: you broke the code by hand;
- [ ] `./mvnw verify` is green on your machine, all of it, before you
      push, and the report shows exactly as many new tests as you added;
- [ ] no one else's test is deleted or disabled without an explanation;
- [ ] the description says what the tests check and what isn't covered, and why.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. What's wrong with checking through `main` and printing, if today it
   showed the right numbers?
2. Why doesn't replacing `!submittedAt.isAfter(deadline)` with
   `submittedAt.isBefore(deadline)` show up in `ManualCheck`? Which
   case catches it?
3. The `onDeadlineIsStillOnTime` test is green. What does that tell you
   about the scoring rule, and what doesn't it tell you?
4. What is a regression, and what do tests you didn't write have to do
   with it?
5. A `ScoreRulesCheck` class with tests is green in the IDE. Why won't the
   build run it, and how do you notice that a test isn't running?
6. How do `Failures` differ from `Errors` in a Maven report?
7. Why does a project have more unit tests than end-to-end ones, even
   though end-to-end tests are closer to real life?
8. Your change broke someone else's test, and it's keeping your task from
   being merged. What do you do first, and what don't you do?

---

## What's next

Article 2 is your first unit test. We'll write `DeadlineScoreTest` from
scratch and go through every line: the test class, the method, the
assertion, and how to name a test so that when it fails, it tells you
itself what broke.

## Sources

* [JUnit 6: Annotations](https://docs.junit.org/6.0.3/writing-tests/annotations.html):
  `@Test` and JUnit's other markers;
* [AssertJ: documentation](https://assertj.github.io/doc/): start
  with Quick Start;
* [Maven Surefire: Inclusions and Exclusions of Tests](https://maven.apache.org/surefire/maven-surefire-plugin/examples/inclusion-exclusion.html):
  the name patterns Maven uses to find tests;
* [Martin Fowler: Test Pyramid](https://martinfowler.com/bliki/TestPyramid.html):
  a short note on the pyramid;
* [GitHub Docs: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches):
  the section on required checks before merging.

---

## The full example, with imports

A learning example. It lives in its own sandbox, a small project where
everything runs right away. You'll need the sandbox in the next articles
of the series too.

**The `testy` sandbox.** The site start.spring.io (Spring Initializr)
generates a skeleton project in a minute. The fields:

| field | value |
|---|---|
| Project | Maven |
| Language | Java |
| Spring Boot | 4.1.x, the latest 4.1 |
| Group | `example` |
| Artifact | `testy` |
| Package name | `example.testy` |
| Java | 25 |

Don't add any dependencies: without them, Initializr includes
`spring-boot-starter-test` on its own. It already brings JUnit, AssertJ,
and Mockito, a library for mocks covered later in the series. You need
JDK 25: with the JDK from your course, 17 or 21, the build fails with
`release version 25 not supported`.

Generate downloads an archive; unzip it and open the folder with
`pom.xml` in your IDE. Put your classes in the `example.testy.score`
subpackage. Initializr also creates `TestyApplication` and
a `TestyApplicationTests` test with an empty `contextLoads` method:
"the application at least starts up." Don't touch them.

`import static` in the test brings in the static method `assertThat`,
so you can write it without the class name.

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
// src/main/java/example/testy/score/ManualCheck.java
package example.testy.score;

import java.time.Duration;
import java.time.Instant;

/** Checking by eye: run it and compare what's printed with what you expect. */
class ManualCheck {

    void main() {
        Instant deadline = Instant.parse("2026-10-12T21:00:00Z");   // midnight, October 13, Moscow time

        IO.println(DeadlineScore.score(deadline, deadline.minusSeconds(60)));          // expect 100
        IO.println(DeadlineScore.score(deadline, deadline.plusSeconds(3600)));         // expect 50
        IO.println(DeadlineScore.score(deadline, deadline.plus(Duration.ofDays(2))));  // expect 0
    }
}
```

```java
// src/test/java/example/testy/score/DeadlineScoreTest.java
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

class DeadlineScoreTest {

    @Test
    void onDeadlineIsStillOnTime() {
        Instant deadline = Instant.parse("2026-10-12T21:00:00Z");

        int score = DeadlineScore.score(deadline, deadline);

        assertThat(score).isEqualTo(100);
    }
}
```

Now do by hand what Part 1 described in words:

1. Run `ManualCheck`: `100`, `50`, `0`. Run `./mvnw test`:
   `Tests run: 2`, all green.
2. In `DeadlineScore`, replace the first condition with
   `if (submittedAt.isBefore(deadline))`. Run both again.
   `ManualCheck` prints the same thing. The test is red: `expected: 100`,
   `but was: 50`.
3. Put the condition back the way it was. The test is green again.
4. Change `Duration.ofHours(24)` to `Duration.ofHours(23)`: the test is
   green, because it didn't ask about the one-day limit. Change it back.

Now you know the main thing about this test. It can go red, and it does
go red when the thing it asks about is broken: "exactly on the deadline
means 100." A green result from a test like that can be trusted.
