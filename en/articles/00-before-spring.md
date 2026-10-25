# What to know before Spring

> "From Java to Spring Boot" · Article 0 · 20–25 min read
>
> **Who it's for.** You know Java from a course: classes, methods, `if`,
> loops, lists. You've never seen a Spring application. That's enough:
> this article starts right there.
>
> **What's inside.** Three things you'll run into on your very first task
> at work: a bit of Java your course may have skipped; Maven, the tool that
> builds the project; and table-driven tests, a way to check ten cases with
> one test.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why we don't start with Spring

Spring is a tool that does a lot for you: it creates objects, wires them
together, starts a web server, talks to the database. As long as
everything works, that's convenient. When something breaks, you get
a hundred lines of error about things you never wrote.

You can only make sense of an error like that if you understand what lies
underneath Spring: plain Java, the build, and tests. That's why
a newcomer's first tasks on the team involve no Spring at all: records,
enums, validation, and tests for them.

The running example is parsing a task key. On the task board, every task
has a key: the project's letters and a number. In the learning project
"Game Day", which runs through the whole series, keys look like `GD-130`.

---

## Part 1. The Java you'll meet in your first tasks

### A record is a class that just holds data

Say you need to store a task number. As an ordinary class, that means
a field, a constructor, an accessor, plus `equals`, `hashCode`, and
`toString`: forty-odd lines for a single number. And you can make
a mistake in any of them.

A **record** is a short way of telling Java: "this is just data, do the
rest yourself."

```java
public record TaskKey(int number) {}
```

One line, and here's what you get for free:

* a constructor: `new TaskKey(130)`;
* an accessor: `key.number()`;
* `equals` and `hashCode`: two records with the same fields are equal,
  so `new TaskKey(130).equals(new TaskKey(130))` returns `true`;
* `toString`: prints as `TaskKey[number=130]`.

⚠️ The accessor has the same name as the field: `number()`, not
`getNumber()`. Older tutorials use `get…` everywhere; records don't have it.

A record is **immutable**: once created, its field can't change. That
sounds like a limitation, but it's really protection. You can pass an object like that anywhere without worrying: nobody along the way can change it.

**Validation on creation.** A task number is never zero or negative.
This check goes in the **compact constructor**, a record constructor
with no parameter list:

```java
public record TaskKey(int number) {

    public TaskKey {                         // compact constructor: no parameter list
        if (number < 1) {
            throw new IllegalArgumentException("task number must be at least 1, got " + number);
        }
    }
}
```

Where does `number` come from inside? It's the parameter from the record
header, `record TaskKey(int number)`, and you don't repeat it. If the
check passes, Java assigns the value to the field after the constructor.

Now `new TaskKey(0)` simply fails: Java throws an exception.
🔑 That's the key idea: **an invalid object should never exist at all**.
Then you won't have to catch it later, in ten other places.

### An enum with a code

An **enum** is a type with a fixed set of values known in advance. For
example, task areas on the board: Backend, DB, Infra, Test, Docs,
Monitoring. There are no others.

Often a value has an "external name": how it's written in JSON (the text
format programs use to exchange data), in the database, or on the board.
And it doesn't match the Java name. It's kept in a field:

```java
public enum Area {
    BACKEND("Backend"), DB("DB"), INFRA("Infra"),
    TEST("Test"), DOCS("Docs"), MONITORING("Monitoring");

    private final String code;               // how the area is written outside Java

    Area(String code) {
        this.code = code;
    }

    public String code() {
        return code;
    }

    public static Area fromCode(String code) {
        for (Area area : values()) {         // values(): all values, in order
            if (area.code.equals(code)) {
                return area;
            }
        }
        throw new IllegalArgumentException("unknown area: " + code);
    }
}
```

How to read it: `BACKEND("Backend")` is a value and, at the same time,
a call to the constructor `Area(String code)` with the argument
`"Backend"`. That's how each value gets its own `code`. The semicolon
after the list of values is required: ordinary class code follows.

Why not the built-in `Area.valueOf("Backend")`? It looks for the **Java
name** `BACKEND`, letter for letter, and fails on `"Backend"`. A separate
code decouples the two worlds: you can rename a value in Java, and the
JSON, the database, and the board won't notice.

What to do with an unknown code (throw an exception or silently skip it)
depends on the task. In the real project you'll see both, and the task
description always says which.

### Exceptions: checked and unchecked

Java has two kinds of exceptions:

* **checked**: subclasses of `Exception`, except the `RuntimeException`
  branch. The compiler forces you to either catch them (`try/catch`) or
  declare them (`throws`) in every method they pass through;
* **unchecked**: subclasses of `RuntimeException`. The compiler doesn't
  insist.

In the real project, errors are **unchecked**. Here's why: an error like
"an invalid number came in" can't be fixed where it's noticed. It has to
travel up to the place that knows what to tell the user. In a web
service that's one place, an error handler shared by the whole
application. With checked exceptions, every method along the way would
have to be decorated with `throws`.

⚠️ Later, in tasks involving JSON, you'll find examples online that use
Jackson (the JSON library) with `catch (JsonProcessingException e)`.
That's Jackson 2, where errors are checked. Spring Boot 4 brings Jackson 3,
and its errors are unchecked.

### A factory method instead of a constructor

The key arrives as a string: `"GD-130"`. It's more convenient to turn it
into a `TaskKey` not with a constructor but with a static method that has
a clear name, a **factory method**:

```java
TaskKey key = TaskKey.parse("GD-130");
```

The name `parse` says exactly what happens. And before creating the
object, you can prepare the string and check it:

```java
public static TaskKey parse(String raw) {
    if (raw == null) {
        throw new IllegalArgumentException("key is missing");
    }
    String text = raw.strip();                   // strip spaces at both ends
    if (!text.startsWith("GD-")) {
        throw new IllegalArgumentException("key must start with GD-: " + raw);
    }
    String digits = text.substring(3);           // everything after "GD-"
    if (!digits.matches("[1-9][0-9]*")) {        // digits only, the first one not zero
        throw new IllegalArgumentException("GD- must be followed by digits, no leading zero: " + raw);
    }
    return new TaskKey(Integer.parseInt(digits));
}
```

The string `"[1-9][0-9]*"` is a **regular expression**, a compact way to
write a pattern. Square brackets mean "one character from the set": `[1-9]`
is one digit from 1 to 9. The asterisk means "the previous thing any number
of times, even zero": `[0-9]*` is any number of digits after that. The `matches`
method checks the **whole** string; it doesn't search for a piece inside it.

In short: "the first digit from 1 to 9, then only digits." So `GD-0130`
won't pass: by the board's rules, numbers are written without leading
zeros.

---

## Part 2. Maven: what builds the project

### What work it does

Just to run the tests, you need to:

1. download libraries (JUnit, AssertJ, Jackson) in the right versions;
2. download what *they* need to work, because they have dependencies of
   their own too;
3. compile your code, then the tests;
4. run the tests and produce a report.

By hand, that's hours of work and dozens of places to go wrong. **Maven**
does all of it with one command, from a description of the project.

### pom.xml: the project's ID card

The description lives in `pom.xml` at the root of the repository. Here's
the important part:

```xml
<parent>                                      <!-- "parent": where versions come from -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>4.1.0</version>
</parent>

<groupId>example</groupId>                   <!-- who owns the project -->
<artifactId>task-keys</artifactId>           <!-- which project -->
<version>0.1.0-SNAPSHOT</version>            <!-- version; SNAPSHOT means "work in progress" -->

<dependencies>
    <dependency>                               <!-- library for JSON -->
        <groupId>tools.jackson.core</groupId>
        <artifactId>jackson-databind</artifactId>
    </dependency>
    <dependency>                               <!-- everything for tests: JUnit, AssertJ and more -->
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>                    <!-- needed only by tests -->
    </dependency>
</dependencies>
```

Four terms you'll see all the time:

* **coordinates**: `groupId`, `artifactId`, `version`. Like a book's
  author, title, and edition: with them you can find any library
  unambiguously;
* **dependency**: someone else's library that the project uses;
* **`scope test`**: the library is needed only by tests and won't end up
  in the finished application;
* **starter**: a set of libraries bundled as one dependency. Add
  `spring-boot-starter-test` and you get everything for testing at once.

Notice that the dependencies have **no versions**. The "parent" fills
them in: the `<parent>` block at the top. It knows which library versions
have been tested together.

"But isn't this article about not needing Spring yet?" Right: for now,
Spring Boot in the project is just a quartermaster that picks library
versions. The code of the first tasks doesn't use Spring itself.

⚠️ Online, Jackson is added with the `groupId`
`com.fasterxml.jackson.core`. That's Jackson 2. Jackson 3 uses
`tools.jackson.core`.

### Where libraries come from

From **Maven Central**, a huge shared library repository. On the first
build, Maven downloads everything it needs to a folder on your machine,
`~/.m2/repository`, where `~` is your home folder (on Windows,
`C:\Users\<name>`). After that it takes them from there. That's why the
first build is slow and the next ones are fast.

### One command, many steps

A build has **phases**, steps in order. The main ones:

| phase | what it does |
|---|---|
| `compile` | compiles your code |
| `test` | compiles and runs the tests |
| `package` | builds the finished application, a `.jar` file |
| `verify` | final checks |

🔑 Ask for a phase, and Maven runs all the phases before it too. `verify`
means compile, test, package, and check, all at once.

In the real project, `verify` also checks **test coverage**. A tool
called JaCoCo does that; more on it at the end of the article. If
coverage is below the threshold, the build fails. That's why, before
a **pull request** (a request to merge your changes into the shared
code), you run exactly this:

```bash
./mvnw verify
```

`BUILD SUCCESS` in green at the end means you're ready to submit.

### mvnw: Maven that downloads itself

`mvnw` is a **wrapper**: a small script in the repository. It downloads
the right version of Maven and runs it. You don't need to install Maven
separately, and everyone on the team has the same one. In Git Bash on
Windows the command is the same, `./mvnw verify`; in the regular Windows
command prompt, it's `mvnw.cmd verify`.

### The target folder

After a build, a `target` folder appears in the project. It holds
everything Maven produced: compiled classes, reports, the finished `.jar`.
It's **build output, not source code**: it doesn't go into git, and
`./mvnw clean` deletes it, so the next build starts from a clean slate.

### Team rule: a mid-level developer adds dependencies

If a task needs a library, either it's already in `pom.xml` or the task
description says so explicitly. A new dependency is a decision: application
size, security, version compatibility. A mid-level developer, someone with
experience, makes it and writes down the reason.

---

## Part 3. Table-driven tests

### A test is a program that checks a program

A **unit test** is a small method that calls your code with known data and
compares the result to what's expected. A "unit" here is a small piece of
the program: one class or one method.

In courses, you often check code by hand: write a `main`, run it, eyeball the
output. At work nobody does that: there are hundreds of checks, and they
have to run after every change. Two tools handle this. Both are already in
the project, brought in by the `spring-boot-starter-test` starter from
Part 2.

**JUnit** is the most widely used testing library in Java. You write test
methods, and JUnit finds them and runs them one by one, with no `main`
needed. After the run, it reports which tests passed, which failed, and
why. You can run tests two ways: with `./mvnw test` (Maven calls JUnit in
the `test` phase) or with the green triangle next to the test in your IDE.

**AssertJ** is an assertion library. You could check "the result equals
130" with JUnit's own tools, but an AssertJ assertion reads as plain
English: `assertThat(number).isEqualTo(130)`. And when an assertion fails,
AssertJ tells you what was expected and what came instead:

```
expected: 130
 but was: 13
```

Tests live separately from the code, in `src/test/java`, in the same
package as the class under test. The test class name ends in `Test`: that
suffix is how Maven finds them.

```java
class TaskKeyTest {

    @Test                                         // "this is a test": JUnit will find and run it
    void parsesKey() {
        TaskKey key = TaskKey.parse("GD-130");    // 1. call the code
        assertThat(key.number()).isEqualTo(130);  // 2. check: assert that the number is 130
    }
}
```

`@Test` is an **annotation**: a marker above a method. It's read not by
Java itself but by a tool, here JUnit: "this method is a test, run it."
Annotations will be everywhere, especially in Spring.

If `parse` returns something other than 130, the test turns red and says
what came instead of what was expected.

The short examples in this article have no `import` lines; otherwise each
one would double in size. Where `@Test`, `assertThat`, and the rest come
from is shown in the full example at the end.

### The problem: too many cases

Look at how much there is to check for a single `parse`:

| input | result |
|---|---|
| `GD-130` | 130 |
| `GD-130` with spaces at both ends | 130 |
| `GD-1` | 1 |
| `gd-130`: lowercase | error |
| `GD-0130`: leading zero | error |
| `GD-`: no number | error |
| `130`: no prefix | error |
| `GD-12a`: letter in the number | error |
| `null`: no key at all | error |

Nine cases. Nine nearly identical methods is copy-paste, and copy-paste
breeds mistakes: you change one place and forget the other.

### The solution: one test, many rows

A **parameterized test** is a test that JUnit runs many times,
substituting a new row of data each time:

```java
@ParameterizedTest(name = "{0} → {1}")           // name: how each row appears in the report
@CsvSource(delimiter = '|', textBlock = """
        GD-130     | 130
        ' GD-130 ' | 130
        GD-1       | 1
        """)
void parsesValidKeys(String raw, int expected) {
    assertThat(TaskKey.parse(raw).number()).isEqualTo(expected);
}
```

How to read it:

* `@CsvSource`: data as a table. Each row is one test run;
* the triple quotes `"""` at the start and end make a **text block**,
  a Java string you can write across several lines. Very handy for tables;
* `delimiter = '|'`: the column separator. The first column goes into the
  `raw` parameter, the second into `expected`. JUnit converts the text
  `130` from the table into a number itself, because the parameter is
  declared as `int`;
* the single quotes in `' GD-130 '` keep the spaces at both ends. Without
  them, JUnit trims the spaces, and you won't test what you meant to;
* `name = "{0} → {1}"`: how each run is labeled in the report. `{0}`
  becomes the first column and `{1}` the second, so you get
  `"GD-130" → "130"`. JUnit 6 adds the quotes itself, around `130` too:
  the label uses the text from the table as it was before conversion to
  a number. On the plus side, the report shows spaces at the edges:
  `" GD-130 " → "130"`.

Error rows go in a separate test. `assertThatThrownBy` means "assert that
this throws an exception."

Note the `() -> TaskKey.parse(raw)`. That's a **lambda**: a piece of code
passed around as a value without running it right away. Why? If you wrote
just `TaskKey.parse(raw)`, the exception would fly out before the check
and crash the test itself. This way, AssertJ runs the piece of code itself,
catches the exception, and checks it. `IllegalArgumentException.class` is
how you name the exception class you expect.

```java
@ParameterizedTest(name = "{0} → rejected")
@ValueSource(strings = {"gd-130", "GD-0130", "GD-", "130", "GD-12a"})
void rejectsBadKeys(String raw) {
    assertThatThrownBy(() -> TaskKey.parse(raw))
            .isInstanceOf(IllegalArgumentException.class);
}

@Test
void rejectsNull() {
    assertThatThrownBy(() -> TaskKey.parse(null))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("missing");
}
```

`null` gets its own test because `@ValueSource` doesn't accept it.

🔑 **This is how every junior task in the real project works:** the task
description contains an "input → result" table. Each row of the table is
a separate case in the tests: a row in `@CsvSource` or `@ValueSource`, or,
if it doesn't fit there (like `null`), a separate test. Our table has nine
rows, and all nine are checked. Reviewers look at this first. How to
choose rows for such a table is covered in
[Article 4, "Which cases to test"](https://hammerhall.io/en/ledger/testing/4-which-cases)
of the "From Red to Green" series.

💡 The table in the task is the minimum, not the ceiling. What happens
with the key `GD-99999999999`? The number doesn't fit in an `int`, and
`Integer.parseInt` throws a `NumberFormatException`. Add that row to
`rejectsBadKeys` and the test passes: it's a subclass of
`IllegalArgumentException`. But the message is low-level and says nothing
about task keys: `For input string: "99999999999"`. If you find an edge case like that, mention it in your pull request.

### Coverage: what the tests actually ran through

The tests are green, so everything is checked? Not necessarily. You can
write five tests that all take the same path and never touch half the
code. To see that, you need one more tool.

**JaCoCo** (short for Java Code Coverage) watches the tests while they run
and marks every line of your code that execution passed through. Like
a highlighter running over a text: after the run, you can see which lines
the tests went through and which they never touched.

JaCoCo rarely shows up in course projects, but at work you'll seldom do
without it. The team agrees on a threshold, say "at least 80% of lines
covered," and a build that falls short isn't accepted. That keeps code
nobody has ever run from sneaking into the project. Why coverage alone isn't proof is explained in
[Article 5, "A test that checks nothing"](https://hammerhall.io/en/ledger/testing/5-test-that-checks-nothing)
of the "From Red to Green" series.

You don't need to install JaCoCo separately: it's configured in `pom.xml`
as a **plugin**, an add-on that Maven downloads and runs itself. In the
`test` phase, JaCoCo watches the tests and collects a report; in the
`verify` phase, it compares coverage to the threshold. Thresholds in the
real project:

* the whole project: at least 80% of lines and 70% of branches, or the
  build fails;
* your new classes: **100% of lines and branches**. That's a requirement
  for every task.

**How to read the report.** After `./mvnw verify`, open
`target/site/jacoco/index.html` in a browser. There's a list of packages
with percentages; click a package, then a class, and you'll see your code
colored line by line:

* a green line: the tests executed it;
* red: no test executed it;
* yellow: partially executed, usually a condition where the tests took
  only one of the two branches.

⚠️ Red here doesn't mean "a test failed"; it means "the tests never got
here."

**Branches.** Every `if` creates two paths: the condition was true or it
wasn't. The `if` is fully covered only if the tests have taken both paths. Next to
such lines, JaCoCo draws a diamond in the same color: green means both
paths were taken, yellow one, red neither.

Our example shows why this matters. All the tests above are green, but in
the report the `number < 1` check in the constructor will be yellow (the
branch is half covered), and the `throw` line under it red. You can't
reach it through `parse`: the pattern won't let a zero through. So you
need one more test, directly on the constructor:

```java
@Test
void rejectsZero() {
    assertThatThrownBy(() -> new TaskKey(0))
            .isInstanceOf(IllegalArgumentException.class);
}
```

Add the test, run `./mvnw verify` again, and the line turns green.

⚠️ Coverage is not proof. Here's a test that provides coverage and checks
nothing:

```java
@Test
void looksCoveredButChecksNothing() {
    TaskKey.parse("GD-130");    // called it and didn't check the result
}
```

The lines are green, but if `parse` starts returning the wrong number, the
test will still pass. JaCoCo sees where the tests **went**, but not what
they **checked** there. That's why a reviewer looks not only at the
percentages but at what the test checks.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. How does a record differ from an ordinary class? Name three things it
   gives you for free.
2. Why does the `Area` enum need a separate `code` when there's
   `Area.valueOf(...)`?
3. Why are exceptions unchecked in the real project?
4. What does `./mvnw verify` do? Why do you need exactly that before
   a pull request, and not `./mvnw test`?
5. Where does Maven keep downloaded libraries, and why is the second build
   faster than the first?
6. The task's table has seven rows. How many cases should the tests check,
   and where does the `null` row go?
7. What does JaCoCo show, and what can't it show?
8. Coverage is 100%, yet there's a bug in the code. How is that possible?

---

## What's next

Article 1, "Why Spring." We'll write three objects that depend on each
other, wire them up by hand, and see what work Spring takes over.

## Sources

* [JEP 395: Records](https://openjdk.org/jeps/395): records as the
  authors of Java designed them;
* [Maven: Introduction to the Build Lifecycle](https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html):
  build phases;
* [JUnit: Parameterized Classes and Tests](https://docs.junit.org/6.0.3/writing-tests/parameterized-classes-and-tests.html):
  `@CsvSource`, `@ValueSource`, and the other data sources;
* [AssertJ](https://assertj.github.io/doc/): every assertion there is;
* [JaCoCo: Coverage Counters](https://www.jacoco.org/jacoco/trunk/doc/counters.html):
  what exactly counts as a line and a branch.

---

## The full example, with imports

A learning example. You can build it in any Maven project that has JUnit
and AssertJ. The easiest is a skeleton project generated at start.spring.io;
Article 1 shows how to create one. These are the complete files: what goes
in `src/main/java`, what goes in `src/test/java`, and where `@Test` and
`assertThat` come from. `import static` brings in a class's static
methods, so after it you write `assertThat(...)` without the class name in
front.

```java
// src/main/java/example/TaskKey.java
package example;

public record TaskKey(int number) {

    public TaskKey {
        if (number < 1) {
            throw new IllegalArgumentException("task number must be at least 1, got " + number);
        }
    }

    public static TaskKey parse(String raw) {
        if (raw == null) {
            throw new IllegalArgumentException("key is missing");
        }
        String text = raw.strip();
        if (!text.startsWith("GD-")) {
            throw new IllegalArgumentException("key must start with GD-: " + raw);
        }
        String digits = text.substring(3);
        if (!digits.matches("[1-9][0-9]*")) {
            throw new IllegalArgumentException("GD- must be followed by digits, no leading zero: " + raw);
        }
        return new TaskKey(Integer.parseInt(digits));
    }
}
```

```java
// src/test/java/example/TaskKeyTest.java
package example;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class TaskKeyTest {

    @ParameterizedTest(name = "{0} → {1}")
    @CsvSource(delimiter = '|', textBlock = """
            GD-130     | 130
            ' GD-130 ' | 130
            GD-1       | 1
            """)
    void parsesValidKeys(String raw, int expected) {
        assertThat(TaskKey.parse(raw).number()).isEqualTo(expected);
    }

    @ParameterizedTest(name = "{0} → rejected")
    @ValueSource(strings = {"gd-130", "GD-0130", "GD-", "130", "GD-12a"})
    void rejectsBadKeys(String raw) {
        assertThatThrownBy(() -> TaskKey.parse(raw))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsNull() {
        assertThatThrownBy(() -> TaskKey.parse(null))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("missing");
    }

    @Test
    void rejectsZero() {
        assertThatThrownBy(() -> new TaskKey(0))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
```
