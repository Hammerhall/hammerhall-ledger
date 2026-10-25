# Spring Boot 4 for absolute beginners

> "From Java to Spring Boot" · Article 2 · 25 min read
>
> **Who it's for.** You've read Articles 0 and 1 and set up the `game-day`
> sandbox from start.spring.io. You haven't touched Spring Boot yet.
>
> **What's inside.** How Boot starts and what it does for you; which
> Boot 4 starters you'll meet in the real project, and where the internet
> still calls them by their old names; how the application gets its
> settings from a file, a profile, and the environment, and checks them on
> startup.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why Spring Boot

In Article 1 we started the container for the Game Day journal ourselves,
in `GameDayApp`, and described the beans without `@Component` in
`GameDayConfig`. For four beans, that's bearable.

A real service needs more: a web server, converting records to JSON,
a database, metrics, settings for staging and for production (the servers
real users work with). Behind each of these are dozens of beans that have
to be created and wired correctly. By hand, that's hundreds of beans and
a week of reading documentation, all before the first line of your own
code.

**Spring Boot** is Spring with ready-made defaults. Think of a furnished
apartment: you can live there from day one, and if you don't like the
wardrobe, you bring your own and the old one gets taken away. The
container, beans, injection: it's all the same as in Article 1.

In the real project, everything runs on Boot: the clock from Article 1,
the settings, the web layer, and the database. This article is about that
foundation.

The running example is the same journal in the same sandbox. We'll move it
to Boot and give it settings for the game: how long it lasts, what the
stop word is, and how many attackers there are.

---

## Part 1. How Boot starts

### The application class

A Boot application has an **application class** with a `main` method. In
the sandbox, Initializr created it: it's `GameDayApplication`, the class
Article 1 asked you not to touch. Now it's in charge. Add to its `main`
what you had in `GameDayApp`:

```java
@SpringBootApplication                                             // "this is a Boot application"
public class GameDayApplication {

    public static void main(String[] args) {
        var context = SpringApplication.run(GameDayApplication.class, args);   // start everything
        context.getBean(IncidentLog.class).add("Broker is not responding");    // peek inside, as in Article 1
    }
}
```

As in Article 0, the short examples have no `import` lines; you'll find
them in the full example at the end.

`var` means "work out the variable's type yourself." `SpringApplication.run`
does what `new AnnotationConfigApplicationContext(GameDayConfig.class)` did
in Article 1, and more: it reads the settings, turns on auto-configuration
(more on it below), and starts the web server if the project has one.

`@SpringBootApplication` says three things: this class is a configuration,
like `GameDayConfig`; look for classes with `@Component`, `@Service`, and
`@Configuration` (it counts as a component too) in this class's package
and in every package below it, like `@ComponentScan`; and turn on
auto-configuration.

That's why the application class goes in the **root package**: the
topmost package of the project, the one that holds all the others. In the
sandbox, the root is `example.gameday`. That's where `GameDayApplication`
lives, and the journal from Article 1 is in `example.gameday.journal`,
inside the root, so Boot will find it on its own. The real project works
the same way.

⚠️ Scanning won't see a class in a package **next to** the root, say
`example.tools`. If some constructor asks for it, startup fails with an
error like "Parameter 0 of constructor in … required a bean of type '…' that could not be found." If nobody asks for it, it silently never appears, even
though `@Component` is right there.

### The journal on Boot

What to change in the sandbox:

* in `example.gameday.journal`, delete `GameDayApp` and `HandMadeApp`:
  `GameDayApplication` starts the context now, and there should be only
  one `main`;
* in `GameDayConfig`, remove `@ComponentScan`: `@SpringBootApplication`
  does the scanning now, and it will find `GameDayConfig` itself, since
  that class is inside the root. The `DutyRoster` and `Clock` beans stay.

Run `GameDayApplication` with the green triangle next to `main`. First, the lines Boot prints about its own work scroll by: that's the
**log**. Don't confuse it with our Game Day journal: the journal is about
incidents, the log is about the application itself. After the log comes
something familiar:

```
[notification] duty-1: Broker is not responding — detected at 2026-10-05T09:15:03.512704831Z
```

The journal is assembled; it's just that Boot started the context this
time. Then the application exits. That's expected: the sandbox has no web
server, so nothing needs to wait for requests.

### Auto-configuration

How does Boot know which beans are needed besides yours? It looks at what
the project includes.

**Auto-configuration** is a set of ready-made `@Configuration` classes
inside Boot, except that they come with conditions. The rule: **if the
project has the starter for technology X and you haven't made your own
bean, Boot makes its own.**

An example from the real project. Add the web starter, and Boot's module
for Jackson (the JSON library from Article 0) comes along with it. Boot
creates a `JsonMapper` bean, Jackson's main object, by itself, and you can
ask for it in a constructor. You can also add Jackson on its own, as
a separate dependency, the way the `pom.xml` in Article 0 does. But
without the Boot module, nobody creates the bean; Part 2 explains why.

In the same way, with the web starter, Boot starts Tomcat (a web server,
more on it below). And with the Flyway starter, it applies migrations on
startup: Flyway is a library that changes database tables using migration
scripts.

🔑 **Your bean wins.** Declare your own `JsonMapper` bean, and Boot won't
make one. That's the "don't like the wardrobe? bring your own" part.

⚠️ Online, to replace the mapper, people declare an `ObjectMapper` bean
from `com.fasterxml.jackson.databind`. That's Boot 2–3 and Jackson 2.
Jackson 3 has an `ObjectMapper` class too
(`tools.jackson.databind.ObjectMapper`), but Boot no longer treats a bean
of that type as a replacement: you need exactly `JsonMapper` from
`tools.jackson.databind.json`.

### The embedded web server

A **web server** is a program that listens on a network port, accepts
requests (from a browser or from another program), and passes them to the
application. Requests are covered in detail later in the series.

It used to be that you installed the server on a machine separately and
put the application inside it: two programs, two versions, and the eternal
"it works on my machine, but not there." Boot turns this around: **the
server lives inside the application, not the application inside the
server.** The server is just one more library in the `.jar`; the
application starts it and stays up, waiting for requests.

**Tomcat** is the web server Boot embeds by default. Course projects don't
have one: their programs run in the console. At work, a service answers
over the network, so it always needs a server. You don't install Tomcat:
it arrives with the `spring-boot-starter-webmvc` starter and starts on its
own, inside `SpringApplication.run`. The startup log will have a line
about it with the port number.

`./mvnw package` builds a single `.jar`: the code, the libraries, and
Tomcat, if there is one. **Deploying** means putting that file on
a machine and running `java -jar`; that's how the service is started on
staging. In the sandbox:

```bash
./mvnw package
java -jar target/game-day-0.0.1-SNAPSHOT.jar      # the name comes from artifactId and version in pom.xml
```

---

## Part 2. Boot 4 starters

### Why the starters got smaller

It's the starter (remember: a set of libraries bundled as one dependency) that turns
auto-configuration on. In Boot 4, Boot itself is split into small
**modules**, one per technology. A technology's auto-configuration lives
in its module, and the module is brought in by the
`spring-boot-starter-<technology>` starter; no starter, nothing to
configure. That leads to two changes people trip over: technologies that
used to need only a third-party library now need a starter; and the test
tools have moved out into `spring-boot-starter-<technology>-test`
starters.

### Starters you'll meet in the real project

A **test slice** is a test that starts a single layer instead of the whole
application; slices are covered later in the series. In the real project, nobody writes database slice tests (`@DataJpaTest`): repositories are tested
against a real database.

**Actuator** is a set of built-in endpoints where the application reports
on itself. You start a program from a course yourself and can see that
it's running; a service on staging runs without you, and something has to
keep asking it "are you alive?" **Probes** are two such checks: "the
process is alive" (liveness) and "ready to accept requests" (readiness).
Actuator comes with the `spring-boot-starter-actuator` starter; the
sandbox doesn't have it. In an application with Actuator and the web
starter, open `http://localhost:8080/actuator/health`: `"status":"UP"` in
the response means "alive."

| starter | what it brings | ⚠️ online (Boot 2–3) → in Boot 4 |
|---|---|---|
| `spring-boot-starter-webmvc` | web: Spring MVC, Tomcat, Jackson | `spring-boot-starter-web` → deprecated |
| `spring-boot-starter-validation` | validation (Part 3); not part of `webmvc` | — |
| `spring-boot-starter-actuator` | Actuator | probes are turned on with a setting → on by default |
| `spring-boot-starter-data-jpa` | working with the database | — |
| `spring-boot-starter-flyway` **and** `org.flywaydb:flyway-database-postgresql` | migrations; Postgres support for Flyway | just `flyway-core` → migrations **silently** don't run |
| `spring-boot-starter-<technology>-test` | test slices | "it's all in `spring-boot-starter-test`" → each technology has its own |

All of them have the `groupId` `org.springframework.boot`, except Flyway
for Postgres; `<parent>` fills in the versions, as in Article 0.

In the real project, a mid-level developer adds dependencies (Article 0);
in the sandbox, you do it yourself. If a tutorial or an LLM suggests
a starter, check its name against the table.

---

## Part 3. Settings

### Why settings live outside the code

The stop word changes for every game. Staging has four attackers, while on
your machine two are plenty. Hard-code the values, and every change needs
a new build. That's why they live outside the code, in **settings**:
named values the application reads on startup. One build, different
values on different machines.

### application.yml and the YAML format

Settings live in `src/main/resources`, the folder for files that aren't
code but still go into the `.jar`. Initializr put `application.properties`
there: delete it and create `application.yml`. The real project uses
YAML, and two formats in one project only cause confusion.

**YAML** is a "key: value" text format where nesting is shown with
indentation:

```yaml
hammerhall:                      # level 1
  game-day:                      # level 2: two spaces deeper
    stop-word: test-stop-word
    attackers: 4                 # the full key: hammerhall.game-day.attackers
```

* indent with spaces only; keys at the same level get the same indent;
* everything after `#` is a comment, like `//` in Java;
* a setting's full name is its path joined with dots:
  `hammerhall.game-day.attackers`. That's what tasks and tests call it:
  `hammerhall.game-day.attackers=4`;
* in YAML, names are written with hyphens (`stop-word`); in Java, in camel
  case (`stopWord`). Boot matches them up itself.

⚠️ Indentation is part of the meaning. Move the last line, `attackers`,
two spaces to the left, and it becomes `hammerhall.attackers`, a setting
nobody reads. You won't get an error: Boot silently uses the default.

### Profiles: a set for each machine

A **profile** is a named set of settings for one environment. Next to
`application.yml` you put `application-<profile>.yml` files. When
a profile is active, Boot reads both files, and where a key is in both,
the profile file wins.

```yaml
# application.yml — for all environments
hammerhall:
  game-day:
    stop-word: test-stop-word    # so you can run it locally
```

```yaml
# application-stand.yml — only with the stand profile
hammerhall:
  game-day:
    attackers: 4                 # four attackers on staging
```

Without a profile there are two attackers (that's the default, more on it
below); with the `stand` profile, four. You turn a profile on with the
`spring.profiles.active` setting, usually as a launch argument (in the
IDE, that's the Program arguments field in the run configuration):

```bash
java -jar target/game-day-0.0.1-SNAPSHOT.jar --spring.profiles.active=stand
```

You can't set `spring.profiles.active` inside a profile file. The real
project has three files: `application.yml` for all environments,
`application-stand.yml` for staging, and `application-prod.yml` for
production.

### Environment variables on top of the file

The real stop word doesn't belong in the repository: a new word shouldn't
require a new build.

An **environment variable** is a named value the system passes to
a program when it starts; it lives on the machine, not in the repository.
You set it before launching: in a terminal or Git Bash, with
`export GAME_DAY_STOP_WORD=…`; in the IDE, in the Environment variables
field of the run configuration. Settings can pick it up in two ways.

**With a placeholder in the file.** Spring replaces `${NAME}` with the
variable's value:

```yaml
# application-stand.yml
hammerhall:
  game-day:
    attackers: 4
    stop-word: ${GAME_DAY_STOP_WORD}   # on staging: from the environment
```

Now the application won't start with the `stand` profile unless this variable is set. That's intentional: it's the safeguard from "The trap" below.

That's how every secret works in the real project: in
`application-prod.yml`, passwords, keys, and tokens have nothing but
`${NAME}`. 🔴 A placeholder can have a default after a colon,
`${NAME:value}`, but secrets never get one: forget the variable, and
production quietly starts with the password from the repository.
A separate test guards this rule.

**Without a placeholder.** A variable that matches a key overrides the
value from both files. The name is built like this: replace the dots with
`_`, drop the hyphens, and make everything uppercase:
`hammerhall.game-day.attackers` → `HAMMERHALL_GAMEDAY_ATTACKERS`. You can
turn a profile on this way too: the variable `SPRING_PROFILES_ACTIVE=stand`
does the same as the `--spring.profiles.active=stand` argument.

### Settings in a record: @ConfigurationProperties

Reading settings one at a time, by a name string, in every class means
scattering names across the code and catching typos during the game. Boot
offers another way: all the game settings go in one record, and Boot fills
it in on startup.

```java
@ConfigurationProperties("hammerhall.game-day")    // prefix: where the game settings live
public record GameDayProperties(
        @DefaultValue("3h") Duration length,        // if not set: 3 hours
        String stopWord,                            // no default: it's different for every game
        @DefaultValue("2") int attackers) {         // if not set: two
}
```

* `"hammerhall.game-day"` is the **prefix**: for each field of the
  record, Boot looks for the setting `hammerhall.game-day.<field name>`;
* Boot calls the record's constructor itself and passes in values
  converted to the right type: the string `4` to an `int`, `3h` to
  a `Duration`. This is **constructor binding**: there are no setters,
  and the settings don't change after startup;
* `Duration` is Java's type for a length of time: `3h` is three hours,
  `90m` is ninety minutes, `30s` is thirty seconds. ⚠️ A number without
  a letter means milliseconds: `length: 3` is three thousandths of
  a second;
* `@DefaultValue("3h")` is the **default**, used when the setting is missing entirely. It sits right next to the rule, so a test with no settings sees the same thing the application does.

⚠️ Online you'll see `@ConstructorBinding` above a record like this.
That's Boot 2. A record with one constructor doesn't need it.

**How Boot finds the record.** Put the `@ConfigurationPropertiesScan`
annotation next to `@SpringBootApplication`: "find all settings records
and fill them in." Like component scanning, it searches from the
application class's package downward. Put the record in `example.gameday`,
next to `GameDayApplication`: these are settings for the whole
application. In the real project, the annotation sits on the application
class.

⚠️ Don't put `@Component` on the record. Spring would create it as an
ordinary bean and look for beans of type `Duration` and `int` to pass to
the constructor, and it wouldn't find any. A record is filled in from the
settings only if `@ConfigurationPropertiesScan` or
`@EnableConfigurationProperties` (you'll meet it in the test) found it.

A settings record is a bean too: another bean asks for it as a constructor
parameter, like any dependency. Let's peek into it from `main`:

```java
var gameDay = context.getBean(GameDayProperties.class);
System.out.println("game " + gameDay.length() + ", attackers " + gameDay.attackers());
```

Without a profile, you get `game PT3H, attackers 2` (`PT3H` is how Java
writes three hours). With the `stand` profile and the `GAME_DAY_STOP_WORD`
variable, `attackers 4`; add `HAMMERHALL_GAMEDAY_ATTACKERS=6`, and it's 6.
We don't print the stop word: values from the environment don't go into
the log.

💡 Exercise: move the on-call name, the `"duty-1"` in `GameDayConfig`,
into the settings. Hint: a `@Bean` method can ask for beans as parameters
too.

### Checking on startup: @Validated

Say someone sets `attackers: 0`, and you get a game with no attackers. Or `length: 5m`, and the game is over before it starts. The application starts anyway, and the
error gets noticed in the middle of Game Day.

🔑 **A bad setting stops the startup, not the game.** Finding out about it
at launch, with the setting's name, is cheaper than finding out three
hours later.

Validation needs a library. Add the starter to the sandbox's `pom.xml` (on
start.spring.io it's called Validation):

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
```

```java
@ConfigurationProperties("hammerhall.game-day")
@Validated                                                               // turn validation on
public record GameDayProperties(
        @DefaultValue("3h") @DurationMin(minutes = 30) Duration length,  // at least 30 minutes
        @NotBlank String stopWord,                                       // set, and not just spaces
        @DefaultValue("2") @Min(1) int attackers) {                      // at least one
}
```

* `@Validated` tells Boot to check the annotations on the fields of the
  filled-in record. ⚠️ Without it, `@Min` and `@NotBlank` are just
  decoration: nobody checks them.
* `@NotBlank` and `@Min(1)` come from Jakarta Validation, the Java
  standard for validation; the package is `jakarta.validation.constraints`.
* ⚠️ `@DurationMin` isn't part of the standard: it comes from Hibernate
  Validator, package `org.hibernate.validator.constraints.time`. An import
  from `jakarta` won't find it.
* ⚠️ In old tutorials, the same annotations come from `javax.validation`.
  That's Boot 2. Boot 4 doesn't support `javax.*`, only `jakarta.*`.

**Hibernate Validator** is the library that actually runs these checks:
the annotations only describe the rules. In course projects, checks are
written with `if`s; at work there are dozens of rules, and it's handier
to declare each one with an annotation next to the field. The library
comes with the starter above, and Boot calls it on startup for every
record with `@Validated`. Set `attackers: 0`, and the application won't
start; the log will show something like this:

```
APPLICATION FAILED TO START
…
    Property: hammerhall.game-day.attackers
    Value: "0"
    Reason: …
```

For `stop-word`, the `Property:` line will say `stopWord`, the field's name in Java.

💡 In a unit test, the record is created with a plain `new`. Then only
the compact constructor runs (you'll see it below); the annotations are
checked and the defaults filled in by Boot, on startup. That's why you
pass all three values to `new`.

### ⚠️ The trap: the environment variable wasn't substituted

On staging, the file says `stop-word: ${GAME_DAY_STOP_WORD}`, and someone
forgot to set the variable before the game. Surely `@NotBlank` will catch
that? It won't.

When filling in a settings record, Spring leaves a placeholder it couldn't
resolve as is: `stopWord` receives the literal string
`${GAME_DAY_STOP_WORD}`. It isn't blank, so `@NotBlank` lets it through.
The team lead says the stop word, and the game doesn't stop: the "right"
stop word is now `${GAME_DAY_STOP_WORD}`.

The fix is the compact constructor from Article 0. It goes inside the
`GameDayProperties` record, after the header, just like in `TaskKey`:

```java
public GameDayProperties {
    if (stopWord != null && stopWord.contains("${")) {          // the placeholder was left as is
        throw new IllegalArgumentException("hammerhall.game-day.stop-word: "
                + "stop word is not set: the environment variable was not substituted");
    }
}
```

* The error text has the setting's name and the reason, so whoever is on
  staging immediately sees what to set.
* `stopWord != null &&` is there because the constructor runs **before**
  the `@Validated` checks. If the stop word isn't set at all, `null`
  comes in, and without this check `stopWord.contains` would throw
  a `NullPointerException` that says nothing about the setting. With it,
  `null` passes through, and `@NotBlank` rejects it, naming the setting.

Try it: run with the `stand` profile and no variable. The application
won't start, and the log will contain our text.

💡 The compact constructor is the record's one and only constructor, not
a second one. `@ConstructorBinding` still isn't needed.

🔴 In the real project, every secret in a settings record is protected
this way: passwords, keys, tokens.

### How to test the settings

**`ApplicationContextRunner`** is a test tool that builds a small Spring
context right inside the test, from only the classes and settings you
name. Starting the whole application just to check the settings is slow,
while the runner answers in a fraction of a second: does the context
start, and what's in the beans? It comes with `spring-boot-starter-test`
and runs like any JUnit test. In the real project, every settings record
is tested this way.

The runner doesn't read `application.yml`: the test sees only
`withPropertyValues` and `@DefaultValue`. That's why the defaults live in
the record.

```java
class GameDayPropertiesTest {

    @Configuration                                             // configuration for this test only
    @EnableConfigurationProperties(GameDayProperties.class)    // "create this record and fill it in"
    static class Config {
    }

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(Config.class);              // the context comes from Config only

    @Test
    void appliesDefaults() {
        runner.withPropertyValues("hammerhall.game-day.stop-word=test-stop-word")
                .run(context -> {                              // the context is built: check it
                    GameDayProperties gameDay = context.getBean(GameDayProperties.class);
                    assertThat(gameDay.length()).isEqualTo(Duration.ofHours(3));
                    assertThat(gameDay.attackers()).isEqualTo(2);
                });
    }

    @Test
    void rejectsUnresolvedStopWord() {
        // a name that is definitely not in the environment; otherwise Spring would substitute the real value
        runner.withPropertyValues("hammerhall.game-day.stop-word=${GAME_DAY_TEST_UNSET_STOP_WORD}")
                .run(context -> {
                    assertThat(context).hasFailed();           // the context didn't start
                    assertThat(context.getStartupFailure())
                            .hasStackTraceContaining("the environment variable was not substituted");
                });
    }
}
```

* `Config` is a class inside the test class; only the test needs it. In
  the application, `@ConfigurationPropertiesScan` finds the record; here,
  `Config` says the same thing explicitly;
* `run(context -> …)` is a lambda, as in Article 0: it receives the
  context, whether it started or not. `getBean` is fine in a test, since
  that's how you peek into the context; in production code, only the
  constructor;
* `hasFailed()` means "the context didn't start"; `hasStackTraceContaining`
  looks for the text in the startup error and in all its causes, because
  Spring wraps the error in several layers. Before you write a check like
  this, print `context.getStartupFailure()` once and read all of it.

That's the technique: one test for "it started," one for "it didn't." How
many tests you need, and which ones, is up to the task's table.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. Why can't you put `@Component` on a settings record, and how does Boot
   find it?
2. Why does the application class sit in the root package? What happens
   to a class that sits next to the root?
3. Explain auto-configuration. Why is there no `JsonMapper` bean without
   the web starter, even though Jackson is in `pom.xml`? How do you
   replace a bean that Boot made?
4. "The server lives inside the application, not the application inside
   the server": what does that mean, and what does it give you when you
   deploy?
5. A tutorial tells you to add `flyway-core` and `spring-boot-starter-web`.
   What's wrong with that in Boot 4, and who adds dependencies in the real
   project?
6. The `attackers` key is in `application.yml`, in `application-stand.yml`,
   and in the environment. Which value does the application get with the
   `stand` profile?
7. Why do you need `@Validated` if `@Min` and `@NotBlank` are already
   there? Why isn't `@DurationMin` imported from `jakarta`?
8. On staging, someone forgot the stop word variable. Why won't
   `@NotBlank` save you, what will, and why is `stopWord != null` there?

---

## What's next

The settings are in place and the application starts: time to store data.
That's what the next two articles are about: first a table, a Flyway
migration, and a test against a real database; then an entity,
a repository, and a transaction.

## Sources

* [Spring Boot: Externalized Configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html):
  YAML, the order of sources, environment variable names, records with
  `@ConfigurationProperties`, validation, how to write a `Duration`;
* [Spring Boot: Profiles](https://docs.spring.io/spring-boot/reference/features/profiles.html):
  how to turn profiles on;
* [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide):
  modules, new starter names, what moved where. The best answer to "why
  won't this tutorial build?"

---

## The full example, with imports

A learning example. Run it in the `game-day` sandbox from Article 1. In
`example.gameday.journal`, `DutyRoster`, `Notifier`, `ConsoleNotifier`,
and `IncidentLog` are from Article 1, unchanged; `GameDayApp`,
`HandMadeApp`, and `application.properties` are deleted; `pom.xml` has
the Validation starter. Initializr's `GameDayApplicationTests` test starts
the whole application with `application.yml`, which is why it needs the
stop word in the shared file too.

```java
// src/main/java/example/gameday/GameDayApplication.java
package example.gameday;

import example.gameday.journal.IncidentLog;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class GameDayApplication {

    public static void main(String[] args) {
        var context = SpringApplication.run(GameDayApplication.class, args);
        context.getBean(IncidentLog.class).add("Broker is not responding");

        var gameDay = context.getBean(GameDayProperties.class);
        System.out.println("game " + gameDay.length() + ", attackers " + gameDay.attackers());
    }
}
```

```java
// src/main/java/example/gameday/journal/GameDayConfig.java
package example.gameday.journal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
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
// src/main/java/example/gameday/GameDayProperties.java
package example.gameday;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.hibernate.validator.constraints.time.DurationMin;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;
import org.springframework.validation.annotation.Validated;

import java.time.Duration;

@ConfigurationProperties("hammerhall.game-day")
@Validated
public record GameDayProperties(
        @DefaultValue("3h") @DurationMin(minutes = 30) Duration length,
        @NotBlank String stopWord,
        @DefaultValue("2") @Min(1) int attackers) {

    public GameDayProperties {
        if (stopWord != null && stopWord.contains("${")) {
            throw new IllegalArgumentException("hammerhall.game-day.stop-word: "
                    + "stop word is not set: the environment variable was not substituted");
        }
    }
}
```

```yaml
# src/main/resources/application.yml
hammerhall:
  game-day:
    stop-word: test-stop-word
```

```yaml
# src/main/resources/application-stand.yml
hammerhall:
  game-day:
    attackers: 4
    stop-word: ${GAME_DAY_STOP_WORD}
```

```java
// src/test/java/example/gameday/GameDayPropertiesTest.java
package example.gameday;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThat;

class GameDayPropertiesTest {

    @Configuration
    @EnableConfigurationProperties(GameDayProperties.class)
    static class Config {
    }

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(Config.class);

    @Test
    void appliesDefaults() {
        runner.withPropertyValues("hammerhall.game-day.stop-word=test-stop-word")
                .run(context -> {
                    GameDayProperties gameDay = context.getBean(GameDayProperties.class);
                    assertThat(gameDay.length()).isEqualTo(Duration.ofHours(3));
                    assertThat(gameDay.attackers()).isEqualTo(2);
                });
    }

    @Test
    void rejectsUnresolvedStopWord() {
        // a name that is definitely not in the environment; otherwise Spring would substitute the real value
        runner.withPropertyValues("hammerhall.game-day.stop-word=${GAME_DAY_TEST_UNSET_STOP_WORD}")
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure())
                            .hasStackTraceContaining("the environment variable was not substituted");
                });
    }
}
```
