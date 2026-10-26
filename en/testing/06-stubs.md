# When your code is surrounded by other code

> "From Red to Green" · Article 6 · 30 min read
>
> **Who it's for.** You've read Articles 1–5 of this series: you have the
> `testy` sandbox with the deadline scoring rule, you pick cases, and you
> break the code by hand to check a test. You don't need the "From Java
> to Spring Boot" series.
>
> **What's inside.** How to test a service that needs a database, another
> service, and a clock: with stubs written by hand and with Mockito; how
> to substitute "now"; what to replace and what to leave real.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why stubs

Everything we've tested so far is `DeadlineScore`: two moments in time go
in, a number comes out. No database, no network, no clock. Code like this
is called **pure logic**: the result depends only on the input, and the
test calls it directly.

On a project there's less of this code than you'd like. The scoring rule
on its own is no use to anyone: something has to find out when the task
was submitted, look up its deadline, compute the score, and record it.
That's the job of a **service**, a class that connects the logic with its
neighbors. A service almost always has neighbors: a repository, a clock,
a client for another service.

How do you test a service that talks to a database when it runs? You could
start a database, insert a row, call the service, and look in the table.
The test would get slow, depend on someone else's data, and fail whenever
the database is down, even though your code is fine. And for the case
"24 hours have passed," you'd have to wait 24 hours.

The way out is a stub. You already caught a glimpse of one in the rate
test in
[Article 5, "A test that checks nothing"](https://hammerhall.io/en/ledger/testing/5-test-that-checks-nothing):
an object that takes the place of a real neighbor in a test and answers
whatever it's told to. Like a stand-in at a rehearsal: it reads the right cue at the right moment,
but it can't play the whole part. In books you'll see "stub," "mock,"
"fake," and "test double," with subtle differences. This series, like the real
project, skips the fine print: a stub is one you write by hand, a mock is one Mockito makes.

With stubs, a service test stays a unit test (Article 1): one class,
no database, no network, no Spring. Tasks in the real project come with
notes like "no Spring," "the repository is a Mockito mock," `Clock.fixed`.
After this article, you'll understand every word.

**The running example is the scoring service, `ScoreService`.** First we'll
write the stubs by hand, with no libraries, to see what's inside them. Then
Mockito will do the same thing: that's how service tests are usually written at work.

---

## Part 1. The service and its neighbors

### Neighbors are interfaces

The service has three neighbors: the submission log, the deadlines, and the
scoreboard. Plus the clock. When the service runs, a database stands behind
the log and the board, and another service stands behind the deadlines.
Each neighbor is described by an **interface**, a list of methods with no
implementation. The interface says "what," and "how" is up to the class that
implements it (`implements`): the real one at work, a stub in a test.

Three interfaces, three files. The short examples leave out the `package`
and `import` lines; the full files are at the end of the article.

```java
public interface SubmissionLog {

    /** When the student submitted the task; empty if they haven't. */
    Optional<Instant> submittedAt(String studentId, String taskKey);
}

public interface Deadlines {

    Instant deadlineOf(String taskKey);
}

public interface ScoreBoard {

    void record(String studentId, String taskKey, int score);
}
```

`Optional<Instant>` means "maybe a moment in time": a box that either holds
a value or is empty. The angle brackets say what can go in the box. This
way the method honestly says "the student may not have submitted," and
instead of `null` it returns an empty box: `Optional.empty()`. A box with
a value is `Optional.of(…)`; to ask whether it's empty, call `isEmpty()`; to
take the value out, call `get()`.

### The service

```java
public class ScoreService {

    private final SubmissionLog log;
    private final Deadlines deadlines;
    private final ScoreBoard board;
    private final Clock clock;                                  // "now" comes only from here

    public ScoreService(SubmissionLog log, Deadlines deadlines, ScoreBoard board, Clock clock) {
        // … stores the neighbors in fields
    }

    public Optional<Integer> grade(String studentId, String taskKey) {
        Instant deadline = deadlines.deadlineOf(taskKey);
        Optional<Instant> submittedAt = log.submittedAt(studentId, taskKey);

        if (submittedAt.isEmpty()) {
            Instant lastChance = deadline.plus(DeadlineScore.GRACE);
            if (clock.instant().isAfter(lastChance)) {          // too late to submit for half
                board.record(studentId, taskKey, DeadlineScore.NONE);
                return Optional.of(DeadlineScore.NONE);
            }
            return Optional.empty();                            // not too late yet: leave it alone
        }

        int score = DeadlineScore.score(deadline, submittedAt.get());
        board.record(studentId, taskKey, score);
        return Optional.of(score);
    }
}
```

Three paths. Submitted: a score by the rule, recorded on the board. Not
submitted, and 24 hours past the deadline have gone by: zero, also recorded
on the board. Not submitted, but it's not too late yet: empty, and the board
stays untouched. `GRACE` is those same 24 hours from `DeadlineScore`: the
service lives in the same package and can see it.

The service can't compute a score itself; `DeadlineScore` does that, and
the tests from Articles 2–5 check it. A service test has its own questions:
was the right path taken, what did the service return, and what did it
record on the board.

The key thing here is the constructor. The service creates neither its
neighbors nor its clock, and it doesn't know who's on the other end:
a database or a stub. They're passed in from outside, which means a test
can pass in its own.

---

## Part 2. Stubs by hand

### A lambda: a one-line stub

You could write a stub for `Deadlines` as a class: `implements Deadlines`,
a method that returns the deadline. Five lines for one answer. There's a
shorter way. An interface with exactly one method without an implementation
is called **functional**, and you can write an object of it as a lambda, as
in `assertThatThrownBy` from Article 4.

```java
private final Deadlines deadlines = taskKey -> DEADLINE;                     // one deadline for all tasks
```

Read it like this: "when asked for the deadline of any task, answer `DEADLINE`."
`DEADLINE` is the deadline constant, as in Article 2. The lambda's parameters
are the parameters of that single method, and its result is the method's
answer. Java figures out which interface is meant from the variable's type.
Two parameters go in parentheses:

```java
SubmissionLog log = (studentId, taskKey) -> Optional.of(DEADLINE.plus(Duration.ofHours(2)));
```

"Whoever you ask about, they submitted two hours after the deadline."

### A stub that remembers

That won't work for the board. `record` returns nothing (`void`). A lambda
could accept the call, but the test would never learn what was recorded.
You need a stub with a memory:

```java
/** A board that remembers what was recorded on it. */
static class RememberingBoard implements ScoreBoard {

    final List<String> records = new ArrayList<>();

    @Override
    public void record(String studentId, String taskKey, int score) {
        records.add(studentId + " " + taskKey + " " + score);
    }
}
```

It's a class inside the test class; `static` means it doesn't need a test
object. `@Override` says "this method comes from the interface." Get the
name wrong, and the compiler will tell you. Each call adds a string like
`student-1 T-7 50` to the list: a string, so it's easy to read in a red
report.

### The clock: "now" comes from outside

The third path, "not submitted, and 24 hours have passed," depends on
"now." If the service took it from `Instant.now()`, the test would get the
real moment it was run. To check "25 hours after the deadline," you'd have
to wait 25 hours. Or you'd count the deadline from "now," and then the test
would mean something slightly different every day. It's the same trouble
as with the time zone in Article 3: the result depends on where and when
you ran it.

**`Clock`** is a class from `java.time`: an object that answers "what time
is it" (`clock.instant()`). Its documentation says plainly what it's for:
so you can plug in a different clock, which makes testing easier. At work
the clock is the real system clock. In a test it's
**`Clock.fixed(instant, zone)`**: a stopped clock that always shows the same
time. The `ZoneOffset.UTC` zone is a formality here: we only ask for an
`Instant`, and an `Instant` has no zone.

In the real project this is a rule: code takes "now" only from a `Clock`,
and it gets the clock through its constructor. [Article 1, "Why Spring"](https://hammerhall.io/en/ledger/articles/1-why-spring)
of the "From Java to Spring Boot" cycle walks through the clock and a hand-written
stub on a different example.

### The tests

A helper method builds the service from the stubs and a clock stopped at
the right moment; `deadlines` is the lambda from above:

```java
private final RememberingBoard board = new RememberingBoard();

private ScoreService serviceAt(Instant now, SubmissionLog log) {
    return new ScoreService(log, deadlines, board, Clock.fixed(now, ZoneOffset.UTC));
}

@Test
void notSubmittedYetIsNotGraded() {
    SubmissionLog log = (studentId, taskKey) -> Optional.empty();
    ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(3)), log);   // 24 hours not up yet

    Optional<Integer> score = service.grade("student-1", "T-7");

    assertThat(score).isEmpty();
    assertThat(board.records).isEmpty();
}

@Test
void notSubmittedAfterGraceGetsNothing() {
    SubmissionLog log = (studentId, taskKey) -> Optional.empty();
    ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(25)), log);  // 24 hours are up

    Optional<Integer> score = service.grade("student-1", "T-7");

    assertThat(score).contains(0);
    assertThat(board.records).containsExactly("student-1 T-7 0");
}
```

The board is a field of the test class, but the tests don't get in each
other's way. JUnit creates a new test object before every test method
(Article 2), so each one starts with an empty board. The AssertJ checks
here are:

* `contains(0)`: "the box holds zero";
* `isEmpty()`: "empty";
* `containsExactly(…)`: "the list holds exactly this and nothing else."

Three hours and 25 hours sit on opposite sides of the boundary, but far
from it. Right at the boundary you'd put "exactly 24 hours" and "24 hours
and one nanosecond," as in the table from Article 4.

The third test, `submittedLateWithinDayGetsHalf`, checks the "submitted"
path: a score of 50, and `student-1 T-7 50` on the board. Why check both
the answer and the board? Delete the line `board.record(studentId, taskKey, score);`
after the score is computed. The answer stays correct, 50, but the test goes
red on the second check: nothing made it onto the board. Without that check,
nobody would have seen the bug.

Now replace `clock.instant()` in the service with `Instant.now()`. One of
the two tests above goes red, but which one is up to the calendar. Before
October 13, 2026, 21:00 UTC (the deadline plus 24 hours), it's
`notSubmittedAfterGraceGetsNothing` that's red: the real 24 hours haven't
passed yet. After that, it's `notSubmittedYetIsNotGraded`: they already
have. Code with `Instant.now()` can't be tested for both cases at all.

Put the service back the way it was. The tests went red on real bugs, so
now you can trust their green (Article 1).

🔑 **Everything code takes from outside, it should get through its
constructor: the database, the network, the clock.** Then a test can plug
in a stub, and it doesn't have to wait or start a database.

---

## Part 3. Mockito

### What it is and where it comes from

Hand-written stubs are fine while there are few neighbors. At work a service
can have five or more. Each one needs its own class like `RememberingBoard`,
and each test needs its own answers.

**Mockito** is a library that makes a stand-in for any interface or class
in one line: a mock. You tell the mock what to answer, and afterward you
check how it was called. If it's called the wrong way, the test is red. Courses
usually skip Mockito, but at work it's in almost every service test.

Article 1 promised to cover it: Mockito comes into the sandbox with
`spring-boot-starter-test`, so there's nothing to install. Its tests run like
any others, with `./mvnw test`, and the results land in the same report.
For a different example, in an endpoint test, see
[Article 4, "Your first endpoint: how an application answers over HTTP"](https://hammerhall.io/en/ledger/articles/4-web)
of the "From Java to Spring Boot" cycle.

### WARNING lines in the log

Next to the Mockito tests, the build log will most likely show `WARNING`
lines from Java itself: "A Java agent has been loaded dynamically…".
Along with them comes a Mockito line: "Mockito is currently self-attaching…".
The tests don't fail because of them.

To make mocks of any class, Mockito 5 rewrites classes right while the
tests run. To do that, it attaches an agent to Java, a helper like the one
JaCoCo uses in Article 5. JaCoCo is attached at startup, while Mockito
attaches itself on the fly. Since version 21, Java warns about this:
someday, attaching on the fly will be off by default.

On Java 25 it's still only a warning. You can get rid of it by attaching
Mockito as an agent explicitly, with the `-javaagent` flag for Surefire.
Section 0.3 of the Mockito documentation shows how to write this in
`pom.xml`. Boot 4.1 doesn't do it for you: neither start.spring.io nor
Boot's parent `pom.xml`. We don't do it in the sandbox either: this article
doesn't change `pom.xml`.

### @Mock and MockitoExtension

The same stubs, made by Mockito:

```java
@ExtendWith(MockitoExtension.class)
class ScoreServiceMockitoTest {

    @Mock
    private SubmissionLog log;

    @Mock
    private Deadlines deadlines;

    @Mock
    private ScoreBoard board;

    private ScoreService service;

    @BeforeEach
    void setUp() {
        Clock fiveDaysLater = Clock.fixed(DEADLINE.plus(Duration.ofDays(5)), ZoneOffset.UTC);
        service = new ScoreService(log, deadlines, board, fiveDaysLater);
        when(deadlines.deadlineOf("T-7")).thenReturn(DEADLINE);
    }
```

How to read it:

* `@ExtendWith(MockitoExtension.class)` means "plug Mockito into this class."
  `@ExtendWith` is a JUnit annotation: it plugs in an **extension**, code
  that JUnit calls before and after each test. Before a test, the Mockito
  extension puts fresh mocks into the `@Mock` fields. After the test, it
  checks whether anything unneeded is left over; more on that below.
* `@Mock` means "make a mock of this type here."
* `@BeforeEach` marks a method JUnit runs before every test: shared setup
  in one place. `DEADLINE` is the same deadline constant.

Without the annotation, the `mock(…)` method makes a mock: `mock(SubmissionLog.class)`
returns the same thing. You'll see both ways.

⚠️ Online, you'll see tests with `@SpringBootTest` where `@Mock` fields
work without any `@ExtendWith`. `@SpringBootTest` marks a test that starts
the whole Spring application. That's Boot 2–3: there, Spring itself filled
in the `@Mock` fields. The sandbox runs Boot 4, and that's gone: without
`MockitoExtension` the field stays `null`, and the test fails the first time
it touches the mock.

### when … thenReturn: setting an answer

Read `when(deadlines.deadlineOf("T-7")).thenReturn(DEADLINE)` as an instruction:
"when asked for the deadline of task `T-7`, answer `DEADLINE`." Inside `when(…)`,
the call to the mock's method isn't a real one: Mockito remembers which
call is being set up. `when`, `verify`, and the rest are static Mockito methods.
They come into a test with `import static`, like `assertThat` (Article 2).

When asked something it has no answer for, a mock answers with "empty": `null`,
zero, `false`, an empty list, an empty `Optional`.

That last one is the sneakiest. Forget the `when` for `log`, and the service
gets an empty box and quietly takes the "not submitted" path. There's no
exception: the test goes red on a check, and you'll have to hunt for the cause.

The same thing written differently is `given(…).willReturn(…)` from `BDDMockito`:
that's how the Spring Boot documentation writes it. This series uses `when`.

### verify: checking a call

```java
@Test
void lateWithinDayIsRecordedAsHalf() {
    when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE.plus(Duration.ofHours(2))));

    service.grade("student-1", "T-7");

    verify(board).record("student-1", "T-7", 50);
}
```

`verify(board).record("student-1", "T-7", 50)` means "make sure `record`
was called on the board with these arguments, exactly once." Once is the
default; for a different number, pass it as the second argument:
`verify(board, times(2))`. A Mockito mock remembers its calls on its own,
like our `RememberingBoard`, only for any interface. If there was no call,
or the arguments were different, the test is red.

### ArgumentCaptor: catching an argument

```java
@Test
void onTimeIsRecordedAsFull() {
    when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE));
    ArgumentCaptor<Integer> recorded = ArgumentCaptor.forClass(Integer.class);

    service.grade("student-1", "T-7");

    verify(board).record(anyString(), anyString(), recorded.capture());
    assertThat(recorded.getValue()).isEqualTo(100);
}
```

**`ArgumentCaptor`** catches an argument. In `verify`, instead of a value,
there's `recorded.capture()`: Mockito saves whatever was passed, and
`getValue()` hands back what it saved, which you then check with AssertJ.
Only classes go in angle brackets, so the captor for an `int` is declared
as `Integer`. `anyString()` is a **matcher**: "any string."

⚠️ If even one argument is a matcher, all of them have to be matchers.
Mockito won't accept `record(anyString(), anyString(), 100)` and will throw
an error. Write `eq(100)`, the matcher for "exactly this value."

To be honest, the captor here is just for show: you could check the number
right in `verify`. You need one when the argument is an object the service
built itself: then you check it field by field.

### verifyNoInteractions and never()

```java
@Test
void earlyCheckTouchesNothing() {
    Clock threeHoursLater = Clock.fixed(DEADLINE.plus(Duration.ofHours(3)), ZoneOffset.UTC);
    service = new ScoreService(log, deadlines, board, threeHoursLater);
    when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.empty());

    Optional<Integer> score = service.grade("student-1", "T-7");

    assertThat(score).isEmpty();
    verifyNoInteractions(board);                            // the board wasn't touched at all
}
```

`verifyNoInteractions(board)` means "nothing at all was done with the board."
Another way to say the same thing:

```java
verify(board, never()).record(anyString(), anyString(), anyInt());
```

"`record` was never called with any arguments." Here `anyInt()` is the
matcher for "any `int`," and `never()` means "zero times." The difference
is that `verifyNoInteractions` forbids every method, while `never()` forbids
one named method. The board has only one method, so here they mean the same thing.

### Why the service is built by hand

In `earlyCheckTouchesNothing`, the service is rebuilt with a different clock.
The clock is a real object, not a mock: to change the time, you need a different clock.

Mockito's `@InjectMocks` annotation on the service field means "create the
service and plug the test's mocks into it." It won't do here, for two reasons.

First: `@InjectMocks` takes the longest constructor and fills it only with
mocks from the test. Whatever it doesn't find, it passes as `null`, and it
says nothing. The clock would be `null`. A "submitted" test on such a service
would pass: it never gets as far as the clock. But every "not submitted" test
would fail with a `NullPointerException`.

Second: an explicit `new ScoreService(…)` shows the dependencies. If the
service gets another neighbor, the test won't compile, and you find out
right away, not from a `null`. `@InjectMocks` is fine when every neighbor is a mock.

### Strict stubs

By default, `MockitoExtension` is strict: **strict stubs**. If a `when` in a
test is never used, the test fails with `UnnecessaryStubbingException`, even
when all the checks passed.

An unneeded `when` means the test thinks the code takes one road while it
actually takes another. Or it's a leftover from a rewrite that confuses the
reader. The cure is to delete the unneeded `when`. Strict mode also catches
a stubbed method being called with different arguments.

Mockito counts this for each test separately, `@BeforeEach` included.
That's why `setUp` holds only what every test needs: all three tests ask for
the deadline of `T-7`. If not every test needs an answer, move the `when`
into the tests that do. Mockito also has `lenient()`: "this stub is allowed
to go unused." But first ask yourself why it's in the test at all.

What strict mode doesn't catch is a question you never set an answer for at
all. The mock quietly answers "empty," like `log` above. You'll only see that
from a check on the result.

### Service tests in the real project

Service tests in the real project are built the same way. One service there
has five neighbors, among them a repository, a response mapper, and a notifier.
In the test, all five are mocks, and the service is built with `@InjectMocks`:
there's no clock among the neighbors. The service's answer comes from the
mapper's mock, so checking it only shows that the answer didn't get lost.

The important part shows up through a captor: the record the service built
itself and handed to the repository. The test pulls it out and checks its status
and other fields. The notifier returns nothing to the outside, so it gets a `verify`.

One more pattern from these tests is for `void` methods: the compiler won't
accept `when(…)` around such a call. The form for them is reversed:
`doThrow(exception).when(mock).method(…)`. On our board it would
look like this:
`doThrow(new RuntimeException()).when(board).record(anyString(), anyString(), anyInt())`.

Now the mock fails on recording. That's how you check that a loop over
records one at a time survives an error on the first and processes the second. And `never()`
in the neighboring test confirms that after an interrupted loop, the second
record was never reached.

---

## Part 4. What to replace and what to leave real

### State or calls

The hand-written board checked **state**: what the service returned and what
ended up on the board. `verify` checks **interaction**: which method was
called and with what. State doesn't care which path the service took to get
there, so a test like that survives rewrites. Interaction is what you need
when the result leaves the service and there's nothing else to look at:
a notification, a write to someone else's system. The rule is simple: if
there's a result, check the result; `verify` is for what goes outside.

Our board shows both approaches. By hand, we looked at what was on it,
and Mockito checked that it was called. For the board, both are right:
recording on it is the service's result. But `verify(deadlines).deadlineOf("T-7")`
would be unneeded: asking for the deadline isn't a result, it's a way of getting one.

### What not to replace

**`DeadlineScore`.** Pure logic, fast and with no neighbors. Replace it, and
the service test checks a rule you dictated to the mock yourself. It won't
notice a bug in the real rule. The real one costs nothing.

**Values**: `Instant`, `Duration`, `Optional`, strings, lists. Create them
for real.

**And don't repeat the implementation.** A test that retells the code puts
a `verify` on every call: `verify(deadlines).deadlineOf(…)`,
`verify(log).submittedAt(…)`, `verify(board).record(…)`. A test like that
breaks on a rewrite that doesn't change the behavior. The service starts
asking for the deadline twice, and `verify` expects exactly one call by
default: the test is red. The deadlines of all tasks start coming from one
shared query, `deadlineOf` isn't called at all, and the test is red again,
even though the score is the same.

And such a test proves little: that the code is written the way it's written.
It's the test that agrees with itself from Article 5, only built out of `verify`.

Replace the **boundaries**: whatever goes to the database, the network, the
clock, another service. Everything inside stays real.

The rate test from Article 5 got caught exactly this way: the repository
stub answered "three made it," and the test checked only the arithmetic.

🔑 **A stub answers what you told it to, and the test can't see what's
behind it.** So replace only what you can't use for real.

### A check that was checking the stub

In the browser part of the real project, there was a screen that had to
respond in a special way to one particular server response. The check was
written in a test file that starts the whole application: it seemed like
the right place. But at the top of that same file, the entire layer of requests to the server had been replaced with
a stub. And the response logic lived right inside that layer: in the test it
never ran at all.

The test failed, and that was lucky. If the expectation had been worded
a little differently, it would have been green even with the response logic
switched off entirely. The fix was to split the checks by layer, so that what's
being checked is always real. One test replaces only the browser's network
and checks that the request layer calls the handler. The other replaces the
request layer and checks that the screen responds to the call.

The rule from there: before you write a check, ask **whether the code
you're checking actually runs in this test**. If its layer is replaced,
you're checking the stub.

### A stub that answered everything

In another test in the same place, a server stub answered by request
address, and for an unknown one it quietly returned "nothing." The screen
showed its "couldn't load the data" message and still rendered: the test
was checking it in its error state instead of the normal one. When one
address was cut from the stub, eleven tests stayed green both with it and
without it.

Throwing an exception on an unknown address wasn't an option: the screen
would catch it, show the same error, and stay green. Instead, the stub started
**remembering** unknown requests, and after each test a check required the
list to be empty. Now a forgotten address names itself in the red report.
It's our `RememberingBoard`, turned the other way around:
a stub that speaks up loudly about the unexpected.

### A mock in Spring: @MockitoBean

The objects Spring creates and wires together are called **beans**, and the
whole running application with them is the **context**. In a test that starts
the context, the service gets its neighbor from Spring, not from your `new`.
There, `@MockitoBean` on a field replaces the bean with a Mockito mock.

Spring keeps ready contexts in a cache, but the set of replaced beans is
part of the cache key. Every new set means a new context and extra seconds.
So wherever you can, write a unit test without Spring, like everything in this article.

⚠️ Online, you'll see `@MockBean`. That's Boot 2–3; Boot 4 removed it.
In Boot 4 it's `@MockitoBean` from the
`org.springframework.test.context.bean.override.mockito` package.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. Why can't `ScoreService` be tested the same way as `DeadlineScore`,
   and what does a stub do in the test?
2. When can you write a stub as a lambda, and when do you need a class like
   `RememberingBoard`?
3. Why does the service take "now" from a `Clock`? What happens to the tests
   if you replace `clock.instant()` with `Instant.now()`?
4. The "submitted two hours late" test checks both the service's answer and
   the board. Which bug can only the board check see?
5. How does checking `board.records` differ from `verify(board).record(…)`?
   When do you choose which?
6. Why is the service in `ScoreServiceMockitoTest` built by hand in `@BeforeEach`
   rather than with `@InjectMocks`? What would `@InjectMocks` have done
   with the clock?
7. All the checks passed, but the test failed with `UnnecessaryStubbingException`.
   What does that mean, and what do you do?
8. Why shouldn't you replace `DeadlineScore`? And what's wrong with a test that
   puts a `verify` on every call in the implementation?

---

## What's next

The next article in the series is a test with a real database. The `ScoreBoard`
we replaced today gets a real implementation. And we'll see what only the
database catches: a repeated score, a score outside the rules, a bug in the SQL.

## Sources

* [Mockito: the Mockito class javadoc](https://www.javadoc.io/static/org.mockito/mockito-core/5.24.0/org.mockito/org/mockito/Mockito.html):
  sections 0.3 (the agent on Java 21+), 1–4 (mocks, `when`,
  matchers, `verify`, `never`), 12 (`doThrow`), 15 (`ArgumentCaptor`);
* [Mockito: UnnecessaryStubbingException](https://www.javadoc.io/static/org.mockito/mockito-core/5.24.0/org.mockito/org/mockito/exceptions/misusing/UnnecessaryStubbingException.html):
  what an unnecessary stub is and why it's better to delete it;
* [Java 25: java.time.Clock](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html):
  why the clock is an object, and what `Clock.fixed` is;
* [Spring Framework: @MockitoBean and @MockitoSpyBean](https://docs.spring.io/spring/reference/testing/annotations/integration-spring/annotation-mockitobean.html):
  a mock in place of an object in a test with Spring;
* [Spring Framework: Context Caching](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html):
  what makes up the cache key, and why a new set of mocks means a new
  context.

---

## The full example, with imports

The learning example lives in the `testy` sandbox from Article 1. By this
article, the sandbox has everything from Articles 1–5: `DeadlineScore` and `Attempts`,
their tests, and the JaCoCo plugin in `pom.xml`. The new files go in the
`example.testy.score` package, next to `DeadlineScore`, which doesn't change.
This article adds no dependencies: Mockito comes
with `spring-boot-starter-test`.

```java
// src/main/java/example/testy/score/SubmissionLog.java
package example.testy.score;

import java.time.Instant;
import java.util.Optional;

/** Where it's recorded when a task was submitted. */
public interface SubmissionLog {

    /** When the student submitted the task; empty if they haven't. */
    Optional<Instant> submittedAt(String studentId, String taskKey);
}
```

```java
// src/main/java/example/testy/score/Deadlines.java
package example.testy.score;

import java.time.Instant;

/** Task deadlines. */
public interface Deadlines {

    Instant deadlineOf(String taskKey);
}
```

```java
// src/main/java/example/testy/score/ScoreBoard.java
package example.testy.score;

/** Where scores are recorded. */
public interface ScoreBoard {

    void record(String studentId, String taskKey, int score);
}
```

```java
// src/main/java/example/testy/score/ScoreService.java
package example.testy.score;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;

/** Grades a task: takes the submission time and the deadline, computes the score, records it. */
public class ScoreService {

    private final SubmissionLog log;
    private final Deadlines deadlines;
    private final ScoreBoard board;
    private final Clock clock;                                  // "now" comes only from here

    public ScoreService(SubmissionLog log, Deadlines deadlines, ScoreBoard board, Clock clock) {
        this.log = log;
        this.deadlines = deadlines;
        this.board = board;
        this.clock = clock;
    }

    /**
     * Grade the task. Empty means it's too early to grade: the task hasn't
     * been submitted yet, and the time for half the score hasn't run out.
     */
    public Optional<Integer> grade(String studentId, String taskKey) {
        Instant deadline = deadlines.deadlineOf(taskKey);
        Optional<Instant> submittedAt = log.submittedAt(studentId, taskKey);

        if (submittedAt.isEmpty()) {
            Instant lastChance = deadline.plus(DeadlineScore.GRACE);
            if (clock.instant().isAfter(lastChance)) {          // too late to submit for half
                board.record(studentId, taskKey, DeadlineScore.NONE);
                return Optional.of(DeadlineScore.NONE);
            }
            return Optional.empty();                            // not too late yet: leave it alone
        }

        int score = DeadlineScore.score(deadline, submittedAt.get());
        board.record(studentId, taskKey, score);
        return Optional.of(score);
    }
}
```

```java
// src/test/java/example/testy/score/ScoreServiceTest.java
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/** Stubs written by hand, no libraries. */
class ScoreServiceTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    /** A board that remembers what was recorded on it. */
    static class RememberingBoard implements ScoreBoard {

        final List<String> records = new ArrayList<>();

        @Override
        public void record(String studentId, String taskKey, int score) {
            records.add(studentId + " " + taskKey + " " + score);
        }
    }

    private final RememberingBoard board = new RememberingBoard();
    private final Deadlines deadlines = taskKey -> DEADLINE;                     // one deadline for all tasks

    private ScoreService serviceAt(Instant now, SubmissionLog log) {
        return new ScoreService(log, deadlines, board, Clock.fixed(now, ZoneOffset.UTC));
    }

    @Test
    void submittedLateWithinDayGetsHalf() {
        SubmissionLog log = (studentId, taskKey) -> Optional.of(DEADLINE.plus(Duration.ofHours(2)));
        ScoreService service = serviceAt(DEADLINE.plus(Duration.ofDays(5)), log);

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).contains(50);
        assertThat(board.records).containsExactly("student-1 T-7 50");
    }

    @Test
    void notSubmittedYetIsNotGraded() {
        SubmissionLog log = (studentId, taskKey) -> Optional.empty();
        ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(3)), log);   // 24 hours not up yet

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).isEmpty();
        assertThat(board.records).isEmpty();
    }

    @Test
    void notSubmittedAfterGraceGetsNothing() {
        SubmissionLog log = (studentId, taskKey) -> Optional.empty();
        ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(25)), log);  // 24 hours are up

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).contains(0);
        assertThat(board.records).containsExactly("student-1 T-7 0");
    }
}
```

```java
// src/test/java/example/testy/score/ScoreServiceMockitoTest.java
package example.testy.score;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** The same stubs, made by Mockito. */
@ExtendWith(MockitoExtension.class)
class ScoreServiceMockitoTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Mock
    private SubmissionLog log;

    @Mock
    private Deadlines deadlines;

    @Mock
    private ScoreBoard board;

    private ScoreService service;

    @BeforeEach
    void setUp() {
        Clock fiveDaysLater = Clock.fixed(DEADLINE.plus(Duration.ofDays(5)), ZoneOffset.UTC);
        service = new ScoreService(log, deadlines, board, fiveDaysLater);
        when(deadlines.deadlineOf("T-7")).thenReturn(DEADLINE);
    }

    @Test
    void lateWithinDayIsRecordedAsHalf() {
        when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE.plus(Duration.ofHours(2))));

        service.grade("student-1", "T-7");

        verify(board).record("student-1", "T-7", 50);
    }

    @Test
    void onTimeIsRecordedAsFull() {
        when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE));
        ArgumentCaptor<Integer> recorded = ArgumentCaptor.forClass(Integer.class);

        service.grade("student-1", "T-7");

        verify(board).record(anyString(), anyString(), recorded.capture());
        assertThat(recorded.getValue()).isEqualTo(100);
    }

    @Test
    void earlyCheckTouchesNothing() {
        Clock threeHoursLater = Clock.fixed(DEADLINE.plus(Duration.ofHours(3)), ZoneOffset.UTC);
        service = new ScoreService(log, deadlines, board, threeHoursLater);
        when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.empty());

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).isEmpty();
        verifyNoInteractions(board);                            // the board wasn't touched at all
    }
}
```

Try it yourself:

1. `./mvnw test`: everything is green, `Tests run: 24` (the 18 tests from
   Articles 1–5 plus the six new ones). The `WARNING` lines about the agent from
   Part 3 don't break the build.
2. Delete the line `board.record(studentId, taskKey, score);` in `ScoreService`
   after the score is computed. Red: `submittedLateWithinDayGetsHalf`, on
   the board check, while the answer is correct; `lateWithinDayIsRecordedAsHalf`
   and `onTimeIsRecordedAsFull`, because there was no call. Put the line back.
3. Delete the line `board.record(studentId, taskKey, DeadlineScore.NONE);`
   in the "24 hours have passed" branch. `notSubmittedAfterGraceGetsNothing` goes red:
   the zero in the answer is correct, but the board is empty. Put the line back.
4. Replace `clock.instant()` with `Instant.now()`. It's already later than
   October 13, 2026, 21:00 UTC, so `notSubmittedYetIsNotGraded`
   and `earlyCheckTouchesNothing` are red. Before that moment, the red one
   would have been `notSubmittedAfterGraceGetsNothing`. Put it back.
5. Add an unneeded `when` to `lateWithinDayIsRecordedAsHalf`, for example,
   an answer for `"student-2"`. The check passes, but the test fails
   with `UnnecessaryStubbingException`. Remove it.

Each of the six tests went red at least once on a real bug.
And not one of them had to start a database or wait 24 hours.
