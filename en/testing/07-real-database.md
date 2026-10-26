# A test with a real database

> "From Red to Green" · Article 7 · 30 min read
>
> **Who it's for.** You've read Articles 1–6 of this series: you write
> unit tests, choose cases, and replace the neighbors of your code with
> stubs. SQL at the `SELECT` level is enough. You don't need the "From
> Java to Spring Boot" series.
>
> **What's inside.** What only a real database catches and a stub never
> notices; how to start Postgres for a test with Docker, Testcontainers,
> Flyway, and Spring; how tests share one database without breaking each
> other.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Red to Green" series is about working
> with tests on a project: writing them, reading a red build, and trusting
> a green test only if you've seen it red. The examples are for learning:
> you can reproduce them yourself.

---

## Why a real database

In [Article 6, "When your code is surrounded by other code"](https://hammerhall.io/en/ledger/testing/6-stubs),
the `ScoreService` service calculated a score and recorded it on the
scoreboard, the `ScoreBoard` interface. In the test, the stub
`RememberingBoard` stood in for the board: it put every record into
a list, and we checked the list. The test is honest: it checks the
service, and the service is right.

But real scores aren't kept in a list; they're kept in a database. The
database has rules of its own: one score per task, and only three
possible scores: 0, 50, and 100. The stub doesn't know these rules. It
will accept and remember 70 points or a second score for the same task.
What the database will say, only the database knows.

Remember the pyramid from Article 1: hundreds of unit tests at the
bottom, and one floor up, dozens of integration tests, where code is
checked together with a real database. A unit test won't notice an error
in SQL: it has no database. This article is about that second floor. And
about the promise from Article 1, "a test cleans up after itself": here
you'll see why there's no way around it.

**The running example** is the same deadline scoring. A `score` table
appears, along with the `JdbcScoreBoard` class and its test
`JdbcScoreBoardIT`. The test runs against a real **PostgreSQL** (Postgres
for short). That's a database server: it stores tables and runs SQL
queries. You don't need to install it: Docker will start Postgres for the
test (more on Docker in Part 2).

---

## Part 1. What only the database sees

### The score table

A table is described in SQL with the `CREATE TABLE` command. The columns
go in parentheses, separated by commas, and each has a name, a type, and
rules.

```sql
-- src/main/resources/db/migration/V1__score.sql
CREATE TABLE score (
    student_id TEXT NOT NULL,
    task_key   TEXT NOT NULL,
    score      INT  NOT NULL CHECK (score IN (0, 50, 100)),    -- the rule knows no other scores
    PRIMARY KEY (student_id, task_key)                          -- one score per task
);
```

Line by line:

* `TEXT`: a string of any length;
* `INT`: an integer;
* `NOT NULL`: a value is required, it can't be left empty;
* `CHECK (…)`: a **check constraint**, a condition the database checks
  on every write. Here a score can only be 0, 50, or 100, as in the
  scoring rule;
* `PRIMARY KEY`: the **primary key**, the thing that identifies a row
  unambiguously. Here the key has two columns, so it's the **pair**
  "student and task" that can't repeat. The database won't let in a second
  score for the same task.

Where this file goes and why it has this name is covered in Part 2. The
sandbox keeps things simple: the table lives in the default **schema**,
and the keys are plain strings. A schema is a folder for tables inside
a database. In the real project, the application has its own schema, and
its name is written explicitly.
[Article 3a, "Data, part 1: a table and a migration"](https://hammerhall.io/en/ledger/articles/3a-table-and-migration)
of the "From Java to Spring Boot" cycle explains why.

### JdbcScoreBoard: scores in the database

```java
// src/main/java/example/testy/score/JdbcScoreBoard.java
/** The scoreboard in the database: the real implementation of what the tests in Article 6 replaced. */
@Repository
public class JdbcScoreBoard implements ScoreBoard {

    private final JdbcTemplate jdbc;

    public JdbcScoreBoard(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void record(String studentId, String taskKey, int score) {
        jdbc.update("INSERT INTO score (student_id, task_key, score) VALUES (?, ?, ?)",
                studentId, taskKey, score);
    }

    public Optional<Integer> scoreOf(String studentId, String taskKey) {
        return jdbc.queryForList("SELECT score FROM score WHERE student_id = ? AND task_key = ?",
                        Integer.class, studentId, taskKey)
                .stream()
                .findFirst();                                   // no row: empty
    }
}
```

The short examples have no `import` lines; the full files are at the end
of the article.

`@Repository` is an annotation for Spring: "make a bean out of this
class." A bean (Article 6) is an object Spring creates itself and hands
to whoever needs it.

**`JdbcTemplate`** is a Spring helper that runs SQL passed as a string.
It takes a database connection itself, sends the query, and reads the
answer. In courses, every query takes a dozen lines: open a connection,
run the query, read the result, don't forget to close it. Here it's one
line.

It comes with the **starter** `spring-boot-starter-jdbc`. A starter is
a set of libraries in one dependency, like `spring-boot-starter-test`
from Article 1. Our class gets its `JdbcTemplate` through the constructor.

* `update` is for commands that change data. `INSERT INTO … VALUES …`
  adds a row.
* `queryForList(…, Integer.class, …)` runs a `SELECT` and returns a list
  of the values of its only column, as `Integer` numbers.
  `.stream().findFirst()` takes the first element. If there isn't one,
  you get an empty `Optional` from Article 6.
* `?` is a placeholder for a value. The values themselves come after the
  SQL, in order, and `JdbcTemplate` puts them in correctly.

🔴 Values go in only through `?`. Never glue them into the SQL string.
A value that comes from outside can carry a piece of SQL, and the
database will run it as a command. That's how websites get broken, and
it's called **SQL injection**.

The `ScoreBoard` interface has no `scoreOf` method: the service has no
reason to read scores, but the test does.

### What only the database will catch

* **Constraints.** The stub will record 70 points and a second score, but
  the database will refuse: `CHECK` and `PRIMARY KEY` forbid them.
* **SQL errors.** A typo in a column or table name means nothing to
  a stub: it doesn't run SQL. The database answers with an error on the
  very first query.
* **Types.** A number or text, a time with a time zone or without one.
  Whether what Java sends matches the column shows only on a write.

🔑 **A stub answers what it was told to. A database answers what's really
there.** Everything that lives in SQL and in the table can be checked
only by a test against a real database.

Old tutorials use H2 for such tests, a database that lives in Java's
memory. We use the same Postgres as in production: a different database
has different errors.

---

## Part 2. How to start a database for a test

### Docker

**Docker** is a program that runs other programs in **containers**.
A container is a running program walled off from the rest of the
machine, already installed and set up. It's started from an **image**,
a ready-made snapshot of a program with everything it needs. An image is
like an installation disc, and a container is like a program run from
it that you don't mind throwing away. The `postgres:17-alpine` image is
Postgres 17 on a tiny Linux (Alpine).

**Why.** In courses, people install Postgres on their own machines, and
everyone has a different version plus leftovers from earlier runs.
A container is the same for everyone and clean every time.

**Where it comes from.** You install Docker once. On Windows and macOS,
it's Docker Desktop; on Linux, Docker Engine. Before the tests, it has to
be **running**. Images and containers are covered in detail in
[Article 6, "Build your own staging environment"](https://hammerhall.io/en/ledger/articles/6-stand)
of the "From Spring to a System" cycle.

**How to check.** The `docker ps` command prints the running containers.
If it answered without an error, Docker is alive. If Docker isn't
running, the database tests fail right at the start with the error
`Could not find a valid Docker environment`.

Here, the word "container" is only about Docker. A set of Spring beans
is always a **context** for us, as in Article 6 of this series.

### Testcontainers

**Testcontainers** is a Java library that starts Docker containers from
test code and removes them afterwards.

**Why.** So that the test gets a clean Postgres of the right version by
itself: on your machine, on a colleague's, and in the pull request check.

**Where it comes from.** Two dependencies with `<scope>test</scope>`, for
tests only (Article 1). `testcontainers-postgresql` provides the
`PostgreSQLContainer` class, a container with Postgres.
`spring-boot-testcontainers` connects it to Spring Boot. The whole piece
of `pom.xml` is in "The full example."

**How it runs.** By itself, with the same `./mvnw verify`. The first run
is slow: Docker downloads the image. While the tests run, `docker ps`
shows the `postgres:17-alpine` container and, next to it, a helper one,
the Testcontainers cleaner called Ryuk. After the run, neither is left.

⚠️ Online you'll see the `org.testcontainers:postgresql` dependency and
the class `org.testcontainers.containers.PostgreSQLContainer<?>`. The `<?>`
means "some type parameter." That's Testcontainers 1.x. We use 2.0: the
`testcontainers-postgresql` module and the class
`org.testcontainers.postgresql.PostgreSQLContainer`, without `<?>`.

### Flyway

Someone has to create the `score` table: before the first test, in every
new database. You can't do it by hand: the container lives only while
the tests run.

**Flyway** is a library that applies **migrations** to a database:
numbered SQL files, each of which changes the structure of the database.
Our first and so far only migration is `V1__score.sql`.

**Why.** So that every database, whether a test one, yours, or
production, gets the same structure from the same files. Flyway remembers
what has already been applied in its own table, `flyway_schema_history`.
It applies only what's new: in number order, each migration once.

**Where it comes from.** The `spring-boot-starter-flyway` starter and the
`flyway-database-postgresql` module, which the starter doesn't bring. You
also need the **driver** `org.postgresql:postgresql`: the library Java
uses to talk to Postgres. `<scope>runtime</scope>` on the driver means
it's needed by the running program, not by the compiler.

**How it runs.** By itself, when the application starts (or a test that
starts it), before the first database call. The test database is new
every time, so `V1__score.sql` is applied on every run.

**The file name** follows the pattern `V<version>__<description>.sql`.
`V` means "versioned migration," `1` is the number, then **two**
underscores, the description, and `.sql`. The folder is
`src/main/resources/db/migration`: that's where Flyway looks by default.
With one underscore, it simply won't see the file, and there will be no
table. A migration that has already run on a shared database isn't
edited; you write a new one. Article 3a explains why.

⚠️ Online you'll see that `flyway-core` is all Flyway needs. That's
Boot 2–3. We use Boot 4: without the starter, Flyway doesn't run and says
nothing. The error surfaces later, on the first query to a table that
doesn't exist.

### Spring in a test: the context

To check `JdbcScoreBoard`, you have to assemble it. It needs
a `JdbcTemplate`, which needs a database connection, and before the
first query Flyway has to create the table. By hand, that's dozens of
lines, and you wouldn't assemble it the way the application is assembled
in production.

That's what Spring does: it creates the beans itself and assembles them
into a context. **Spring Boot** is Spring with ready-made settings. It
sees a database in the project and makes the connection and the
`JdbcTemplate` by itself.

**In a test**, the context is started by the **`@SpringBootTest`**
annotation. The whole application is assembled, as on a real start: the
database connection, Flyway, `JdbcTemplate`, and `JdbcScoreBoard`. The
annotation comes with `spring-boot-starter-test`, which has been in the
sandbox since day one.

A bean gets into the test through a field with **`@Autowired`**:
"Spring, put a bean of this type here." In application code, dependencies
come through the constructor, as with `JdbcScoreBoard`. But a test class
is created by JUnit, not by you, and an `@Autowired` field is the usual
way for a test.

### The container as a bean

What's left is to tell Spring where the database is. For that, the
Postgres container is made a bean:

```java
// src/test/java/example/testy/TestcontainersConfiguration.java
/** A real Postgres in Docker: one for all the tests that import it. */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection                                          // Spring finds the address and credentials
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

* `@TestConfiguration` is a class with settings for tests only.
  `proxyBeanMethods = false` is a technical setting; Boot's documentation
  writes it this way. It doesn't change what the example does.
* `@Bean` on a method means "here's how to create the object; keep it as
  a bean." Our bean is the Postgres container.
* `@ServiceConnection`: Spring itself asks the container for its address,
  username, and password and connects the application to it. You can't
  set them by hand: the container gets a new port every time.

A container like this lives as long as the context. Spring starts it
before all the other beans, including before Flyway, which needs the
database. And it stops it when it closes the context.

These settings are connected to a test with the line
`@Import(TestcontainersConfiguration.class)`. A `@TestConfiguration`
doesn't get into a test on its own. Spring deliberately doesn't pick it
up, so that settings for some tests don't spread to all of them.

### One context, one container

Spring keeps started contexts in a cache and hands them to later tests
with the same configuration (Article 6). We have `@SpringBootTest` and
`@Import(TestcontainersConfiguration.class)` on two classes:
`JdbcScoreBoardIT` and the test from Initializr. The configuration is the
same, so there's one context, and one Postgres container for the whole
run.

Change the configuration of one of the classes: a different `@Import`,
a setting of its own, a `@MockitoBean` mock of its own. Spring will start
a second context for it, and a second container along with it.

⚠️ A common mistake: a shared base test class with the `@Testcontainers`
annotation and the container in a `@Container static` field. That's
a JUnit extension, like `MockitoExtension` in Article 6: it starts the
container before each test class and stops it after. But Spring keeps
the context in its cache longer and hands it to the next subclass,
connected to a container that's already stopped. Each class is green on
its own, but together they fail with `Connection refused`. Boot's
documentation recommends a container bean, as here.

### One container per run: how the team does it

On the team, the test database is set up differently, but the goal is
the same: one container per run. The integration tests there extend
a shared base class, and the container in it is a static field. It's
started once and not stopped after the class: there's no `@Container`
annotation there, and so no trap from above. At the end of the run, Ryuk
removes the container. The "application starts" test extends the
same class, for the same reason as our test below.

### The Initializr test now needs a database

In Article 1, we agreed not to touch the `TestyApplicationTests` test.
Now we have to change it, by one line:

```java
// src/test/java/example/testy/TestyApplicationTests.java — from Initializr, plus one line
@SpringBootTest
@Import(TestcontainersConfiguration.class)                      // without a database, the app won't start now
class TestyApplicationTests {

    @Test
    void contextLoads() {
    }
}
```

Its `contextLoads` test checks that the context starts. Now the
application has a database, and without its address the context won't
start. Spring Boot stops with the error
`Failed to configure a DataSource`, which means "I can't set up the
database connection." That's why `@Import` is needed here too. `TestyApplication` itself can't
be started without a database now either, but the sandbox doesn't need
that.

⚠️ Without Docker running, `TestyApplicationTests` turns red too, even
though it doesn't touch any tables: it needs the context, and the context
needs the container. A full `./mvnw verify` won't pass without Docker
anymore, even if you changed one line in `DeadlineScore`. If you see
`Could not find a valid Docker environment`, start Docker: your code has
nothing to do with it.

---

## Part 3. A test against a real database

### Four tests

```java
// src/test/java/example/testy/score/JdbcScoreBoardIT.java
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class JdbcScoreBoardIT {

    @Autowired
    private JdbcScoreBoard board;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void emptyTable() {
        jdbc.update("DELETE FROM score");                       // clean up BEFORE the test: no leftovers
    }

    @Test
    void recordedScoreCanBeReadBack() {
        board.record("student-1", "T-7", 50);

        assertThat(board.scoreOf("student-1", "T-7")).contains(50);
    }

    @Test
    void unknownTaskHasNoScore() {
        assertThat(board.scoreOf("student-1", "T-404")).isEmpty();
    }

    @Test
    void secondScoreForSameTaskIsRejected() {
        board.record("student-1", "T-7", 100);

        assertThatThrownBy(() -> board.record("student-1", "T-7", 50))
                .isInstanceOf(DuplicateKeyException.class);
    }

    @Test
    void scoreOutsideRuleIsRejectedByDatabase() {
        assertThatThrownBy(() -> board.record("student-1", "T-7", 70))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
```

* `recordedScoreCanBeReadBack`: we wrote 50 and read back 50. The
  simplest test, and already something a stub can't check: the `INSERT`
  and the `SELECT` are written without errors and look at the same
  columns.
* `unknownTaskHasNoScore`: there's no row, so the result is empty, not an
  error and not zero.
* `secondScoreForSameTaskIsRejected`: a second score for the same task.
  `assertThatThrownBy` from Article 4 means "I assert that this code throws an
  exception of this type."
* `scoreOutsideRuleIsRejectedByDatabase`: 70 points.
* `@BeforeEach` from Article 6: before each test, `DELETE FROM score`
  with no condition deletes all rows from the table. More on why below.

### What the database answers and how Java hears it

Postgres answers a broken rule with an error. In our two cases, it looks
like this:

```
ERROR:  duplicate key value violates unique constraint "score_pkey"
ERROR:  new row for relation "score" violates check constraint "score_score_check"
```

Postgres came up with the names `score_pkey` and `score_score_check`
itself, from the names of the table, the column, and the kind of
constraint. Besides the text, the error has a code, the **SQLSTATE**.
For a repeated key it's `23505`; for a broken check, `23514`. Codes
starting with `23` mean "data integrity violated."

Java gets the error from the driver as an `SQLException`, one exception
for every case. `JdbcTemplate` translates it into Spring exceptions by
the code. It turns `23505` into a `DuplicateKeyException`, and the other
`23…` codes into a `DataIntegrityViolationException`. The first is
a subclass of the second, a special case of it. Both live in the
`org.springframework.dao` package, and both are unchecked: the compiler
doesn't make you catch them.

💡 The fourth test checks only the type. But
`DataIntegrityViolationException` is also thrown for a repeated key. If
someone else's "student-1, T-7" row were in the table, the test would go
green even if the `CHECK` were gone. If you want it stricter, check the
text too, with `hasMessageContaining` from Article 4: the text contains
the name `score_score_check`.

### Red first

A database test can check nothing, like any other test (Article 5). So
break every new one. Remove the `CHECK (…)` from `V1__score.sql`, and the
70-point test should go red. Remove the `PRIMARY KEY` line and the comma
after `CHECK (…)`, and the second-score test goes red.

Now the SQL error that Article 6 promised. Make a typo in the `INSERT` in
`JdbcScoreBoard`: `scor` instead of `score` in the column list. The three
tests that write to the table go red. Only `unknownTaskHasNoScore` stays
green: it only reads. A stub wouldn't see such a typo at all.

Once they've gone red, put things back: now you can trust them when
they're green (Article 1). Editing the migration is fine here. The test
database is new every time, and no other database has seen this file
yet.

### Cleanup: before the test or after

The `score` table lives in one database for the whole run. A row one
test writes is left for the next one. Delete the `@BeforeEach` method,
and one of `recordedScoreCanBeReadBack` and
`secondScoreForSameTaskIsRejected` goes red, whatever the order.

Both write the score "student-1, T-7." Whichever runs second fails on its
very first write, before the check even happens, and in the report
that's `Errors` (Article 3). Which of the two fails depends on the order,
and JUnit doesn't promise an order (Article 2). This is exactly the
reason for "it's green on my machine but red in the build" from
Article 3: on your machine you run one test, while the build runs all
of them, in its own order.

We clean up **before** the test. Such a test starts with an empty table,
no matter who ran before it and what they left behind. That could be
a neighbor that forgot to clean up after itself, a test that failed
halfway through, or a cleanup step that failed. Cleanup **after**
protects you only if everyone else does it too, and without mistakes.

But cleanup before protects your test, not other people's. Your rows stay
after you and are left for the next test. In the sandbox, only
`JdbcScoreBoardIT` touches the `score` table, and cleanup before is
enough. Where dozens of classes write to shared tables, cleanup before
isn't enough; you need cleanup after too. Cleanup after alone is enough
only when it's shared by everyone and lives in the base class: then no
one leaves garbage behind.

🔑 **Cleaning up before yourself protects your test from other tests'
garbage. Only cleanup after protects other tests from your garbage.**

One more database rule. A row in one table can **reference** a row in
another; such a reference is called a **foreign key**. While the
reference exists, the database won't let you delete the row it points to.

### Cleanup for everyone

On the team, cleanup runs after every test, but for everyone at once. It
lives in the shared base class and can't be forgotten, so it's enough on
its own. It doesn't stop at "its own" tables: it empties every table in the application's
schema except the migration history.
The command for that is `TRUNCATE … CASCADE`: empty a whole table along
with the rows that reference it.

### The rows that broke other tests

In one real project, there's also one container per run, and two lessons
about cleanup were written down there.

The first lesson. A new test cleaned "its own" tables, but a neighboring
class had left a row in a table the new test "barely touched." The test
failed on its own insert with the error "this key already exists." On
its own, it was green.

The failure depended on what had run before it and looked like chance,
like the flaky test from Article 3. The conclusion: clean everything the
test touches.

The second lesson was louder. A test cleaned the database only before
itself. Its rows outlived it and referenced a shared table. That table's
rows could no longer be deleted.

After that, every test that cleaned that table failed: **341 errors,
and not one of them about the culprit.** The last test to fail looked
guilty, but the trail led from the first error. Now that test cleans up
both before itself and after.

---

## Part 4. Integration tests in the build

### Names and Surefire patterns

The database test is called `JdbcScoreBoardIT`, where `IT` stands for
integration test. Surefire, which runs tests in the `test` phase
(Article 1), doesn't pick up such names by default. That's why the
patterns in `pom.xml` are set again:

```xml
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-surefire-plugin</artifactId>
            <configuration>
                <includes>
                    <include>**/*Test.java</include>
                    <include>**/*Tests.java</include>       <!-- or the Initializr test goes missing -->
                    <include>**/*IT.java</include>
                </includes>
            </configuration>
        </plugin>
```

Your own list **replaces** the defaults instead of adding to them
(Article 1). List only `*Test` and `*IT`, and `TestyApplicationTests`
silently disappears: it ends in `Tests`. That's why there are three
patterns, and that's what the comment on the middle one is about.

The check is the same as in Article 1: after `./mvnw verify`, the report
should show exactly four more tests. Otherwise the build doesn't see some
class.

In the real project, there are two patterns, `*Test` and `*IT`, and the
database tests have one container for the whole run.

### What it costs

The database test itself runs fast. What's expensive is everything before
it: starting the container and the context, applying the migrations, and
the first time, downloading the image. You pay for it once per run, as
long as the tests share one configuration.

The pyramid from Article 1 doesn't change. The scoring rule is guarded by
the `DeadlineScore` unit tests, and the database test guards only what
lives in SQL and in the table. More complex tests, for a repository and
a transaction, are covered in
[Article 3b, "Data, part 2: entity, repository, transaction"](https://hammerhall.io/en/ledger/articles/3b-entity-and-transaction)
of the "From Java to Spring Boot" cycle.

### The contexts that ate the database

In one real project, tests nobody had touched started failing one day.
Green on their own, red together, with
`Failed to load ApplicationContext`. The cause was in the last
`Caused by:` (Article 3): the database refused the connection, "too many
clients."

Contexts in the cache live until the end of the run, and each
configuration has its own. Each one held its own database connections,
and the database hit its limit. And Spring doesn't retry a context that
failed to start once: one cause produced a lot of red.

The conclusion written down there: database tests are written with one
configuration. Every setting or mock of your own adds a context and
connections, and with a container bean, a container too.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. The service test with a stub from Article 6 is green. Why won't it
   tell you that the database won't accept 70 points, and which test will?
2. What are a Docker container and an image? What happens to the database
   tests and to `TestyApplicationTests` if Docker isn't running?
3. Who creates the `score` table in the test database, and when? What
   happens if you name the file `V1_score.sql`?
4. Why do `JdbcScoreBoardIT` and `TestyApplicationTests` get the same
   Postgres? What changes if one of them gets
   a `@MockitoBean`?
5. Why do a container in a `@Container static` field and Spring's context
   cache together give `Connection refused`?
6. Which tests go red from a typo in the `INSERT`, and which one stays
   green? Why wouldn't a stub notice this typo?
7. What does cleanup before a test protect, and what does cleanup after
   protect? Why is cleanup before enough in the sandbox? When is cleanup
   after alone enough for many classes with shared tables, and when are both needed?
8. The Surefire patterns are `*Test`, `*Tests`, and `*IT`. What disappears
   if you remove the middle one, and how do you notice?

---

## What's next

This is the last article of the "From Red to Green" series: from here on,
read the tests of your own project and the documentation from the
"Sources" of its seven articles.

## Sources

* [Spring Boot: Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html):
  containers as beans, `@ServiceConnection`, and why not `@Container static`;
* [Spring Framework: Context Caching](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html):
  what counts as "the same configuration" and when a context is started again;
* [Spring Framework: DAO Support](https://docs.spring.io/spring/reference/data-access/dao.html):
  how database errors become Spring exceptions;
* [Flyway: Versioned migrations](https://documentation.red-gate.com/fd/versioned-migrations-273973333.html):
  file names, order, and why what's been applied isn't edited;
* [Testcontainers: General Container runtime requirements](https://java.testcontainers.org/supported_docker_environment/):
  which Docker you need on Windows, macOS, and Linux.

---

## The full example, with imports

The learning example lives in the `testy` sandbox from Article 1. By this
article, it has everything from Articles 1–6: the deadline scoring and
its tests, the `ScoreService` service with the `ScoreBoard` interface,
and the JaCoCo plugin in `pom.xml`.
**The example won't run without Docker running**: on Windows and macOS
you need Docker Desktop, on Linux Docker Engine. Check with `docker ps`.
The first run downloads the `postgres:17-alpine` image, so give it time.

Add the dependencies and the Surefire setting to `pom.xml`. The
`<!-- … -->` lines mean: keep what was already there.

```xml
<!-- testy sandbox pom.xml: what Article 7 adds -->
<dependencies>
    <!-- … what was already there -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-jdbc</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-flyway</artifactId>
    </dependency>
    <dependency>
        <groupId>org.flywaydb</groupId>
        <artifactId>flyway-database-postgresql</artifactId>
    </dependency>
    <dependency>
        <groupId>org.postgresql</groupId>
        <artifactId>postgresql</artifactId>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-testcontainers</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.testcontainers</groupId>
        <artifactId>testcontainers-postgresql</artifactId>
        <scope>test</scope>
    </dependency>
</dependencies>

<build>
    <plugins>
        <!-- … spring-boot-maven-plugin and JaCoCo from Article 5, as before -->
        <plugin>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-surefire-plugin</artifactId>
            <configuration>
                <includes>
                    <include>**/*Test.java</include>
                    <include>**/*Tests.java</include>       <!-- or the Initializr test goes missing -->
                    <include>**/*IT.java</include>
                </includes>
            </configuration>
        </plugin>
    </plugins>
</build>
```

```sql
-- src/main/resources/db/migration/V1__score.sql
CREATE TABLE score (
    student_id TEXT NOT NULL,
    task_key   TEXT NOT NULL,
    score      INT  NOT NULL CHECK (score IN (0, 50, 100)),    -- the rule knows no other scores
    PRIMARY KEY (student_id, task_key)                          -- one score per task
);
```

```java
// src/main/java/example/testy/score/JdbcScoreBoard.java
package example.testy.score;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/** The scoreboard in the database: the real implementation of what the tests in Article 6 replaced. */
@Repository
public class JdbcScoreBoard implements ScoreBoard {

    private final JdbcTemplate jdbc;

    public JdbcScoreBoard(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    public void record(String studentId, String taskKey, int score) {
        jdbc.update("INSERT INTO score (student_id, task_key, score) VALUES (?, ?, ?)",
                studentId, taskKey, score);
    }

    public Optional<Integer> scoreOf(String studentId, String taskKey) {
        return jdbc.queryForList("SELECT score FROM score WHERE student_id = ? AND task_key = ?",
                        Integer.class, studentId, taskKey)
                .stream()
                .findFirst();                                   // no row: empty
    }
}
```

```java
// src/test/java/example/testy/TestcontainersConfiguration.java
package example.testy;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

/** A real Postgres in Docker: one for all the tests that import it. */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection                                          // Spring finds the address and credentials
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

```java
// src/test/java/example/testy/TestyApplicationTests.java — from Initializr, plus one line
package example.testy;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(TestcontainersConfiguration.class)                      // without a database, the app won't start now
class TestyApplicationTests {

    @Test
    void contextLoads() {
    }
}
```

```java
// src/test/java/example/testy/score/JdbcScoreBoardIT.java
package example.testy.score;

import example.testy.TestcontainersConfiguration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class JdbcScoreBoardIT {

    @Autowired
    private JdbcScoreBoard board;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void emptyTable() {
        jdbc.update("DELETE FROM score");                       // clean up BEFORE the test: no leftovers
    }

    @Test
    void recordedScoreCanBeReadBack() {
        board.record("student-1", "T-7", 50);

        assertThat(board.scoreOf("student-1", "T-7")).contains(50);
    }

    @Test
    void unknownTaskHasNoScore() {
        assertThat(board.scoreOf("student-1", "T-404")).isEmpty();
    }

    @Test
    void secondScoreForSameTaskIsRejected() {
        board.record("student-1", "T-7", 100);

        assertThatThrownBy(() -> board.record("student-1", "T-7", 50))
                .isInstanceOf(DuplicateKeyException.class);
    }

    @Test
    void scoreOutsideRuleIsRejectedByDatabase() {
        assertThatThrownBy(() -> board.record("student-1", "T-7", 70))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
```

Try it yourself:

1. Start Docker, then `./mvnw verify`: everything is green,
   `Tests run: 28` (24 after Article 6 plus four new ones). While the run
   is going, `docker ps` in another window shows one `postgres:17-alpine`
   container and Ryuk.
2. Remove `CHECK (score IN (0, 50, 100))` from `V1__score.sql`. Red:
   `scoreOutsideRuleIsRejectedByDatabase`. Put it back.
3. Remove the `PRIMARY KEY (student_id, task_key)` line and the comma
   after `CHECK (…)`. Red: `secondScoreForSameTaskIsRejected`. Put it back.
4. In `JdbcScoreBoard`, replace the `score` column in the `INSERT` with
   `scor`. Red: `recordedScoreCanBeReadBack`, `secondScoreForSameTaskIsRejected`,
   and `scoreOutsideRuleIsRejectedByDatabase`; only
   `unknownTaskHasNoScore` is green. Put it back.
5. Delete the `emptyTable` method together with `@BeforeEach`. One test
   is red, `recordedScoreCanBeReadBack` or `secondScoreForSameTaskIsRejected`,
   and it's in `Errors`. Put it back.
6. Remove `**/*Tests.java` from the patterns. The build is green, but
   `Tests run: 27`: `TestyApplicationTests` has vanished from the report. Put it back.
7. Stop Docker and run `./mvnw verify` again. Five tests that need the
   context are red: the four in `JdbcScoreBoardIT` and
   `TestyApplicationTests`. The log says
   `Could not find a valid Docker environment`. The other tests are green.
   Start Docker.

Now you know the main thing about these tests: each of them can go red,
and goes red exactly when the database stops guarding its rule. The stub
from Article 6 can't do that: it will accept both 70 points and a second
score.
