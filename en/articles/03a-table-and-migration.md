# Data, part 1: a table and a migration

> "From Java to Spring Boot" · Article 3a · 30 min read
>
> **Who it's for.** You've read Articles 0–2 and set up the `game-day`
> sandbox: it has beans, Boot settings, and JUnit tests. Your SQL goes as
> far as `SELECT`. We'll install Docker along the way.
>
> **What's inside.** Three things: how to describe a table in SQL so that
> the database itself guards the rules; how to change a database's
> structure the same way on every database at once, with migrations and
> Flyway; and how to check a migration with a test against a real
> Postgres, with Docker and Testcontainers.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why a database, and why nobody edits its structure by hand

The Game Day journal from Article 1 doesn't store incidents; it only
sends notifications. Put them in a list in the program's memory, and after
a restart the list is empty. And applications restart all the time:
a deployment, a crash, a server reboot. Data that has to survive
a restart is kept in a database.

The catch is that a project has more than one database.
There's one on your machine, one in every test run, one on staging, and
one in production. They all have to be structured the same way.

Changing their structure by hand means "log in and fix it." That's a sure
road to drift: you fixed yours, forgot staging, made a typo in
production. You find out during a deployment, the most expensive way
there is.

The "Data" topic takes two articles. In this one, the journal gets
a table, a migration, and a test against a real database. In the second
part, Java learns to work with the table: entity, repository,
transaction.

---

## Part 1. The database and the table

### PostgreSQL

**PostgreSQL** (Postgres for short) is a database server program: it
stores tables and runs SQL queries.

**What it's for.** In courses, you install a database for one evening.
A real service needs a database that's set up the same way everywhere
the service runs.

**How you get it.** You don't need to install it: Postgres is started in
a Docker container with a single command, shown below. In tests, the
database is started by Testcontainers; that's Part 3.

**Where to look.** With the `psql` client from the same container, or in
the database window of your IDE.

### Docker

**Docker** is a program that runs other programs in isolated boxes
called **containers**. A container is started from an **image**,
a ready-made snapshot of a program: from the `postgres:17-alpine` image you can start Postgres 17 on a tiny Linux (Alpine) in seconds, and remove the container afterwards without a trace. The container here is Docker's, not Spring's:
it shares only the name with the Spring container from Article 1.

On Windows and macOS, Docker is installed as **Docker Desktop**
(docs.docker.com, the Get Docker section); on Linux, as Docker Engine.
Install it, start Docker Desktop, and check in a terminal:

```bash
docker version
```

The `Server` part of the output is Docker itself, the part that runs
containers. If it's missing and there's a connection error instead,
Docker Desktop isn't running. Images and containers are covered in detail
in Article 6, "Build your own staging environment."

### Postgres for a minute

```bash
docker run -d --rm --name game-day-db -p 127.0.0.1:5432:5432 \
    -e POSTGRES_PASSWORD=game-day-local postgres:17-alpine
docker exec -it game-day-db psql -U postgres
```

* `-d`: run in the background; `--rm`: remove the container, data and
  all, when it stops; `--name`: a name to use in the next commands;
* `-p 127.0.0.1:5432:5432`: port 5432 on your machine leads to the
  database port in the container, and only from your machine. If the port
  is taken (you already have Postgres installed), pick a different one on
  the left: `127.0.0.1:5433:5432`;
* `-e POSTGRES_PASSWORD=…`: an environment variable (Article 2), the
  password for the `postgres` user; the image won't start without it;
* `docker exec -it … psql -U postgres`: run `psql` inside the container;
  `-it` lets you type. If Git Bash answers `the input device
  is not a TTY`, add `winpty` at the start of the command.

No connection? Wait a couple of seconds: the database is waking up. Type
SQL after `postgres=#` and end it with `;`; to quit, type `\q`. In your
IDE, connect to `127.0.0.1:5432` as the `postgres` user.

### Schema and role

Inside a database, tables are grouped into **schemas**. A schema is
a named folder for tables: a table's full name is `schema.table`. If you
don't name a schema, the table lands in the default one, usually
`public`. A database **role** is the account a program logs in to the
database with, and it has its own permissions: which schemas it sees and
what it can do in them.

In the real project, the application has its own schema and its own
role, and that role can't see other schemas or `public`. In production,
several applications often live in one Postgres. A role of its own keeps
the application from touching other applications' tables, even by accident: like
having your own room in a shared apartment and a key to that room only.
The role has exactly the permissions the work needs, and no more.

In the sandbox, the application does get its own schema, `game_day`, but no role of its own: the container has one user with all permissions, which is
enough for a learning database.

Rule: write the schema name explicitly, `game_day.incident`, not
`incident`. Otherwise the table ends up wherever the connection settings
point, and that's guesswork.

### The incident table

A table is created with the `CREATE TABLE name (…)` command: inside the
parentheses, separated by commas, come the columns: name, type, rules.
Rules for the whole table can come at the end.

```sql
CREATE TABLE game_day.incident (
    id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    title        VARCHAR(200)  NOT NULL CHECK (btrim(title) <> ''),
    detected_at  TIMESTAMPTZ   NOT NULL,
    fixed_at     TIMESTAMPTZ   NULL,
    duty_name    VARCHAR(50)   NOT NULL,
    CONSTRAINT incident_fixed_after_detected
        CHECK (fixed_at IS NULL OR fixed_at >= detected_at)
);
```

Part 2 covers where to put this SQL. For now, line by line:

* `PRIMARY KEY`: the **primary key**, the column that identifies a row
  unambiguously. The database won't let a duplicate or an empty value
  into it;
* `UUID`: the key's type, a 128-bit identifier like
  `5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e`. Unlike the numbers 1, 2, 3, it
  can't be guessed. And it can be created anywhere, even in Java before
  the row is written. In the real project, our own identifiers are
  `UUID`s; numbers and names that come from someone else's system are
  stored as they are;
* `DEFAULT gen_random_uuid()`: the value used when none is passed, so the database generates the key itself (in the second part, Java will create keys too; that's also where you'll see why we need both);
* `VARCHAR(200)`: a string of at most 200 characters. The database won't
  accept a longer one;
* `NOT NULL`: a value is required. `NULL` on `fixed_at` is an explicit
  "may be empty": empty means not fixed yet;
* `CHECK (…)`: a **check constraint**, a condition the database checks on
  every write. `btrim` strips spaces at both ends, so a title made of
  nothing but spaces won't pass either;
* the last `CHECK` looks at two columns at once: nothing can be fixed before it's detected. `CONSTRAINT …` gives the check a name, and the
  database will use that name in the error.

Try it in `psql`. In this one-minute database, create the schema by hand
with `CREATE SCHEMA game_day;`. Then run the whole `CREATE TABLE` and
insert a row where the fix came before the detection:

```sql
INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
VALUES ('staging is not responding', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1');
```

```
ERROR:  new row for relation "incident" violates check constraint "incident_fixed_after_detected"
```

🔑 Checks in the table are the last line of defense: even if someone
forgot the rule in code, the database won't accept a broken row. An error
caught by the database beats quietly corrupted data.

### Time: TIMESTAMPTZ and Instant

A **time zone** is local time's offset from Coordinated Universal Time
(UTC): 12:15 in Moscow and 09:15 UTC are the same moment. Postgres has
two types for time:

* `TIMESTAMP` stores "the clock on the wall," say `12:15`, and doesn't
  know whose wall it was. A server on UTC wrote it, a laptop on Moscow
  time read it, and now you can't tell when the incident was really
  detected;
* `TIMESTAMPTZ` stores a **moment**: on write, Postgres converts the time
  to UTC; on read, it shows it in the time zone of whoever is asking.

Insert a proper row, without `fixed_at`, and look at it from two time
zones. `SET TIME ZONE` sets the zone for your connection only:

```sql
INSERT INTO game_day.incident (title, detected_at, duty_name)
VALUES ('staging is not responding', '2026-10-05T09:15:00Z', 'duty-1');

SET TIME ZONE 'UTC';
SELECT detected_at FROM game_day.incident;      -- 2026-10-05 09:15:00+00

SET TIME ZONE 'Europe/Moscow';
SELECT detected_at FROM game_day.incident;      -- 2026-10-05 12:15:00+03
```

In Java, a moment is the `Instant` from Article 1.
In the real project, pairing `TIMESTAMPTZ` with `Instant` is a rule.

Done looking? Quit (`\q`) and shut the database down:
`docker stop game-day-db`. With `--rm`, the container is removed along
with the schema and the table. From here on, they're created not by hand
but by Flyway.

### No foreign key to the on-call engineer

A **foreign key** (`REFERENCES`) is a database rule: "the value in this
column must be the key of a row in that table." The journal has
`duty_name VARCHAR(50)`, with no foreign key. The journal doesn't store
the list of on-call engineers: `DutyRoster` from Article 1 provides it,
and in the real project, the list of people usually lives in another service, with
its own database. On a local staging setup and in tests, that table
doesn't exist at all, and the application's role can't see other schemas:
there's nothing to reference. So the name is stored as a plain value.
Foreign keys go only between tables in your own schema: there, the
database itself makes sure no reference is left dangling.

---

## Part 2. Migrations and Flyway

### A migration is a numbered SQL file

The fix for the problem from the start of the article is to stop changing the
database's **structure** by hand: tables, columns, checks. Every such
change is written to a file and put in git next to the code. That file
is called a **migration**. Our first one is the `CREATE TABLE` from
Part 1:

```
src/main/resources/db/migration/
    V1__game_day_incident.sql      ← ours, the first in the sandbox
    V2__…                          ← the next change gets the next number
```

Migrations are like items in meeting minutes: they're numbered, new ones
go at the end, and what's written is never corrected. Run them all in
order, and you get the same database on any machine. A program runs them.

### Flyway

**Flyway** is a library that applies migrations to a database.

**What it's for.** In courses, tables are created by hand in a database
client, the way you just did in `psql`: while there's one database and
just you, that'll do. At work there are many databases and many people,
and only a machine can keep the databases identical. Flyway looks at
which migrations the database has already seen and applies only the new
ones, in version order, each exactly once.

It keeps track of this in its own history table, `flyway_schema_history`: the version, the description, and the
**checksum** of every applied migration. A checksum is a number computed
from the file's contents: change even a single letter, and the checksum
is different.

**How it gets into the project.** Through dependencies in `pom.xml`. In
the sandbox you add them yourself (in the real project, a mid-level
developer does, Article 0):

```xml
<dependency>                                <!-- database connection and JdbcTemplate (Part 3) -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-jdbc</artifactId>
</dependency>
<dependency>                                <!-- Flyway, and running it on startup -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-flyway</artifactId>
</dependency>
<dependency>                                <!-- Flyway for Postgres: the starter doesn't bring it -->
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
<dependency>                                <!-- the Postgres driver -->
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
```

**JDBC** is Java's standard way of talking to databases; a **driver** is
a library that teaches it a particular database's language.
`<scope>runtime</scope>`: the driver is needed by the running program,
not by the compiler. The versions are filled in by `<parent>`, as in
Article 0.

Flyway creates the schema itself; just name it in `application.yml`:

```yaml
spring:
  flyway:
    schemas: game_day        # create the schema if it's missing; keep the history in it
```

**How it runs.** By itself, when the application starts and when
database tests start: Spring Boot runs the migrations before the
application starts working with the database. Flyway writes what it did
to the startup log.

⚠️ Online you'll see that the `flyway-core` dependency is all Flyway
needs. That's Boot 2–3. Boot 4 needs the `spring-boot-starter-flyway`
starter. Without it, Flyway doesn't run and says nothing: the application
starts, but the table isn't there, and the very first query to it fails.

### File name and folder

Read the name `V1__game_day_incident.sql` like this: `V` means
a versioned migration; `1` is the version, which Flyway uses to put
migrations in order; `__` is **two** underscores; `game_day_incident` is
what the migration does, in lowercase letters separated by `_`; then
`.sql`. With a single underscore, Flyway won't recognize the file as
a migration and simply won't see it: there will be no table.

The folder is `src/main/resources/db/migration`: that's where Flyway
looks for migrations by default. In the real project, a separate rules
test checks the names, versions, and schema in every migration file.
There, a mistake like this is caught by the build, not by a deployment.

### First run

Start a clean database with the same `docker run` as in Part 1. The
application learns where the database is from its settings; set them
with environment variables, like the stop word in Article 2:

```bash
./mvnw package -DskipTests        # build without tests: database tests need Part 3
export SPRING_DATASOURCE_URL=jdbc:postgresql://127.0.0.1:5432/postgres
export SPRING_DATASOURCE_USERNAME=postgres
export SPRING_DATASOURCE_PASSWORD=game-day-local
java -jar target/game-day-0.0.1-SNAPSHOT.jar
```

`SPRING_DATASOURCE_URL` is the `spring.datasource.url` setting, the
database's JDBC address: server, port, and database name (the image
created the `postgres` database itself). In your IDE, the same three variables go in
the Environment variables field.

The log has a Flyway line, followed by the familiar output from
Article 2:

```
Successfully applied 1 migration to schema "game_day", now at version v1 (execution time …)
[notification] duty-1: Broker is not responding — detected at 2026-…Z
game PT3H, attackers 2
```

Look at the history in `psql` (`docker exec -it game-day-db psql -U postgres`):

```sql
SELECT version, description, checksum
FROM game_day.flyway_schema_history
ORDER BY installed_rank;
```

```
 version |         description          | checksum
---------+------------------------------+-----------
         | << Flyway Schema Creation >> |
 1       | game day incident            | 763185274
```

The first row is Flyway's marker: it created the `game_day` schema
itself. The second is our migration: the version, the description taken
from the file name, and the checksum. The history lives in the
`game_day` schema, the first one listed in `schemas`. Run the
application again, and the log will say `Schema "game_day" is up to date.
No migration necessary.`: the database has already seen this migration.

### 🔴 Never edit an applied migration

A migration has already run on staging, and you find a mistake in it.
It's tempting to fix the file: it's about the same thing, after all.
Don't. On the next start, Flyway compares the file's checksum with the
history, and they won't match. The application **won't start** on any
database where the migration has already been applied.

Try it on yours: in V1, after `duty_name`, add the line
`note VARCHAR(500) NULL,`, rebuild, and run. The application won't start:

```
Migration checksum mismatch for migration version 1
-> Applied to database : 763185274
-> Resolved locally    : 817377389
```

That's how a deployment once failed in the real project: someone added
one more column to a migration that had gone to production three hours
earlier.

The `flyway repair` command won't save you either: it rewrites the
checksum in the history but doesn't run what you added. The column won't
exist, and the code will fail the first time it touches it.

🔑 A database change is always a **new** migration: a mistake in V1 is
fixed by V2 with `ALTER TABLE …` (the SQL command that changes an
existing table). Until your pull request is merged, the file lives only
on your machine, and you can edit it. In tests, the database is new every
time, so an edit breaks nothing there. And if the migration has already
run on your database in the container, recreate the database:
`docker stop game-day-db`, then `docker run` again; thanks to `--rm`, the
old one goes away along with its history. Do that now: remove `note` from
V1 and recreate the database.

### The number is the next free one on the main branch

Take **the next free version number on the repository's main branch at
the time of your pull request**, not when you started the work: while
you were writing, someone may have merged a migration with the same
number. Git won't show a conflict, because the file names differ:
`V7__a.sql` and `V7__b.sql`. But Flyway won't accept two identical
numbers, and the application won't start. In the real project, whoever
merges second renames their file before merging.

---

## Part 3. Testing against a real database

### Why not an "in-memory database"

The migration needs testing: did it apply, and do the checks hold? Old
tutorials use H2 for tests like this, a database that lives right in
Java's memory and starts in an instant.

But H2 isn't Postgres: different SQL, different types, schemas, and
permissions. A migration written for Postgres may fail on H2, or pass but
behave differently: the test is green, and production fails. That's why
the database test runs against a real Postgres.

### Testcontainers

**Testcontainers** is a Java library that starts Docker containers from
test code and removes them afterwards.

**What it's for.** Tests need a database of their own: clean on every
run, the same version, on any machine: yours, a colleague's, and in the
pull request check. A database test from start to finish, from the
container to cleaning up after itself, is covered in
[Article 7, "A test with a real database"](https://hammerhall.io/en/ledger/testing/7-real-database) of the
"From Red to Green" series.

**How it gets into the project.** Two more dependencies, both for tests
only:

```xml
<dependency>                                <!-- glue between Testcontainers and Spring Boot -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-testcontainers</artifactId>
    <scope>test</scope>
</dependency>
<dependency>                                <!-- a Postgres container -->
    <groupId>org.testcontainers</groupId>
    <artifactId>testcontainers-postgresql</artifactId>
    <scope>test</scope>
</dependency>
```

**How it runs.** By itself, with the same `./mvnw verify`; Docker just
has to be running. The first run is slow: Docker downloads the image.
While the tests run, `docker ps` shows the Postgres container and
a helper container, Ryuk: it cleans up after the tests even if the run
was cut short. If Docker isn't running, the database tests fail right at
the start with the error `Could not find a valid Docker environment`.

⚠️ Online you'll see `org.testcontainers:postgresql` and the class
`org.testcontainers.containers.PostgreSQLContainer<?>` (`<?>` means "some
type parameter"). That's Testcontainers 1.x. Boot 4 uses 2.0: the
`testcontainers-postgresql` module and the class
`org.testcontainers.postgresql.PostgreSQLContainer`, without `<?>`.

### The container as a bean

The test needs an application connected to the container. For that, the
container is made a bean, in a separate configuration class next to the
tests:

```java
@TestConfiguration(proxyBeanMethods = false)                    // configuration for tests only
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection                                          // Spring finds the address and credentials
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");   // the image: same as in Part 1
    }
}
```

As before, the short examples have no `import` lines; they're in the full
example at the end.

* `@TestConfiguration`: the `@Configuration` from Article 1, but for
  tests only. `proxyBeanMethods = false` is a technical setting; Boot's
  documentation writes it this way, and it doesn't change what the
  example does;
* `@Bean` on a method, as in `GameDayConfig`: "here's how to create the
  object." Our bean is a Postgres container;
* `@ServiceConnection`: Spring itself asks the container for its address,
  username, and password and connects the application to it. You can't
  set them by hand: the container gets a new port every time.

Spring starts a container like this before the other beans, including
before Flyway, which needs the database. And it stops it together with
the application.

### The migration test

To put a row into the table, you don't need a Java class for the row
(that comes in the second part of the topic). **`JdbcTemplate`** is
a Spring helper that runs SQL from a string. Its `update` method is for
commands that change data; it returns the number of affected rows:

* `INSERT INTO table (columns) VALUES (values)`: add a row;
* `DELETE FROM table`: delete rows (without `WHERE`, all of them).

Boot creates the `JdbcTemplate` bean itself when the application has
a database and `spring-boot-starter-jdbc`.

```java
@SpringBootTest                                   // start the whole application
@Import(TestcontainersConfiguration.class)        // and connect it to Postgres in a container
class IncidentTableIT {

    @Autowired                                    // Spring puts the bean here
    private JdbcTemplate jdbc;

    @AfterEach                                    // after each test, clean up
    void cleanUp() {
        jdbc.update("DELETE FROM game_day.incident");
    }

    @Test
    void acceptsOpenIncident() {
        int inserted = jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, duty_name)
                VALUES ('staging is not responding', '2026-10-05T09:15:00Z', 'duty-1')
                """);                             // no id passed: DEFAULT comes up with one

        assertThat(inserted).isEqualTo(1);
    }

    @Test
    void rejectsFixBeforeDetection() {
        assertThatThrownBy(() -> jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
                VALUES ('staging is not responding', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1')
                """))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("incident_fixed_after_detected");    // this exact check fired
    }
}
```

How to read it:

* **`@SpringBootTest`**: "start the whole application for the test,"
  like `SpringApplication.run` from Article 2, Flyway included: by the
  first test, the table is already in place. It comes with
  `spring-boot-starter-test`; Initializr's `GameDayApplicationTests` is
  marked with it too;
* `@Import(TestcontainersConfiguration.class)`: add the container class
  to the application. A `@TestConfiguration` doesn't get into a test on
  its own: Spring deliberately doesn't pick it up, so that one test's
  settings don't spread to all of them;
* `@Autowired` on a field got a ⚠️ in Article 1: in application code,
  dependencies come only through the constructor. A test class is
  created by JUnit, and an `@Autowired` field is the usual way to get
  a bean into it;
* `@AfterEach`: a method JUnit runs after each test. There's one database
  for the whole run, and it lives on between test classes: whatever you
  inserted, delete. Otherwise someone else's test that counted on an
  empty table will fail;
* the SQL is written as a `"""` text block from Article 0, and the time
  as a string ending in `Z`: Postgres reads it as a moment in UTC on its
  own;
* Postgres reports a violated check as an error, and Spring turns it into
  the unchecked exception `DataIntegrityViolationException`
  (`org.springframework.dao`): "data integrity was violated."
  `hasMessageContaining` makes sure it was **our** check that fired, and
  not, say, `NOT NULL` because of a typo in the test. That's why checks
  get names.

This shows the technique, not the full set: in the real project, the
cases for a migration test are listed in a table in the task description,
and every row gets tested.

**Why there's one database per run.** Spring keeps the application it
started for a test in a **cache** and hands it to the next test class
with the same configuration: the same annotations, the same `@Import`.
One application means one container.

⚠️ A common mistake: a shared base test class with the `@Testcontainers`
annotation and a `static` field annotated with `@Container`. `@Testcontainers` is a **JUnit extension**, an add-on that JUnit calls before and after
tests: it starts the container before the test class and stops it after.
But Spring hands the application from the cache to the next class, still
connected to the stopped container. The tests hang and fail with
`Connection refused`, even though each class is green on its own.

In one real project, a base class with thirteen subclasses worked
exactly like that. After the fix, two test classes in a row took
29 seconds instead of 5 minutes 34 seconds. Boot's documentation
recommends a container bean, as here.

### *IT tests and Surefire

A test that checks code together with a real database is called an
**integration test**; in the real project, its class name ends in `IT`
(integration test). `*Test` classes run without a database, in
milliseconds, sometimes with a slice of Spring, like the
`ApplicationContextRunner` test from Article 2. `*IT` classes run with
a real Postgres, in seconds. The dividing line is the database, not
Spring.

Remember from Article 0: Maven finds tests by the ending of their names.
The one doing the finding is **Surefire**, the Maven plugin that calls
JUnit in the `test` phase; it comes with `<parent>`. By default it doesn't
pick up `*IT`: the test silently won't run, and the build will be green.
That's why the search patterns are set again in `pom.xml`, in
`<build><plugins>`:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <configuration>
        <includes>
            <include>**/*Test.java</include>
            <include>**/*Tests.java</include>       <!-- or the test from Initializr goes missing -->
            <include>**/*IT.java</include>
        </includes>
    </configuration>
</plugin>
```

Your own list **replaces** the defaults instead of adding to them. List
only `*Test` and `*IT`, and `GameDayApplicationTests` silently drops out:
it ends in `Tests`. That's why there are three patterns.

### Initializr's test now needs a database

`GameDayApplicationTests` starts the application, and the application now
has a database. Without its address, Spring Boot stops with the error
`Failed to configure a DataSource`: "can't set up the database
connection." So it gets one line, as in the migration test:

```java
@SpringBootTest
@Import(TestcontainersConfiguration.class)                      // the app no longer starts without a database
class GameDayApplicationTests {

    @Test
    void contextLoads() {
    }
}
```

`GameDayApplication` gives the same error if you run it without the
`SPRING_DATASOURCE_*` variables from Part 2.

Run `./mvnw verify`. Flyway applies `V1__game_day_incident.sql` to a real
Postgres, and both migration tests go green. The table exists. But Java
doesn't know anything about it yet, apart from a SQL string in the test.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. Why isn't a database's structure changed by hand, even when you need
   "just one column"? What does Flyway do instead, and how does it
   remember what has already been applied?
2. Migration V5 has already run on staging, and you find a mistake in it.
   What happens if you fix the file? What's the right way?
3. Take `title VARCHAR(200) NOT NULL CHECK (btrim(title) <> '')` apart piece by piece.
   Which three titles will the database reject?
4. How does `TIMESTAMPTZ` differ from `TIMESTAMP`? Why does it map to
   `Instant` in Java?
5. Why does the application need its own schema and its own database role
   with minimal permissions? Why is the schema name written explicitly,
   and why does `duty_name` have no foreign key?
6. You named the file `V7_game_day_incident.sql`. What happens, and how
   will you find out?
7. Why does the migration test run against a real Postgres in a container
   and not an in-memory database? What happens if Docker isn't running?
8. Why does `IncidentTableIT` need a method with `@AfterEach`, and why
   does a check in the table need a name? Why are there three Surefire
   patterns, not two?

---

## What's next

In the second part of the "Data" topic, the table becomes a Java class.
The journal learns to save and find incidents, and to apply several
changes at once on an "all or nothing" basis.

## Sources

* [Flyway: Versioned migrations](https://documentation.red-gate.com/fd/versioned-migrations-273973333.html):
  file names, ordering, checksums, and why you never edit what's been
  applied;
* [Flyway: Validate](https://documentation.red-gate.com/fd/validate-277578898.html):
  what exactly Flyway checks before running migrations;
* [Spring Boot how-to: Flyway](https://docs.spring.io/spring-boot/how-to/data-initialization.html#howto.data-initialization.migration-tool.flyway):
  where Boot looks for migrations and which dependencies you need;
* [Testcontainers: Postgres Module](https://java.testcontainers.org/modules/databases/postgres/):
  the Postgres module, and why the driver is added separately;
* [Spring Boot: Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html):
  the container bean, `@ServiceConnection`, and the warning about
  containers that stop before Spring evicts the application from its
  cache.

---

## The full example, with imports

A learning example. Run it in the `game-day` sandbox after Article 2:
the journal in `example.gameday.journal`, `GameDayApplication`,
`GameDayProperties`, `application-stand.yml`, `IncidentLogTest`, and
`GameDayPropertiesTest` stay unchanged. What to add: the dependencies and
Surefire in `pom.xml`, the migration, the Flyway lines in
`application.yml`, the container class, and the migration test; and in
`GameDayApplicationTests`, the `@Import` line. You need Docker running;
the first run downloads the `postgres:17-alpine` image.

```xml
<!-- pom.xml: into <dependencies> and <build><plugins>, next to what's already there -->
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

<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <configuration>
        <includes>
            <include>**/*Test.java</include>
            <include>**/*Tests.java</include>
            <include>**/*IT.java</include>
        </includes>
    </configuration>
</plugin>
```

```sql
-- src/main/resources/db/migration/V1__game_day_incident.sql
-- The Game Day journal: incidents detected by on-call engineers.
CREATE TABLE game_day.incident (
    id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    title        VARCHAR(200)  NOT NULL CHECK (btrim(title) <> ''),
    detected_at  TIMESTAMPTZ   NOT NULL,
    fixed_at     TIMESTAMPTZ   NULL,
    duty_name    VARCHAR(50)   NOT NULL,
    CONSTRAINT incident_fixed_after_detected
        CHECK (fixed_at IS NULL OR fixed_at >= detected_at)
);
```

```yaml
# src/main/resources/application.yml
spring:
  flyway:
    schemas: game_day
hammerhall:
  game-day:
    stop-word: test-stop-word
```

```java
// src/test/java/example/gameday/TestcontainersConfiguration.java
package example.gameday;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

/** A real Postgres in Docker: one for all the tests that import it. */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

```java
// src/test/java/example/gameday/GameDayApplicationTests.java — from Initializr, plus one line
package example.gameday;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class GameDayApplicationTests {

    @Test
    void contextLoads() {
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentTableIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentTableIT {

    @Autowired
    private JdbcTemplate jdbc;

    @AfterEach
    void cleanUp() {
        jdbc.update("DELETE FROM game_day.incident");
    }

    @Test
    void acceptsOpenIncident() {
        int inserted = jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, duty_name)
                VALUES ('staging is not responding', '2026-10-05T09:15:00Z', 'duty-1')
                """);

        assertThat(inserted).isEqualTo(1);
    }

    @Test
    void rejectsFixBeforeDetection() {
        assertThatThrownBy(() -> jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
                VALUES ('staging is not responding', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1')
                """))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("incident_fixed_after_detected");
    }
}
```
