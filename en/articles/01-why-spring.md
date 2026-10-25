# Why Spring

> "From Java to Spring Boot" · Article 1 · 30 min read
>
> **Who it's for.** You've read Article 0: records, Maven, tests with JUnit
> and AssertJ. You still haven't seen Spring, and that's fine: this
> article starts with plain Java.
>
> **What's inside.** Three things: why an object receives what it needs
> through its constructor instead of creating it itself; how to test such
> a class without Spring; and what the Spring container does (beans,
> `@Component`, `@Configuration`, and `@Bean`) and why there's one
> instance of a bean per application.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why Spring

In courses, `main` creates all of a program's objects: a couple of lines
with `new`, and you're done. A real project has hundreds of classes, and
many of them need each other. Take the clock, an object you ask for the
time (more on it below). Retry logic, the scheduler, and metrics will all need it,
and they all need the same one.

Who creates all these objects, and in what order? How do you swap one of
them out in a test? Spring takes over this work. To understand what it does, and why it sometimes fails on startup, we'll do its job by hand once and then let Spring do the wiring. By the end of the article you'll
understand every word in the phrase "the application clock is a `Clock`
bean."

**The series' running example is the Game Day journal.** Game Day is
a team drill: the team lead attacks the **staging environment**, a copy
of the service used for testing and drills. On-call engineers spot
incidents, and mid-level developers fix them. The journal accepts an
incident, say "broker is not responding," and notifies whoever is on call
right now. It's a learning example. Later the journal will learn to store
incidents in a database and serve them over the network.

---

## Part 1. Wiring by hand

### The journal's three helpers

The journal needs three things: to find out who's on call, to notify
them, and to know what time it is, so it can record when the incident was
detected. `DutyRoster` handles the first and `ConsoleNotifier` the
second; for now the notifier just prints to the console.

```java
public class DutyRoster {

    private final String dutyName;      // final: the field is set once, in the constructor, and never changes

    public DutyRoster(String dutyName) {
        this.dutyName = dutyName;       // in this learning example, one person is on call for the whole game
    }

    public String currentDuty() {
        return dutyName;
    }
}
```

```java
public class ConsoleNotifier {

    public void send(String dutyName, String text) {
        System.out.println("[notification] " + dutyName + ": " + text);   // for now, just to the console
    }
}
```

For time, two classes from the `java.time` package are enough.
**`Instant`** is a moment in time: a point on the timeline, with no time
zone. It prints like this: `2026-10-05T09:15:00Z`, where `Z` means UTC,
Coordinated Universal Time, with no time zone offset and no daylight saving time.
**`Clock`** is a clock: an object you ask "what time is it?";
`clock.instant()` returns an `Instant`.

There's also `Instant.now()`: "now" straight from the system. Why
a separate object, then? That will become clear in Part 2.

Now the journal itself:

```java
public class IncidentLog {

    private final DutyRoster roster;
    private final ConsoleNotifier notifier;
    private final Clock clock;

    public IncidentLog(DutyRoster roster, ConsoleNotifier notifier, Clock clock) {
        this.roster = roster;                         // everything it needs came from outside
        this.notifier = notifier;
        this.clock = clock;
    }

    public void add(String title) {
        Instant detectedAt = clock.instant();         // ask the clock for "now"
        String dutyName = roster.currentDuty();       // who's on call
        notifier.send(dutyName, title + " — detected at " + detectedAt);
    }
}
```

The journal can't store incidents yet; it only notifies.

As in Article 0, the short examples have no `import` lines, and `…` in
code marks an unchanged piece that was left out. The full files are at the
end of the article. Where to run the code is in Part 3: there the journal
gets its own project.

### Wiring in main

Everything an object can't work without is called its **dependencies**.
The journal has three: the duty roster, the notifier, and the clock. You
know the word from `pom.xml`, but there it means a library the project
needs; here it means an object another object needs.

Let's wire up the journal:

```java
public class HandMadeApp {

    public static void main(String[] args) {
        DutyRoster roster = new DutyRoster("duty-1");                 // 1. first, the ones that need nothing
        ConsoleNotifier notifier = new ConsoleNotifier();
        Clock clock = Clock.systemUTC();                              //    a real clock, time in UTC
        IncidentLog log = new IncidentLog(roster, notifier, clock);   // 2. then the one that needs them

        log.add("Broker is not responding");
    }
}
```

In the console (your time will differ):

```
[notification] duty-1: Broker is not responding — detected at 2026-10-05T09:15:03.512704831Z
```

It works. But this `main` has four problems that will become big ones as
the application grows.

### Where it hurts

**1. Creation order.** Here there are four lines, and the order is
obvious. In a real project there are hundreds of objects, and keeping
track of the order is up to you. Give the journal a fourth dependency, and
you have to edit `main` and every place the journal is created with `new`.

**2. One instance for everyone.** A real notifier holds a connection to
a chat or email server: it's created once and everyone uses it. In `main`,
that means threading one object into every constructor by hand. And if
someone deep in the code writes their own `new ConsoleNotifier()`, there will
be two instances, and nobody will notice.

**3. Substitution.** The journal's constructor takes a `ConsoleNotifier` and nothing else.
How do you test that the on-call engineer got notified? Read the console?
And on staging you'd want notifications in chat; locally, in the console.
Right now that would mean rewriting the journal itself.

**4. Who knows the settings.** The on-call name, where to send
notifications, which clock: `main` decides all of it. When the notifier
gets a chat address and a key, and the game gets a duration and a stop
word, all of that will land in `main` too, next to the `new` calls.

---

## Part 2. Dependencies come from outside

### Constructor injection

Look at the journal's constructor again: it doesn't create the roster, the
notifier, or the clock; it receives them ready-made. It could be done
differently:

```java
public class IncidentLog {

    private final DutyRoster roster = new DutyRoster("duty-1");       // decides for itself who's on call,
    private final ConsoleNotifier notifier = new ConsoleNotifier();   // and picks where to send notifications

    public void add(String title) {
        Instant detectedAt = Instant.now();                           // "now", straight from the system
        notifier.send(roster.currentDuty(), title + " — detected at " + detectedAt);
    }
}
```

`main` would get simpler, but the journal is now welded to the console and
the system clock. In a test, the notification goes to the console, and the
time in the text is new on every run, so you can't check the whole string.

The technique where an object doesn't create its dependencies but receives
them in its constructor is called **constructor injection**. Like your
first day on a team: your laptop, access, and the key to the staging
environment are handed to you; you don't buy them yourself. Whoever hands
them out decides whether it's the training environment or the real one,
and you work the same either way.

Why the constructor and not a field (more on that at the end of the
article):

* the fields are `final`: the constructor must fill them, and they can't
  be swapped later. And the Spring container, if it can't find a clock,
  won't create the journal at all; it will fail on startup (Part 3);
* all dependencies are visible in one place, the constructor parameters;
* in a test, the object is created with a plain `new`, with whatever
  dependencies the test needs.

### An interface is the substitution point

The journal still asks for a `ConsoleNotifier` specifically. We need an
**interface**: a list of methods without implementation, "what it can
do," not "how." An interface is like a power socket: the journal knows
only its shape, and you can plug any device into it.

```java
public interface Notifier {

    void send(String dutyName, String text);         // notify the on-call; how is up to the implementation
}
```

```java
public class ConsoleNotifier implements Notifier {

    @Override
    public void send(String dutyName, String text) {
        System.out.println("[notification] " + dutyName + ": " + text);
    }
}
```

Interface methods are always public, so you don't write `public` in an
interface, and there's no body, just a semicolon. In the implementing
class, `public` is required. `implements Notifier` means "this class does
what the interface promises." `@Override` is an annotation meaning "this
method comes from the interface": get the name wrong, and the compiler
will tell you.

In the journal, one word changes in two places, the type of the field and
of the parameter:

```java
    private final Notifier notifier;                  // was ConsoleNotifier

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock) { … }
```

Now on staging you can write your own `ChatNotifier implements Notifier`,
and in a test your own implementation, and the journal won't notice.

The JDK has already done the same for clocks: `Clock` is a general type,
with several clocks behind it. `Clock.systemUTC()` is a real clock in UTC.
`Clock.fixed(…)` is a stopped one: it always shows the same time.

### A test without Spring

For the test we'll write a **stub**, an object that stands in for the
real one in a test. Our stub doesn't send anything; it remembers. Later,
the Mockito library will create objects like this for you (they're called mocks); more on it further on in the series. For now, we'll write one by hand:

```java
class RememberingNotifier implements Notifier {

    final List<String> messages = new ArrayList<>();     // everything the journal "sent"

    @Override
    public void send(String dutyName, String text) {
        messages.add(dutyName + ": " + text);            // don't send anything; remember it
    }
}
```

`List<String>` is a list of strings: the angle brackets say what's in the
list. On the right the brackets are empty, and Java takes `String` from
the left side. `List` is also an interface, and `ArrayList` is one of its
implementations: the same technique as with `Notifier`.

A field without `private` is visible to classes in the same package. The
test lives in the same package and reads `messages` directly. You don't do
this in production code, but in a test stub it's fine. The stub itself
lives next to the tests, in `src/test/java`, and won't end up in the
application.

The test uses JUnit and AssertJ from Article 0:

```java
class IncidentLogTest {

    @Test
    void notifiesDutyWithDetectionTime() {
        RememberingNotifier notifier = new RememberingNotifier();                            // stub notifier
        Clock clock = Clock.fixed(Instant.parse("2026-10-05T09:15:00Z"), ZoneOffset.UTC);   // frozen clock
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier, clock);

        log.add("Broker is not responding");

        assertThat(notifier.messages)
                .containsExactly("duty-1: Broker is not responding — detected at 2026-10-05T09:15:00Z");
    }
}
```

How to read it:

* `Instant.parse(…)` turns a string into a moment in time, and
  `ZoneOffset.UTC` is the UTC time zone. A clock needs a zone for local
  time, but the zone doesn't affect `instant()`. This clock always shows
  09:15 on October 5;
* the journal is created with a plain `new`, with the stub and the stopped
  clock;
* `containsExactly`: "the list contains exactly these elements, in this
  order."

🔑 The test doesn't start Spring (more on it in Part 3), prints nothing,
and doesn't depend on when it's run. That's the main strength of
constructor injection: any dependency can be swapped with a plain `new`.
Most tests in the real project work exactly this way, with no Spring and
no database.

💡 And here's the answer to why the clock is a separate object: with
`Instant.now()` inside, you can't check the whole string. In the real
project, "now" comes only from a `Clock`. That's a team rule.

Substitution is solved, but creation order, the single instance, and the
settings are still `main`'s job. That's a job for Spring.

---

## Part 3. The Spring container

### Spring Framework: what assembles the objects

**Spring Framework** (usually just called Spring) is a library that
creates an application's objects and wires them together. You describe
which objects you need and what they require, and Spring takes care of
the creation order and of passing dependencies. In course projects,
objects are wired in `main` by hand, because there are only a few. In real
ones there are hundreds, and nobody writes a `main` hundreds of lines
long.

Spring isn't a separate program; it's a library inside your application.
You don't install it by hand: the `spring-boot-starter` starter pulls it
in. Spring is a dependency of that starter, a transitive dependency
(remember, libraries have dependencies of their own). In the real project,
Spring arrives the same way, with Boot starters. Your `main` starts Spring,
and if something goes wrong, you see it right away in the console.

### Sandbox: a project from start.spring.io

The journal needs its own project: in a real service the example would run
into other people's code, a database, and coverage thresholds, while in
a sandbox everything runs right away.

**Spring Initializr** is the site start.spring.io, which generates a skeleton Spring Boot project in a minute: a `pom.xml` with starters, the `mvnw`
wrapper, and the `src/main/java` and `src/test/java` folders. At work
nobody writes the project skeleton from scratch; it's generated. You don't
need to install anything. Fill in the fields:

| field | value |
|---|---|
| Project | Maven |
| Language | Java |
| Spring Boot | 4.1.x, the latest 4.1 |
| Group | `example` |
| Artifact | `game-day` |
| Package name | `example.gameday`: check it and type it in by hand if needed |
| Java | 25 |

You need JDK 25 on your machine, the same one the real project builds
with. With the JDK 17 or 21 from your course, the build fails with
`release version 25 not supported`; make sure your IDE picked JDK 25 for
the project.

Don't add anything under Dependencies: Initializr always includes `spring-boot-starter`
and `spring-boot-starter-test`. The first brings Spring, the second JUnit
and AssertJ.

The Generate button downloads an archive. Unzip it and open the folder
containing `pom.xml` in your IDE; the first time, Maven will spend a while
downloading libraries into `~/.m2`.

Initializr also creates a `GameDayApplication` class and
a `GameDayApplicationTests` test. That's Boot, covered in Article 2.
Don't touch them for now; run your own `GameDayApp`.

Put the journal classes in the `src/main/java/example/gameday/journal`
subpackage, and the stub and test in
`src/test/java/example/gameday/journal`. The subpackage keeps our
container from picking up Initializr's Boot class. Run with the green
triangle next to `main` or the test. To run all tests at once, use
`./mvnw test`.

### Container and bean

The heart of Spring is the **container**: an object inside the
application that, following your description, creates other objects,
passes them their dependencies, and keeps them. A container is like
someone assembling flat-pack furniture: you hand over the parts and the
diagram of what attaches to what, and they decide the order to screw
things together. In Spring, the container is described by the
**`ApplicationContext`** interface, the "application context"; you'll
see both words in the docs and in error messages.

⚠️ Don't confuse it with a Docker container on staging: only the word is
the same. That's why Spring people usually say "context."

A **bean** is an object that the container created itself, or got from
a method with `@Bean` (more on that below), and keeps. Beans are the
application's "workers": the journal, the notifier, the clock. Title strings and moments in time are ordinary objects: your code creates them
as it runs.

There are two ways to describe beans. The first is for your own classes.

### @Component: "create me yourself"

```java
@Component                                           // "container, create an object of this class"
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock) {   // there's one constructor
        this.roster = roster;
        this.notifier = notifier;
        this.clock = clock;
    }
    …
}
```

**`@Component`** is an annotation on a class: "container, create an
object of this class and make it a bean." We put the same marker on
`ConsoleNotifier`. Not on the `Notifier` interface: you can't create an
object of an interface. When the journal asks for a `Notifier`, the
container finds the bean that implements it, `ConsoleNotifier`.

If there were two such beans, the container wouldn't know which one to
pass and would fail on startup. How to keep two implementations and pick
one isn't covered in this series; if you meet it in real code, look for
`@Primary` and `@Qualifier`.

In real code you'll also see `@Service`. It's the same as `@Component`;
the name just tells the reader that there's logic here.

How does the container find these classes? It can scan a package and
collect everything marked `@Component`. This is called **component
scanning**; how to turn it on is below.

**Why there's no `@Autowired`.** **`@Autowired`** is an annotation meaning
"inject here." If a class has one constructor, the container calls it
itself and passes beans of the right types. The marker is needed only
when there are several constructors: it tells the container which one to
use. That's been the case since Spring 4.3; in old examples `@Autowired` sits on every constructor, which is redundant.

### @Configuration and @Bean: when @Component doesn't fit

`@Component` works when the container can assemble the object itself,
because all constructor parameters are beans. That's not always the case.

**It needs data the container doesn't have.** `DutyRoster` asks for the
on-call name, the string `"duty-1"`. How would the container know it?

**The class isn't yours.** `Clock` is a JDK class. You can't put
`@Component` on it: its code isn't yours. The same goes for classes from
any library.

For these cases there's a **configuration class**: a class annotated with
**`@Configuration`**, containing methods annotated with **`@Bean`**. The
container calls such a method once, and whatever it returns becomes
a bean:

```java
@Configuration                                  // "beans are described in this class"
@ComponentScan                                  // "and find classes with @Component" (more below)
public class GameDayConfig {

    @Bean                                       // "what this method returns is a bean"
    public DutyRoster dutyRoster() {
        return new DutyRoster("duty-1");        // the configuration knows who's on call, not main
    }
}
```

We don't put `@Component` on `DutyRoster`: the `@Bean` method creates that bean. The value `"duty-1"` moved from `main` into the configuration class.
The fourth pain point is half solved: the values are still in code, but
they're gathered in one place, separate from object wiring. Moving the values into a settings file is the topic of Article 2.

The clock is declared the same way, with a `@Bean` method that returns
a `Clock`. But first let's forget about it and see what the container
does.

### Starting the container without Boot

```java
public class GameDayApp {

    public static void main(String[] args) {
        AnnotationConfigApplicationContext context =
                new AnnotationConfigApplicationContext(GameDayConfig.class);   // start the container
        IncidentLog log = context.getBean(IncidentLog.class);                  // peek: give me the journal

        log.add("Broker is not responding");

        context.close();                                                       // shut the container down
    }
}
```

How to read it:

* **`AnnotationConfigApplicationContext`** is a container that takes bean
  descriptions from annotations: "Annotation Config" means "configuration
  by annotations." It's one implementation of the `ApplicationContext`
  interface. We pass it the configuration class in the constructor;
* `@ComponentScan` on the configuration class turns on scanning. Without
  parameters, the container scans the package where `GameDayConfig` lives
  and all its subpackages. Our classes are in the same package,
  `example.gameday.journal`, so it will find them. It won't find `GameDayApplication`, one package up;
* `getBean(IncidentLog.class)`: "give me the bean of this type."

⚠️ In real code nobody writes `getBean`: beans are obtained only through
constructors. Here it's used once, to peek inside the container.

### First run: an error

Run `GameDayApp`. The container fails right away, even before `getBean`,
with a long error. You don't need to read all of it; look for familiar
names:

```
Error creating bean with name 'incidentLog' … Unsatisfied dependency expressed
through constructor parameter 2: No qualifying bean of type 'java.time.Clock' available
```

`incidentLog` is the journal bean's name. For a `@Component` bean it's the
class name with a lowercase first letter; for a `@Bean` method, it's the
method name (`dutyRoster`). `parameter 2` is the constructor's third
parameter, counting from zero: the journal asks for a clock, and there's
no clock bean. For the same reason, Initializr's `GameDayApplicationTests`
will also fail if you run all the tests.

This is a good error: the container checks the wiring on startup, so
you'll see a forgotten dependency on your own machine, not on Game Day.

Let's add a clock to `GameDayConfig`:

```java
    @Bean                                       // Clock is someone else's class, from the JDK
    public Clock clock() {
        return Clock.systemUTC();               // a real clock, time in UTC
    }
```

Run it again. Before our line, the container may print a few log lines containing `DEBUG`; you can ignore them for now. The last line will be
(your time will differ):

```
[notification] duty-1: Broker is not responding — detected at 2026-10-05T09:15:03.512704831Z
```

That's the same thing `main` printed in Part 1. The container assembled
the same four objects (the journal and its three helpers) and wired them
the same way. It just figured out the order itself.

### One instance per application

By default the container creates each bean **once** and hands that same
object to everyone who asks for it. Such a bean is called a **singleton**.
Like the office coffee machine: one for everyone, and nobody brings their
own. This solves the second pain point: the container provides the single
instance, so you don't need to thread it through `main`.

💡 In books, "singleton" is also a pattern where the class itself
prevents a second instance. A bean isn't like that: `new ConsoleNotifier()`
will create a second one. The rule "beans come only through constructors"
is enforced by code review.

A singleton has a flip side. A service handles requests in parallel: each
request has its own **thread**, a separate worker moving through the
code. Two threads can end up in the same method of the same bean instance
at the same moment. That's why you must not store data from a single call
in a bean's fields:

```java
@Component
public class IncidentLog {

    private String title;                           // 🔴 data from one call, in a field of the shared instance

    public void add(String title) {
        this.title = title;
        String dutyName = roster.currentDuty();
        notifier.send(dutyName, this.title);        // by now another call may have overwritten the field
    }
    …
}
```

The first call put "Broker is not responding" in the field, and while it
was finding out who's on call, the second call overwrote the field with
"Mail is down." Both notifications are about mail, and the broker is lost.
🔴 In a service that sends emails, the same slip means an email to the
wrong person: the service remembers the "current recipient" in a field,
and another request running at the same time overwrites it.

🔑 A bean's fields hold only dependencies and settings, all `final`.
Everything that belongs to a single call lives in method parameters and
local variables: the incident, the person, the request. The
`RememberingNotifier` stub may accumulate calls in a field: it's not
a bean, and it lives for one test.

### Where the internet teaches the old way

⚠️ **`@Autowired` on a field.** Online you'll see this:

```java
@Component
public class IncidentLog {

    @Autowired
    private Notifier notifier;                      // the container puts the bean straight into the field
    …
}
```

This is **field injection**, the old style. Spring still understands it,
but in the real project only constructors are used. Such a field can't be
`final`. `new IncidentLog()` gives a journal with `null` instead of
a notifier, and a test without Spring can't put anything into such
a field. Everything that made the Part 2 test good is lost.

⚠️ **`javax` instead of `jakarta`.** Sometimes a bean needs to do
something right after it's created, once its dependencies have been
passed in. For that, the method is marked with the **`@PostConstruct`**
annotation, and the container calls it itself. Online you'll see
`javax.annotation.PostConstruct`: that's how it was written in the Boot 2
days. This series uses Spring Framework 7 (Boot 4 brings it), and it no
longer supports `javax` annotations. The correct one is
`jakarta.annotation.PostConstruct`.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. What is an object's dependency? Name `IncidentLog`'s dependencies. How
   does this word differ from a dependency in `pom.xml`?
2. What does "constructor injection" mean? What gets worse if the journal
   creates the notifier itself and takes the time from `Instant.now()`?
3. Why is `Notifier` an interface if the application has only one
   implementation so far, `ConsoleNotifier`?
4. How did the Part 2 test check the time in the notification text
   without knowing when it would be run?
5. How does a bean differ from an ordinary object? How does the container
   know which classes to create?
6. When do you need `@Bean` instead of `@Component`? Why can't you put
   `@Component` on `Clock`?
7. The container failed on startup, and the error mentions
   `java.time.Clock`. What happened, and why is it good that it happened
   on startup?
8. Why can't you store data from a single call in a bean's field? What can this lead to in a service that sends notifications?

---

## What's next

Boot does even more: it creates the container and hundreds of beans
itself, and it reads the game settings (such as the duration and the stop
word) from a file. That's Article 2, in the same sandbox:
`GameDayApplication` takes over from `GameDayApp`.

## Sources

* [Spring Framework: Using @Autowired](https://docs.spring.io/spring-framework/reference/core/beans/annotation-config/autowired.html):
  when `@Autowired` isn't needed; see the note on a single constructor;
* [Spring Framework: Java-based Container Configuration](https://docs.spring.io/spring-framework/reference/core/beans/java.html):
  how to describe beans with a configuration class, start
  `AnnotationConfigApplicationContext`, and turn on scanning;
* [Spring Boot: Spring Beans and Dependency Injection](https://docs.spring.io/spring-boot/reference/using/spring-beans-and-dependency-injection.html):
  the same from Boot's point of view, including component scanning and
  `@Service`;
* [Java 25: java.time.Clock](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html):
  `systemUTC`, `fixed`, `instant`;
* [Spring Framework 7.0 Release Notes](https://github.com/spring-projects/spring-framework/wiki/Spring-Framework-7.0-Release-Notes):
  the Removed APIs section explains why `javax` no longer works.

---

## The full example, with imports

A learning example. Run it in the `game-day` sandbox from
start.spring.io; how to create it and where to put the files is in
Part 3. Leave Initializr's `GameDayApplication` and
`GameDayApplicationTests` alone.

```java
// src/main/java/example/gameday/journal/DutyRoster.java
package example.gameday.journal;

public class DutyRoster {

    private final String dutyName;

    public DutyRoster(String dutyName) {
        this.dutyName = dutyName;
    }

    public String currentDuty() {
        return dutyName;
    }
}
```

```java
// src/main/java/example/gameday/journal/Notifier.java
package example.gameday.journal;

public interface Notifier {

    void send(String dutyName, String text);
}
```

```java
// src/main/java/example/gameday/journal/ConsoleNotifier.java
package example.gameday.journal;

import org.springframework.stereotype.Component;

@Component
public class ConsoleNotifier implements Notifier {

    @Override
    public void send(String dutyName, String text) {
        System.out.println("[notification] " + dutyName + ": " + text);
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentLog.java
package example.gameday.journal;

import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;

@Component
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock) {
        this.roster = roster;
        this.notifier = notifier;
        this.clock = clock;
    }

    public void add(String title) {
        Instant detectedAt = clock.instant();
        String dutyName = roster.currentDuty();
        notifier.send(dutyName, title + " — detected at " + detectedAt);
    }
}
```

```java
// src/main/java/example/gameday/journal/GameDayConfig.java
package example.gameday.journal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
@ComponentScan
public class GameDayConfig {

    @Bean
    public DutyRoster dutyRoster() {
        return new DutyRoster("duty-1");
    }

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
```

```java
// src/main/java/example/gameday/journal/HandMadeApp.java
package example.gameday.journal;

import java.time.Clock;

public class HandMadeApp {

    public static void main(String[] args) {
        DutyRoster roster = new DutyRoster("duty-1");
        Notifier notifier = new ConsoleNotifier();
        Clock clock = Clock.systemUTC();
        IncidentLog log = new IncidentLog(roster, notifier, clock);

        log.add("Broker is not responding");
    }
}
```

```java
// src/main/java/example/gameday/journal/GameDayApp.java
package example.gameday.journal;

import org.springframework.context.annotation.AnnotationConfigApplicationContext;

public class GameDayApp {

    public static void main(String[] args) {
        AnnotationConfigApplicationContext context =
                new AnnotationConfigApplicationContext(GameDayConfig.class);
        IncidentLog log = context.getBean(IncidentLog.class);

        log.add("Broker is not responding");

        context.close();
    }
}
```

```java
// src/test/java/example/gameday/journal/RememberingNotifier.java
package example.gameday.journal;

import java.util.ArrayList;
import java.util.List;

class RememberingNotifier implements Notifier {

    final List<String> messages = new ArrayList<>();

    @Override
    public void send(String dutyName, String text) {
        messages.add(dutyName + ": " + text);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentLogTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;

class IncidentLogTest {

    @Test
    void notifiesDutyWithDetectionTime() {
        RememberingNotifier notifier = new RememberingNotifier();
        Clock clock = Clock.fixed(Instant.parse("2026-10-05T09:15:00Z"), ZoneOffset.UTC);
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier, clock);

        log.add("Broker is not responding");

        assertThat(notifier.messages)
                .containsExactly("duty-1: Broker is not responding — detected at 2026-10-05T09:15:00Z");
    }
}
```
