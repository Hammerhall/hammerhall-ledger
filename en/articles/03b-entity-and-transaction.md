# Data, part 2: entity, repository, transaction

> "From Java to Spring Boot" · Article 3b · 30 min read
>
> **Who it's for.** You've read Articles 0–2 and the first part of the
> "Data" topic, Article 3a. Your `game-day` sandbox has the
> `game_day.incident` table, its migration, and the `IncidentTableIT`
> test against Postgres in a container. You have Docker installed.
>
> **What's inside.** Three things: how a Java object becomes a table row
> and back again (the entity and the repository); how to make several
> changes on an "all or nothing" basis (the transaction); and how to test
> both against a real database.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why entities and repositories

In Article 3a you wrote SQL as a string through `JdbcTemplate`. That's
fine for a migration test. But the journal would have to build every
query as a string that way. Every row of the result would have to be
copied into the object's fields by hand, and the other way around when
writing. For every table and every query, that's dozens of near-identical
lines, and in any of them you can mix up the columns.

In this article the Game Day journal finally starts storing incidents.
The table becomes the `Incident` class, the journal gets a repository,
and closing several incidents at once runs as a single transaction.
Restarting the application will no longer wipe the journal: that's the
problem the "Data" topic started with.

The Game Day journal is a learning example. But juniors write entities
and repositories in the real project too, so everything in it will come
up again in your tasks.

---

## Part 1. The entity

### ORM: a translator between rows and objects

An **ORM** (object-relational mapping) does the translating between rows
and objects for you. Think of it as a translator: the database speaks in
rows and columns, Java in objects and fields. Describe once which class
maps to which table, and from then on the ORM translates by itself.

### JPA and Hibernate: who's who

**JPA** (Jakarta Persistence) is a standard: annotations and rules for
describing a class to an ORM. By itself it does nothing. Why "JPA"? The
standard used to be called the Java Persistence API; it was renamed
later, but the abbreviation stuck.

**Hibernate** is a library that implements this standard: it creates
objects from rows, writes the SQL, and tracks changes. JPA is to
Hibernate what the `Notifier` interface from Article 1 is to
`ConsoleNotifier`: you write code against the standard, and the
implementation does the work. Don't confuse it with Hibernate Validator
from Article 2: same authors, different library.

On top of them sits **Spring Data JPA**: it spares you even from writing
repository code (Part 2). The `spring-boot-starter-data-jpa` starter
brings all of it. In the sandbox's `pom.xml`, it takes the place of
`spring-boot-starter-jdbc` from Article 3a.

```xml
<dependency>                                <!-- instead of spring-boot-starter-jdbc -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
```

Why instead of it, and not next to it? The JPA starter brings the JDBC
starter itself: the database connection and `JdbcTemplate`. There's no
point declaring it twice. `IncidentTableIT` from Article 3a, with its
`JdbcTemplate`, works as before. Flyway, the Postgres driver, and
Testcontainers stay where they are, and `<parent>` fills in the version.

You don't need to start Hibernate: Boot brings it up itself when the
application starts. If something goes wrong, you'll see it in the
startup log.

⚠️ Online you'll see annotations from `javax.persistence`. That's Boot 2
and earlier. Boot 4 uses `jakarta.persistence`; Spring Framework 7
doesn't support `javax.*` at all.

⚠️ A common mistake is the `ddl-auto: update` setting from tutorials:
Hibernate creates and alters tables from the classes by itself. Then two
parties would be changing the tables, Flyway from migrations and
Hibernate from classes, and the databases would drift apart again, as at
the start of Article 3a. The real project uses `validate`: only Flyway
creates tables, and on startup Hibernate just checks the classes against
them. If they don't match, the application won't start.

The sandbox works the same way. Add this to `application.yml`, under the
same `spring:` where `flyway:` already is:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate     # tables come only from migrations; Hibernate checks them
```

### The Incident entity

An **entity** is a class whose objects JPA stores as table rows: one
object, one row. The journal classes live where they always have, in the
`example.gameday.journal` package, next to `IncidentLog`. Spring looks
for entities and repositories only inside the application's package:
`example.gameday` and below.

As in the previous articles, the short examples have no `import` lines,
and `…` marks a piece that was left out. The full files are at the end
of the article.

```java
@Entity                                                // "this is an entity"
@Table(name = "incident", schema = "game_day")         // its table; the schema is explicit
public class Incident {

    @Id                                                // the primary key
    // Hibernate creates the key on save: for a UUID, a random UUID
    @GeneratedValue
    private UUID id;

    @Column(name = "title", nullable = false)          // marks NOT NULL in the table; the database checks it
    private String title;

    @Column(name = "detected_at", nullable = false)    // the column name is explicit, as in the table
    private Instant detectedAt;

    @Column(name = "fixed_at")                         // may be empty
    private Instant fixedAt;

    @Column(name = "duty_name", nullable = false)
    private String dutyName;

    protected Incident() {                             // for JPA
    }

    public Incident(String title, Instant detectedAt, String dutyName) {
        // checks as in the compact constructor from Article 0; the full code is at the end
        this.title = title;
        this.detectedAt = detectedAt;
        this.dutyName = dutyName;
    }

    public void fix(Instant now) {                     // "we fixed it"
        if (fixedAt != null) {
            throw new IllegalStateException("incident '" + title + "' is already closed");
        }
        if (now.isBefore(detectedAt)) {
            throw new IllegalArgumentException("fixed before it was detected: " + now);
        }
        fixedAt = now;
    }

    public UUID getId() {
        return id;
    }
    // getTitle(), getDetectedAt(), getFixedAt(), getDutyName(): the same way
}
```

In Java, a `UUID` column corresponds to the `UUID` class from
`java.util`, and `TIMESTAMPTZ` to `Instant`, as agreed in Article 3a.
`IllegalStateException` is a relative of `IllegalArgumentException` from
Article 0: "you can't do that in this state." The problem isn't the
argument; it's that the incident is already closed.

Hibernate checks this description against the table on every startup,
thanks to `validate`. Make a typo in a column name, write
`@Column(name = "fixed")` instead of `fixed_at`, and the application
won't start:

```
Schema validation: missing column [fixed] in table [game_day.incident]
```

Failing on startup beats failing on the first request in the middle of
Game Day.

### Entity rules

This is how entities are written in the real project, and in the sandbox
too.

**Fields are `private`, getters are written out.** JPA reads and writes
fields directly, bypassing methods; the getters are for your code. In the
real project they're written by hand, without Lombok, a library that
generates such code for you. ⚠️ The names are `getTitle()`, not
`title()` as with the records from Article 0.

**No setters.** If there were a `setFixedAt(Instant)` method instead of
`fix`, any place in the code could close an incident twice, "before it
was detected," or quietly reopen it (`setFixedAt(null)`). And every one
of those places would have to check the rule. With `fix`, the rule lives
in one place. And the name says what happened, not which field changed.

**The no-argument constructor is `protected`.** When reading a row, JPA
first creates an empty object, then fills its fields with the column
values. That's what the no-argument constructor is for. Hibernate only
requires that it not be `private`. `protected` means "accessible to
subclasses and to classes in the same package": outside the package,
nobody can create an empty incident. Inside it, there's an agreement:
this constructor is for JPA only. New incidents are created with the
public constructor.

**Not a record, and not `final`.** `final` on a class means "no
subclasses allowed." Hibernate sometimes hands out a subclass it generated instead of the entity itself, for example as a reference to an object it hasn't read from the database yet. So an entity can't be
`final`. A record is always `final`, and immutable on top of that, while
JPA needs to create the object empty and fill it in later. So an entity
is an ordinary class.

**Time comes from outside.** `fix` receives `now` as a parameter, and the
caller takes the time from a `Clock`: `incident.fix(clock.instant())`.
Don't write `Instant.now()` inside an entity: a test won't be able to
check what time was recorded. That's the team rule from Article 1: "now"
comes only from a `Clock`.

💡 The key is set up twice, with `@GeneratedValue` and with `DEFAULT` in
the table. That's not redundant. When you save through JPA, Hibernate generates the key in Java, before the insert, and `DEFAULT` kicks in when a row is inserted with
plain SQL, as in `IncidentTableIT`.

---

## Part 2. The repository

### IncidentRepository

A **repository** is an interface your code uses to find and save
entities. You don't need to write the implementation:

```java
public interface IncidentRepository extends JpaRepository<Incident, UUID> {
}
```

The angle brackets hold type parameters, as in `List<String>` from
Article 1: a repository of `Incident` entities with a `UUID` key.

Spring Data writes the implementation on startup and makes it a bean:
get it through the constructor, like any dependency. Ready-made methods
are already there: `save`, `findById`, `findAll`, `count`, `deleteAll`,
and others. `save` saves the entity and returns the saved one, already
with its key.

`findById` returns an `Optional<Incident>`: a box that either holds the
object or is empty. The method is honest about it: "I might not find
it." `orElseThrow` means "take it out, and if the box is empty, throw
this exception":

```java
Incident incident = incidents.findById(id)
        .orElseThrow(() -> new IllegalArgumentException("no incident " + id));
```

### Queries from method names

Often you don't need to write a query at all: it's enough to name the
method by Spring Data's rules.

```java
List<Incident> findByDutyName(String dutyName);    // … where i.dutyName = ?1
List<Incident> findByFixedAtIsNull();              // … where i.fixedAt is null — the ones still open
```

Spring Data parses the name word by word: `findBy` means "find by,"
followed by an entity field and, if needed, a condition (`IsNull`). The
name uses Java fields (`dutyName`), not columns (`duty_name`). Make a typo and Spring Data won't understand the method, so the application won't start.

Take `findByDuty_name`: it goes by the column, not the field. To Spring
Data, the `_` character is a step into a nested object: it looks for
a `duty` field on `Incident` so it can take `name` from it. There's no
such field:

```
No property 'duty' found for type 'Incident'
```

### @Query: when a name isn't enough

With many conditions, the name becomes unreadable. Then you write the
query yourself:

```java
@Query("select i from Incident i where i.dutyName = ?1 and i.fixedAt is null order by i.detectedAt")
List<Incident> findOpenOf(String dutyName);         // open ones for this on-call engineer, oldest first
```

This is **JPQL**, the JPA query language. It looks like SQL, but it
talks about entities and fields: `Incident` and `dutyName`, not
`game_day.incident` and `duty_name`. They're easy to mix up: the table
and columns go in the migration, the class and fields in `@Query`. `?1`
is the method's first parameter.

---

## Part 3. The journal stores, a transaction closes

### IncidentLog is a service

```java
@Service                                               // was @Component
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;
    private final IncidentRepository incidents;       // the fourth dependency: the repository

    // a constructor with four parameters: as in Article 1, plus incidents

    public void add(String title) {
        Incident incident = incidents.save(new Incident(title, clock.instant(), roster.currentDuty()));
        notifier.send(incident.getDutyName(), title + " — detected at " + incident.getDetectedAt());
    }
    …
}
```

`@Service` from Article 1 is the same thing as `@Component`. In the real
project it marks classes with logic, data, and transactions, and such
classes are called **services**. That's exactly what the journal is now.

`add` saves first, then notifies: a notification about an incident that
isn't in the journal is worse than none at all.

### The new journal replaces the old one

The new `IncidentLog` goes into the same file as the old one,
`src/main/java/example/gameday/journal/IncidentLog.java`: it replaces
the old one rather than sitting next to it. And the journal test from Article 1 has to go.

⚠️ **Don't keep the old journal around.** Say you put the new one in
a different package and keep the old one "just in case." Then the
application ends up with two beans with the same name, `incidentLog`:
Spring takes the bean name from the class name. The application won't
start, failing with `ConflictingBeanDefinitionException`:

```
Annotation-specified bean name 'incidentLog' … conflicts with existing, non-compatible bean definition …
```

**Delete `IncidentLogTest` from Article 1.** It creates the journal with
`new` and three arguments, but the constructor now asks for four. The
compiler will answer `cannot be applied to given types`, and none of the
sandbox's tests will build. You can't rewrite it, either. The fourth
argument has to be a repository, and you can't write a stub for it by
hand, the way `RememberingNotifier` stands in for `Notifier`:
`JpaRepository` has dozens of methods. Mocks for interfaces like that
are made by the Mockito library, which comes later in the series.

So delete the test together with its `RememberingNotifier` stub.
`IncidentLogIT` from Part 4 will test the whole journal, with the
repository and the database. To be honest about what's lost: no test
checks the notification text now; you can only see it in the startup
log. That check comes back with Mockito.

### The journal survives a restart

`GameDayApplication` from Article 2 hasn't changed: it gets the journal
and calls `add("Broker is not responding")`. But now `add` writes to the
database, and every run leaves a row in the table. The application
didn't start without a database before either, so you run it as in
Article 3a: Postgres in a container, the three `SPRING_DATASOURCE_*`
variables, and `java -jar`. Rebuild with `./mvnw package`. The database
tests now run during the build too: you have Docker running.

The log shows familiar lines:

```
[notification] duty-1: Broker is not responding — detected at 2026-…Z
game PT3H, attackers 2
```

Run it once more and look in the table
(`docker exec -it game-day-db psql -U postgres`):

```sql
SELECT title, duty_name, fixed_at FROM game_day.incident;
```

```
          title           | duty_name | fixed_at
--------------------------+-----------+----------
 Broker is not responding | duty-1    |
 Broker is not responding | duty-1    |
(2 rows)
```

Two runs, two rows, and `fixed_at` is empty: nothing has been fixed yet.
The application restarted, and the journal remembers. If you need
a clean database, recreate the container as in Article 3a:
`docker stop game-day-db`, then `docker run` again.

### All or nothing

A money transfer between accounts takes two steps: debit one account,
credit the other. If something breaks after the first step, the money
must not vanish. Either both steps go through, or neither does.

A **transaction** is a group of changes to the database that is carried
out in full or not at all. If it finishes without errors, that's
a **commit**: all the changes become visible to everyone at once. An
error midway means a **rollback**: the database returns to the state it
was in before the start, as if nothing had happened.

Here's what it looks like in the journal. An attack took down the broker
on staging, and the on-call engineers opened five incidents because of
it. A mid-level developer fixed the cause, and all five are closed at
once:

```java
    @Transactional                                     // the whole method is one transaction
    public void fixAll(List<UUID> ids) {
        Instant now = clock.instant();
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("no incident " + id));
            incident.fix(now);                         // already closed: an exception
            incidents.save(incident);
        }
    }                                                  // exited without an exception: commit
```

The on-call engineer passed in five keys, and the fourth one has a typo.
With a transaction, the three fixes already made are rolled back. The
database is just as it was; the on-call engineer fixes the list and tries
again. Without a transaction, each `save` is committed right away: three
incidents are closed, two are open, and you have to dig through the
database to find out which.

### @Transactional

`@Transactional` is a Spring annotation on a bean's method: "run this
method in a transaction." The start of the method is the start of the
transaction, a normal exit is a commit, and an exception is a rollback.

Your IDE may offer two imports for `Transactional`. The second one is
`jakarta.transaction.Transactional`: it comes along with the JPA
starter. Spring understands both, but for one style across all the code,
the real project uses only Spring's:
`org.springframework.transaction.annotation.Transactional`.

It goes on service methods that take several steps, not on the
repository and not on the entity. The repository's ready-made methods,
such as `save` and `findById`, each already run in a small transaction of their own. The service's transaction combines them into one. In real
code you'll find `@Transactional` in almost every service that changes
data.

### ⚠️ Rollback happens only on unchecked exceptions

By default, Spring rolls back a transaction only if an **unchecked**
exception (`RuntimeException` and its subclasses) or an `Error` was
thrown. On a checked exception, it commits everything the method managed
to do.

That's one more reason errors in the real project are unchecked
exceptions (Article 0). If the exception in the example were checked,
the three fixes would stay in the database. That's exactly the
half-done state a transaction is supposed to protect against.

### ⚠️ A call from inside the same class doesn't start a transaction

Spring puts a **proxy** in front of the bean: a go-between object with
the same methods. It opens a transaction, calls the real method, then
commits or rolls back. A call from another bean goes through the
go-between. But a call from inside the class goes straight to the
object, bypassing the go-between. One example is `this.fixAll(ids)`
from another `IncidentLog` method that has no `@Transactional`.

The annotation on `fixAll` then silently does nothing: no error, no
transaction, and the half-done state is possible again. If you need
a transaction, call the method from outside, from another bean.

### The persistence context

Inside a transaction, strictly speaking, you don't need `save` for an
entity you've read. JPA remembers the objects it has read in this
transaction. This memory is called the **persistence context**. On
commit, JPA compares the objects with what it read and writes the
changes itself. In `fixAll`, `save` is written out explicitly: that
makes it easier to see what's going on.

⚠️ Don't confuse it with the Spring context from Articles 1–2: that one
holds beans for as long as the application runs, while the persistence
context holds the entities read during a single transaction.

This memory has a flip side. Reading the same key again in the same
transaction returns the object from memory, not from the database. In
code that's convenient; in tests it's a trap. More on that in Part 4.

---

## Part 4. Database tests

### IncidentTest: the rules without a database

The entity's rules don't need a database: `fix` and the constructor
checks are plain Java. The `IncidentTest` unit test checks them, with no
Spring and no database. Each constructor check is a table row, as
Article 0 taught:

```java
    @ParameterizedTest(name = "{0}, {1}, {2} → rejected")
    @CsvSource(delimiter = '|', nullValues = "null", textBlock = """
            null    | 2026-10-05T09:15:00Z | duty-1
            ''      | 2026-10-05T09:15:00Z | duty-1
            '   '   | 2026-10-05T09:15:00Z | duty-1
            staging | null                 | duty-1
            staging | 2026-10-05T09:15:00Z | null
            staging | 2026-10-05T09:15:00Z | '   '
            """)
    void rejectsMissingParts(String title, Instant detectedAt, String dutyName) {
        assertThatThrownBy(() -> new Incident(title, detectedAt, dutyName))
                .isInstanceOf(IllegalArgumentException.class);
    }
```

`nullValues = "null"`: the word `null` in the table becomes a real
`null`. That's how `null` finally fits into the table. JUnit turns the
string `2026-10-05T09:15:00Z` into an `Instant` itself, just as it
turned the text `130` into an `int` in Article 0.

Together with the tests for `fix`, that's every branch of `Incident`:
100%, which is what the real project requires of new classes
(Article 0). Every line too, except the constructor for JPA. Only
Hibernate calls it, when it assembles an object from a table row, so the
database tests will cover it. JaCoCo isn't set up in the sandbox, but in
the real project the report would show exactly that.

### IncidentRepositoryIT: queries against a real database

The repository is tested against a real Postgres, the same way as the
migration in `IncidentTableIT` from Article 3a:

```java
@SpringBootTest                                        // the whole application
@Import(TestcontainersConfiguration.class)             // plus Postgres in a container
class IncidentRepositoryIT {

    // a frozen "now" for every test in the class
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();                         // the database is shared: clean up after yourself
    }

    @Test
    void findsOnlyOpen() {
        Incident open = incidents.save(new Incident("staging is not responding", T0, "duty-1"));
        Incident fixed = new Incident("the queue is growing", T0, "duty-2");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);

        assertThat(incidents.findByFixedAtIsNull())
                .extracting(Incident::getId)           // only the key of each one found
                .containsExactly(open.getId());
    }
    …
}
```

The annotations and `@Import` are the same as on `IncidentTableIT`. So
Spring hands the test the already-running application from its cache
(Article 3a), and there's still one container per run.

`Incident::getId` is a **method reference**, a short way to write the
lambda `i -> i.getId()`. `extracting` takes the key from each object
found, and from there AssertJ compares a list of keys. We compare keys,
not the objects themselves: the object found doesn't have to be the same
Java object the test saved.

⚠️ In tests, use only a fixed time: `Instant.parse(…)`. `TIMESTAMPTZ`
stores time to the microsecond, but an `Instant` can be more precise: on
some machines `Instant.now()` has more digits after the decimal point.
You write one value, read back another, and the test goes red out of
nowhere.

### The persistence context in tests

Remember the persistence context's flip side? The context lives as long
as the transaction. If the test itself runs in one transaction, "save
and read back" returns the same object from memory. The test is green,
but it has told you nothing about the database.

Our tests don't run in a transaction: `@SpringBootTest` doesn't open one.
Each repository call in `IncidentRepositoryIT` gets its own new
persistence context and closes it afterward. So a read really goes to
the database and returns a new object. That's why the test compares
keys.

`@Transactional` on a test class or method opens a transaction for each
test. At the end of the test, Spring rolls it back, so you don't need to
clean up after yourself. That's how **`@DataJpaTest`**, the database
slice (Article 2), works: it wraps every test in a transaction.

In tests like that, you reset the context by hand with methods of the
JPA `EntityManager` object: `flush` sends the changes to the database,
and `clear` forgets the objects in memory. The next read then really
goes to the database.

The sandbox has no `@DataJpaTest`: the repository is tested by the same
`@SpringBootTest` with a container as the migration. The real project
tests repositories this way too.

⚠️ Online you'll see `@DataJpaTest` from the
`org.springframework.boot.test.autoconfigure.orm.jpa` package, right
inside `spring-boot-starter-test`. That's Boot 2–3. In Boot 4 it has its
own test starter, `spring-boot-starter-data-jpa-test`, and the package
`org.springframework.boot.data.jpa.test.autoconfigure`.

### IncidentLogIT: proving the rollback

The main promise of Part 3, "the three fixes are rolled back," is
checked by a test against a real database. It takes the whole journal
as a bean, with all four dependencies.

```java
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentLogIT {

    // in the past: fixAll takes "now" from the real clock
    private static final Instant T0 = Instant.parse("2026-09-01T09:15:00Z");

    @Autowired
    private IncidentLog log;

    @Autowired
    private IncidentRepository incidents;

    …

    @Test
    void fixAllRollsBackWhenOneIdIsUnknown() {
        List<UUID> ids = new ArrayList<>();
        for (String title : List.of("staging is not responding", "the queue is growing",
                "emails are not going out")) {
            ids.add(incidents.save(new Incident(title, T0, "duty-1")).getId());
        }
        ids.add(UUID.randomUUID());                    // no such key in the database

        assertThatThrownBy(() -> log.fixAll(ids))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no incident");   // it failed on exactly the fourth key
        assertThat(incidents.findByFixedAtIsNull()).hasSize(3);   // all three are still open
    }
}
```

`hasSize(3)` means "the list has exactly three elements."

⚠️ You can check a rollback this way only if the test itself doesn't
open a transaction. Ours doesn't: it has no `@Transactional`. So
`fixAll` opens its own, real one, the rollback reaches the database, and
the check after the error is a fresh query to the database.

Put `@Transactional` on the `IncidentLogIT` class, and the test goes red
even with a working `fixAll`:

```
Expected size: 3 but was: 0 in:
[]
```

`fixAll` joined the test's transaction. The error only marked it "roll
back at the end." Until the test ends, the fixes live in that same
unfinished transaction, and the check, which runs in it too, sees them.
Everything is rolled back after the test, when there's nothing left to
check. Service transactions are tested with a test that has no
transaction of its own, as here.

🔑 Check that the test can fail: remove `@Transactional` from `fixAll`
and run it. It must go red with the same
`Expected size: 3 but was: 0`: the three incidents will be closed. If it
stays green, the check is looking in the wrong place, and it doesn't
prove the rollback. A test that can't say "no" isn't a test.

💡 Why is `T0` here a fixed date, September 1, rather than a stopped clock, as in
`IncidentLogTest` from Article 1? There, the journal was assembled with
`new`, and the clock was passed in by hand. Here the journal is a bean,
and Spring gives it the clock: the real `clock` bean from
`GameDayConfig`. `fixAll` will close the incidents "now." So that `fix`
doesn't decide they were fixed before they were detected, the incidents
are created in the past.

A second clock bean for the test won't help here. Say you copy the
`clock()` method, with a stopped clock, into a test configuration class
marked `@TestConfiguration`, like `TestcontainersConfiguration` in
Article 3a, and bring it in with `@Import`. But a bean named `clock`
already exists, and Boot doesn't allow overriding beans. The application
won't start:
`A bean with that name has already been defined … and overriding is disabled`.

Give the method a different name, and startup succeeds, but the journal
won't notice the swap. Of the two `Clock` beans, Spring passes the one
whose name matches the name of the constructor parameter, that is,
`clock`. How to swap beans in tests comes later in the series, along with
Mockito.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. How does JPA differ from Hibernate? Who creates the tables in the
   sandbox, and what does Hibernate do on startup?
2. Why does an entity need a no-argument constructor, and why is it
   `protected`? Who does `protected` not keep out?
3. Why doesn't `Incident` have a `setFixedAt`? Where does the rule "an
   incident can be closed only once" live?
4. The `findByDuty_name` method keeps the application from starting. Why?
   How does a query in `@Query` differ from the SQL in a migration?
5. `fixAll` closed three incidents and failed on the fourth. What ends up
   in the database with `@Transactional`, and without it?
6. What happens if the exception in `fixAll` turns out to be a checked
   one? And if `fixAll` is called from another method of the same class?
7. What is the persistence context? Why can it make a "save and read
   back" test check nothing?
8. How do you make sure `IncidentLogIT` really proves the rollback? Why
   does it go red if you mark the test itself `@Transactional`?

---

## What's next

Next in the series: the web. The journal learns to answer over HTTP: it
takes an incident from the repository by its key and returns it as JSON,
or, if there's no such incident, a clear error.

## Sources

* [Spring Data JPA: Query Methods](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html):
  the table of keywords for query methods by name (`IsNull`, `OrderBy`,
  and others), and `@Query`;
* [Spring Framework: Using @Transactional](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html):
  proxies, and why a call from inside the class bypasses the transaction;
* [Spring Framework: Rolling Back a Declarative Transaction](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/rolling-back.html):
  which exceptions cause a rollback and which a commit;
* [Introduction to Hibernate 7](https://github.com/hibernate/hibernate-orm/tree/7.4.1/documentation/src/main/asciidoc/introduction):
  the requirements for an entity (a no-argument constructor, not `final`) and the
  ways to generate a key;
* [Spring Boot: Testing Spring Boot Applications](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html):
  how tests start the application, and which tests run in a transaction.

---

## The full example, with imports

A learning example. Run it in the `game-day` sandbox after Article 3a.
These stay unchanged: the `V1__game_day_incident.sql` migration,
`TestcontainersConfiguration`, `IncidentTableIT`,
`GameDayApplicationTests` with `@Import`, `GameDayApplication`,
`GameDayProperties` with its test, `application-stand.yml`, and the
journal's helpers from Article 1: `DutyRoster`, `Notifier`,
`ConsoleNotifier`, and `GameDayConfig` with the clock bean.

What to change: in `pom.xml`, replace `spring-boot-starter-jdbc` with
`spring-boot-starter-data-jpa`; in `application.yml`, add
`ddl-auto: validate`; replace `IncidentLog` with the new one. What to
add: `Incident`, `IncidentRepository`, and three tests: `IncidentTest`,
`IncidentRepositoryIT`, and `IncidentLogIT`. What to delete:
`IncidentLogTest` and `RememberingNotifier` from
`src/test/java/example/gameday/journal`. Docker must be running.

```xml
<!-- pom.xml: in <dependencies>, instead of spring-boot-starter-jdbc; the rest as after Article 3a -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
```

```yaml
# src/main/resources/application.yml
spring:
  flyway:
    schemas: game_day
  jpa:
    hibernate:
      ddl-auto: validate
hammerhall:
  game-day:
    stop-word: test-stop-word
```

```java
// src/main/java/example/gameday/journal/Incident.java
package example.gameday.journal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "incident", schema = "game_day")
public class Incident {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "detected_at", nullable = false)
    private Instant detectedAt;

    @Column(name = "fixed_at")
    private Instant fixedAt;

    @Column(name = "duty_name", nullable = false)
    private String dutyName;

    protected Incident() {
    }

    public Incident(String title, Instant detectedAt, String dutyName) {
        if (title == null || title.isBlank()) {
            throw new IllegalArgumentException("the incident has no title");
        }
        if (detectedAt == null) {
            throw new IllegalArgumentException("detection time is missing");
        }
        if (dutyName == null || dutyName.isBlank()) {
            throw new IllegalArgumentException("the on-call engineer is missing");
        }
        this.title = title;
        this.detectedAt = detectedAt;
        this.dutyName = dutyName;
    }

    public void fix(Instant now) {
        if (fixedAt != null) {
            throw new IllegalStateException("incident '" + title + "' is already closed");
        }
        if (now.isBefore(detectedAt)) {
            throw new IllegalArgumentException("fixed before it was detected: " + now);
        }
        fixedAt = now;
    }

    public UUID getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public Instant getDetectedAt() {
        return detectedAt;
    }

    public Instant getFixedAt() {
        return fixedAt;
    }

    public String getDutyName() {
        return dutyName;
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentRepository.java
package example.gameday.journal;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.UUID;

public interface IncidentRepository extends JpaRepository<Incident, UUID> {

    List<Incident> findByDutyName(String dutyName);

    List<Incident> findByFixedAtIsNull();

    @Query("select i from Incident i where i.dutyName = ?1 and i.fixedAt is null order by i.detectedAt")
    List<Incident> findOpenOf(String dutyName);
}
```

```java
// src/main/java/example/gameday/journal/IncidentLog.java
package example.gameday.journal;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;
    private final IncidentRepository incidents;

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock, IncidentRepository incidents) {
        this.roster = roster;
        this.notifier = notifier;
        this.clock = clock;
        this.incidents = incidents;
    }

    public void add(String title) {
        Incident incident = incidents.save(new Incident(title, clock.instant(), roster.currentDuty()));
        notifier.send(incident.getDutyName(), title + " — detected at " + incident.getDetectedAt());
    }

    @Transactional
    public void fixAll(List<UUID> ids) {
        Instant now = clock.instant();
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("no incident " + id));
            incident.fix(now);
            incidents.save(incident);
        }
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class IncidentTest {

    // a frozen "now" for every test in the class
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Test
    void newIncidentIsOpen() {
        Incident incident = new Incident("staging is not responding", T0, "duty-1");

        assertThat(incident.getId()).isNull();                 // the key appears on save
        assertThat(incident.getTitle()).isEqualTo("staging is not responding");
        assertThat(incident.getDetectedAt()).isEqualTo(T0);
        assertThat(incident.getDutyName()).isEqualTo("duty-1");
        assertThat(incident.getFixedAt()).isNull();
    }

    @Test
    void fixRemembersTime() {
        Incident incident = new Incident("staging is not responding", T0, "duty-1");

        incident.fix(T0.plusSeconds(600));

        assertThat(incident.getFixedAt()).isEqualTo(T0.plusSeconds(600));
    }

    @Test
    void cannotFixTwice() {
        Incident incident = new Incident("staging is not responding", T0, "duty-1");
        incident.fix(T0.plusSeconds(600));

        assertThatThrownBy(() -> incident.fix(T0.plusSeconds(900)))
                .isInstanceOf(IllegalStateException.class);
        assertThat(incident.getFixedAt()).isEqualTo(T0.plusSeconds(600));   // the first time is untouched
    }

    @Test
    void cannotFixBeforeDetected() {
        Incident incident = new Incident("staging is not responding", T0, "duty-1");

        assertThatThrownBy(() -> incident.fix(T0.minusSeconds(1)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(incident.getFixedAt()).isNull();
    }

    @ParameterizedTest(name = "{0}, {1}, {2} → rejected")
    @CsvSource(delimiter = '|', nullValues = "null", textBlock = """
            null    | 2026-10-05T09:15:00Z | duty-1
            ''      | 2026-10-05T09:15:00Z | duty-1
            '   '   | 2026-10-05T09:15:00Z | duty-1
            staging | null                 | duty-1
            staging | 2026-10-05T09:15:00Z | null
            staging | 2026-10-05T09:15:00Z | '   '
            """)
    void rejectsMissingParts(String title, Instant detectedAt, String dutyName) {
        assertThatThrownBy(() -> new Incident(title, detectedAt, dutyName))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentRepositoryIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentRepositoryIT {

    // a frozen "now" for every test in the class
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void findsOnlyOpen() {
        // save returns the entity with its key already set
        Incident open = incidents.save(new Incident("staging is not responding", T0, "duty-1"));
        Incident fixed = new Incident("the queue is growing", T0, "duty-2");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);

        assertThat(incidents.findByFixedAtIsNull())
                .extracting(Incident::getId)
                .containsExactly(open.getId());
    }

    @Test
    void findsByDutyName() {
        Incident first = incidents.save(new Incident("staging is not responding", T0, "duty-1"));
        Incident second = incidents.save(
                new Incident("emails are not going out", T0.plusSeconds(300), "duty-1"));
        incidents.save(new Incident("the queue is growing", T0, "duty-2"));
        assertThat(incidents.findByDutyName("duty-1"))
                .extracting(Incident::getId)
                .containsExactlyInAnyOrder(first.getId(), second.getId());   // no order by, order may vary
    }

    @Test
    void findsOpenOfDutyOldestFirst() {
        Incident later = incidents.save(
                new Incident("emails are not going out", T0.plusSeconds(300), "duty-1"));
        Incident earlier = incidents.save(new Incident("staging is not responding", T0, "duty-1"));
        Incident fixed = new Incident("the queue is growing", T0, "duty-1");
        fixed.fix(T0.plusSeconds(60));
        incidents.save(fixed);
        incidents.save(new Incident("disk is full", T0, "duty-2"));
        assertThat(incidents.findOpenOf("duty-1"))
                .extracting(Incident::getId)
                .containsExactly(earlier.getId(), later.getId());            // the order is set in @Query
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentLogIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentLogIT {

    // in the past: fixAll takes "now" from the real clock
    private static final Instant T0 = Instant.parse("2026-09-01T09:15:00Z");

    @Autowired
    private IncidentLog log;

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void addStoresIncident() {
        log.add("staging is not responding");

        assertThat(incidents.findByDutyName("duty-1"))                       // duty-1 is set in GameDayConfig
                .extracting(Incident::getTitle)
                .containsExactly("staging is not responding");
    }

    @Test
    void fixAllRollsBackWhenOneIdIsUnknown() {
        List<UUID> ids = new ArrayList<>();
        for (String title : List.of("staging is not responding", "the queue is growing",
                "emails are not going out")) {
            ids.add(incidents.save(new Incident(title, T0, "duty-1")).getId());
        }
        ids.add(UUID.randomUUID());

        assertThatThrownBy(() -> log.fixAll(ids))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("no incident");
        assertThat(incidents.findByFixedAtIsNull()).hasSize(3);
    }
}
```
