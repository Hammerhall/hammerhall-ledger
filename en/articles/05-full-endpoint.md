# The full endpoint: layers, access, paging, tests on every layer

> "From Java to Spring Boot" · Article 5 · 45 min read
>
> **Who it's for.** You've read Articles 0–4. In the `game-day` sandbox,
> the journal answers over HTTP: an endpoint that returns an incident by ID, the `IncidentService` service, its own errors, and the
> `IncidentControllerTest` slice with a Mockito mock. For now, anyone at
> all can call the endpoint.
>
> **What's inside.** Why an endpoint is split into layers, and why
> a record goes out instead of the entity. How to return a list page by
> page, and who's allowed to call it: login and roles with Spring
> Security. Which tests go on each layer, and how to show the endpoint
> working live.
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why split an endpoint into layers

In Article 4, the by-ID endpoint already went through the
`IncidentService` service, and the article promised to explain why.
A list makes the reason easier to see.

We need the endpoint `GET /game-day/incidents?page&size&open`. After Game
Day, the team lead pages through the journal, newest incidents first.
They may also want only the open ones. Only `admin` may call the endpoint. Put all
of that in the controller, and here's what ends up in a single method:

```java
@GetMapping("/game-day/incidents")
public Object list(Integer page, Integer size, boolean open) {
    // 1. HTTP: parse page and size, answer 400 to bad values
    // 2. access: is the person logged in, and are they admin
    // 3. data: which query to use and how to ask it for a page
    // 4. rules: "open" means no fixedAt; what to send out from the row
}
```

Four concerns, and each one has to be tested. Take a single rule:
"`open=true` means only open ones, otherwise all." To test it, you'd have
to start Spring, log in as `admin`, and send an HTTP request. If the test goes red, what broke: the path, the login, or the rule? A class like that
is hard to read and even harder to test.

The Game Day journal is a learning example. But in the real project,
almost every list endpoint is built this way: pages, a role, tests on
every layer, and a live demo. This article brings everything from the
series together in one endpoint.

The short examples have no `import` lines; the full files are at the end
of the article.

---

## Part 1. Layers

### Waiter, cook, storeroom

Picture a restaurant kitchen. The **waiter** takes the order, asks about
anything unclear, and brings the dish, but doesn't cook. The **cook**
knows the recipes: what to take and how to prepare it. But the cook never
goes out to the guests and doesn't care whether the order came from the
dining room or over the phone. The **storeroom** hands out ingredients
against a requisition slip and doesn't know what will be made from them.

An endpoint has the same three duties, called **layers**:

| layer | knows | doesn't know |
|---|---|---|
| controller: the waiter | path, parameters, statuses, JSON | tables and the rule "open means no `fixedAt`" |
| service: the cook | the rules: which query to use, what to send out; the transaction | HTTP: paths, `?page=`, response codes |
| repository: the storeroom | the table and the queries against it | who's asking and why |

🔑 **The controller turns HTTP into a service call and back. The rules
live in the service, the data in the repository.** Then each layer can be
tested on its own: the service without HTTP or a database, the repository
without HTTP, the controller without a database.

In the real project, each endpoint usually has its own controller and
service. A single class for all endpoints keeps growing, until you can no
longer tell what belongs to which endpoint. That's why the list gets its
own too: `IncidentListController` and `IncidentListService`. We leave the
code of the by-ID endpoint from Article 4 alone.

### The controller: HTTP only

```java
@RestController
public class IncidentListController {

    private final IncidentListService service;

    public IncidentListController(IncidentListService service) {   // the service, via the constructor
        this.service = service;
    }

    // access: admin only, set in the SecurityConfig security setup (Part 3)
    @GetMapping("/game-day/incidents")
    public PageBody<IncidentResponse> list(                             // a page of responses: Part 2
            @RequestParam(name = "page", required = false) Integer page,    // missing: null
            @RequestParam(name = "size", required = false) Integer size,
            @RequestParam(name = "open", defaultValue = "false") boolean open) {
        PageRequest pageRequest = Pages.request(page, size);            // defaults and 400 live there
        return service.list(pageRequest, open);                         // the service does the rest
    }
}
```

Three things matter here:

* `page` and `size` are `Integer` with `required = false`, like
  `Boolean open` in Article 4: a missing parameter arrives as `null`, and
  `Pages.request` knows the defaults (Part 2);
* `defaultValue = "false"`: if `open` is missing, it will be `false`.
  That's why it's `boolean` here, not `Boolean`: it's never `null`;
* there isn't a single `if` in the method. If a condition about the data
  shows up in the controller, a rule has leaked into the wrong layer.

On `?page=abc`, things never get as far as `Pages.request`. Spring itself
converts the string to `Integer` and answers with its own error: a `400`
in Boot's format, without our `code`, as with `?open=abc` in Article 4.
It's the same sandbox simplification.

### The service: rules and the transaction

```java
@Service
@Transactional(readOnly = true)                                    // read only, as in Article 4
public class IncidentListService {

    private final IncidentRepository repository;

    public IncidentListService(IncidentRepository repository) {
        this.repository = repository;
    }

    public PageBody<IncidentResponse> list(Pageable pageable, boolean openOnly) {   // "which page"
        Page<Incident> found;
        if (openOnly) {                                                // the journal's rule
            found = repository.findByFixedAtIsNullOrderByDetectedAtDesc(pageable);
        } else {
            found = repository.findAllByOrderByDetectedAtDesc(pageable);
        }
        Page<IncidentResponse> responses = found.map(IncidentResponse::of);   // entity → response
        return new PageBody<>(responses.getContent(), pageable.getPageNumber(), pageable.getPageSize(),
                responses.getTotalElements());                         // the page in our format
    }
}
```

`Page`, `Pageable`, and `PageRequest` are Spring Data's page types (Part
2); for now, read them as "give me page number N, and how many there are
in total." `map` is a ready-made method of the page. With the method reference `IncidentResponse::of` (Article 3b), it turns every row into
a response and leaves the "total" count as it was. `PageBody` is our page
format for the response; it's also covered in Part 2.

The service doesn't know the words "request" or "400." That's why you can
call it from an endpoint, from a scheduled job, or from a test with
a plain `new`.

**Where the transaction goes.** The service defines the unit of work: "give me a page" means rows plus a count. That's why
`@Transactional(readOnly = true)` goes on the service, as in Article 4,
and not on the controller or the repository (Article 3b).

**The journal's choice.** Here the journal made the decision for you.
There are two classes between HTTP and the database. `Pages` works out
"which page," and the service receives a ready `Pageable`, returns a ready
`PageBody`, and holds the fork on `open`. In a real task, questions like
these are decided by whoever does the task, and at review they'll be
asked why. From here on, such places are marked briefly: "the journal's
choice."

### A response record goes out, not the entity

Article 4 promised to explain why the endpoint returns a record. Here are
the reasons, shown on the journal:

* **Leaking fields.** Tomorrow someone adds an `attacker_note` column to
  the table: the team lead's note on how they broke staging. If the
  entity went out, the new field would land in the JSON on its own, and
  the on-call engineer would read the answer in the middle of the game.
  A record returns only what's listed in it.
* **Lazy associations**: related rows that JPA loads from the database
  only on first access (the journal has none). When converting to JSON,
  Jackson touches everything: extra database queries, or even an error.
* **The contract changes along with the table.** Rename a field of the
  entity, and the JSON changes for everyone who calls the endpoint.
  A response record is an agreement with the client, while the table is
  the application's internal business. They change separately.

The service converts the entity into a response. That way the entity
never leaves the service or the transaction (the journal's choice). 💡 The
conversion lives in one of two places: an `of` method on the response
record, as here, or a separate converter class, so that the response
record knows nothing about the entity or JPA. You'll see both in real
projects.

---

## Part 2. Paging

### Why page by page

Over a season of Game Days, a thousand incidents will pile up. In a single
response, that's a huge JSON, a slow request, and a screen that will show
twenty rows anyway. That's why lists are returned in **pages**: "page 0,
20 per page" means twenty rows plus the "total" count.

### Parameters: defaults and 400

If `page` is missing, it's 0; if `size` is missing, it's 20. A `page`
below zero gets a `400` with the code `page_number_invalid`; a `size`
outside 1..50 gets a `400` with the code `page_size_invalid`. It's one
rule for every list in the application. That's why it lives not in the
journal but in the root package, `example.gameday`, next to
`ErrorBody`. It's a small class, like `IncidentIds` from Article 4:

```java
public final class Pages {

    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 50;

    private Pages() {                                     // no objects needed, just the method
    }

    public static PageRequest request(Integer page, Integer size) {
        int number = 0;                                   // missing: the first page
        if (page != null) {
            number = page;
        }
        int rows = DEFAULT_SIZE;                          // missing: 20 per page
        if (size != null) {
            rows = size;
        }
        if (number < 0) {
            throw new InvalidInputException("page_number_invalid", "Page number must be 0 or greater");
        }
        if (rows < 1 || rows > MAX_SIZE) {
            throw new InvalidInputException("page_size_invalid", "Page size must be between 1 and 50");
        }
        return PageRequest.of(number, rows);              // "page <number>, <rows> rows per page"
    }
}
```

Bad numbers mean an `InvalidInputException` from Article 4: the handler
answers `400` in our format, with a code. They must be checked before
`PageRequest.of`. On `-1`, it throws an `IllegalArgumentException` itself,
and the client would get a `500`, "something broke on our side," instead of "the
request is invalid."

### The response: PageBody

There's one response format for every list in the application: the
`PageBody<T>` record, also in `example.gameday`:

```java
public record PageBody<T>(List<T> items, int page, int size, long total) {
}
```

```json
{"items":[…],"page":0,"size":20,"total":57}
```

`items` are the rows of the page, `page` and `size` are what was asked
for, and `total` is how many there are in all. The screen uses `total` to
draw the number of pages. `<T>` is a type parameter, as in
`JpaRepository<Incident, UUID>` (Article 3b): `PageBody<IncidentResponse>`
is a page of incident responses. When a list of on-call engineers shows
up, it'll be a `PageBody` of their responses, the same record. You saw
the empty `<>` in `new PageBody<>(…)` in Article 1: Java infers the type
from the arguments.

### How to ask the repository for a page

You pass "which page" as the last parameter of a repository method:
a `Pageable`, created by `PageRequest.of(number, size)`. The method
returns a `Page`, which holds the rows and the total count:

```java
public interface IncidentRepository extends JpaRepository<Incident, UUID> {

    // findByDutyName, findByFixedAtIsNull, findOpenOf: from Article 3b

    Page<Incident> findAllByOrderByDetectedAtDesc(Pageable pageable);            // all, newest first

    Page<Incident> findByFixedAtIsNullOrderByDetectedAtDesc(Pageable pageable);  // open only
}
```

`findAllBy` with no condition means "all rows": you need `By` even when
there's no condition. After it, `OrderByDetectedAtDesc` means "by
`detectedAt`, descending." The second method does have a condition,
`FixedAtIsNull`, as in `findByFixedAtIsNull` from Article 3b.

From the `Pageable`, Spring Data takes how many rows to skip and how many
to fetch. In the SQL that Hibernate sends to Postgres for the second page
and beyond, that's the tail `offset ? rows fetch first ? rows only`:
"skip this many rows, take the first that many." The rows of the page come
from `getContent()`.

The total count comes from `getTotalElements()`: Spring Data usually pays
for it with a second query, a `count`. It skips that query when the
number is already obvious. If a page came back short but not empty, it's
the last one. Then the total is how many were skipped plus how many came
back.

⚠️ `Page`, `Pageable`, and `PageRequest` come from
`org.springframework.data.domain`. Your IDE may suggest the JDK's
`java.awt.print.Pageable` first: that's the wrong one.

⚠️ `total` comes only from `getTotalElements()`, not from the length of
`items`: a page has 20 rows, but there may be 57 in all.

💡 Two rows can have the same `detectedAt`. The database doesn't promise
any order between them, and a row may jump to a neighboring page. The fix
is a second sort key: `…OrderByDetectedAtDescIdDesc`.

### The open filter and a page past the end

An open incident is one without `fixedAt`. The journal settled it this
way: `open=true` means only open ones; missing or `false` means all of
them, not "only closed." Nobody guesses rules like that; they're written
into the endpoint's contract.

A page past the end is `?page=5` when there are three incidents. The
repository returns empty rows and the real `total`. Whether to return
that as `200` or answer `404` is the journal's choice; it returns `200`
with an empty page.

---

## Part 3. Access

### Who's there, and are they allowed in

Right now the list, like the by-ID endpoint, can be called by anyone
who can reach port 8080. Article 4 promised that the journal is the
team's internal business and only `admin` will call it. For that, every
request needs two answers:

* **who's there** is a matter of **login** (authentication): the person
  proves they are who they claim to be;
* **are they allowed in here** is a matter of **access** (authorization):
  it's decided by the roles of whoever logged in.

In the real project, login works with a cookie (Article 4). A mid-level
developer writes it, once for all endpoints, and a junior uses it. In
their own endpoint, the junior only says whom to let in. In the sandbox,
login is simpler, but the questions are the same, and a single library
will answer them.

### Spring Security: a guard in front of the controller

**Spring Security** is a library that checks every request before it
reaches the controller: who's there, and are they allowed in.

**Why.** In courses, the check is written right in the method:
`if (!isAdmin(…))`. Ten endpoints means ten such `if`s, and one of them
is bound to be forgotten. A guard in front of all endpoints at once also
covers the ones somebody forgot. It's like the front desk of an office
building: badges are checked at the entrance, not at every office door.

**Where to get it.** The `spring-boot-starter-security` starter, plus its
own test starter for tests. Add them to the sandbox's `pom.xml`:

```xml
<dependency>                                <!-- security: login and access -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
<dependency>                                <!-- security in tests: the slice, login in a request -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security-test</artifactId>
    <scope>test</scope>
</dependency>
```

`<parent>` fills in the versions.

⚠️ Online, you'll see the dependency
`org.springframework.security:spring-security-test` for tests. That's
Boot 2–3. In Boot 4, Spring Security, like the web layer, has its own
test starter: `spring-boot-starter-security-test`. It brings in
`spring-security-test` by itself and, most importantly, plugs security
into the `@WebMvcTest` slice. Without it, the slice knows nothing about
security, and a test with our security configuration won't start.

**How it works.** Security is a set of **filters**: code that Tomcat runs
a request through before Spring MVC. If a filter refuses, the request
never reaches the controller or our error handler. Add just the starter,
with no configuration at all, and Boot locks down the whole application.
Every request has to come with a login, and there's a single user,
`user`. Boot generates a password at startup and prints it to the log:
`Using generated security password: …`. That's the default security. Our
own comes below, and with it this log line goes away.

### Logging in with Basic

**HTTP Basic** is the simplest way to log in over HTTP: the name and
password travel in every request, in the `Authorization` header:

```
Authorization: Basic YWRtaW46YWRtaW4tbG9jYWw=
```

After the word `Basic` comes the string `admin:admin-local` in
**base64**: a way to write any bytes with Latin letters and digits.
Nobody builds this header by hand. `curl` has the `-u admin:admin-local`
option for it, and tests have `httpBasic("admin", "admin-local")`
(Part 4). Not logged in, or the wrong password? Security answers `401`
with the header
`WWW-Authenticate: Basic realm="Realm", charset="UTF-8"`: "log in with
Basic, name and password in UTF-8."

🔴 base64 isn't encryption: `echo YWRtaW46YWRtaW4tbG9jYWw= | base64 -d`
prints the password. Anyone who sees the request sees the password too.
That's why Basic without HTTPS (encrypted HTTP) is fit only for your own
machine, like the sandbox on `localhost`.

The sandbox has two users, with the roles from Article 4: `admin`, who
may use the journal, and `viewer`, who is logged in but may not.

### Sandbox security: SecurityConfig

Security rules are beans in a configuration class, like `GameDayConfig`
from Article 1. Security is shared by the whole application, so the class
lives in the root package, `example.gameday`, next to
`ErrorHandler`:

```java
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain security(HttpSecurity http) {             // security rules
        http.authorizeHttpRequests(access -> access                         // who may go where
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()   // Boot's error body
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents").hasRole("admin")
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents/{id}").hasRole("admin")
                        .anyRequest().denyAll())                             // everything else: nobody
                .httpBasic(Customizer.withDefaults())                        // login: name and password
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS));   // no session, no cookies
        return http.build();
    }

    @Bean
    public UserDetailsService users() {                                   // who exists: users in memory
        return new InMemoryUserDetailsManager(
                User.withUsername("admin").password("{noop}admin-local").roles("admin").build(),
                User.withUsername("viewer").password("{noop}viewer-local").roles("viewer").build());
    }
}
```

Read it from top to bottom.

* `HttpSecurity` is a rule builder that Spring Security provides. The
  method builds a `SecurityFilterChain` from it: the chain of security
  filters. A bean of this type is a signal to Boot: security is custom,
  the default isn't needed.
* `authorizeHttpRequests` holds the access rules, each one "which
  requests → whom to let in." Security reads them in order, and the
  **first** rule that matches applies.
* `dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()` covers the
  forward to the internal `/error` address. Tomcat forwards Spring errors
  and security refusals there, and that's where Boot builds the response
  body (Article 4). A forward is a request too, and security checks it as
  well. The Spring Security docs advise opening it, so Boot can build the
  error response.
* `requestMatchers(HttpMethod.GET, "…").hasRole("admin")`: a `GET` to
  this path is let in only with the `admin` role. The path is exactly as
  in `@GetMapping`, with `{id}` for the by-ID endpoint. Whatever comes
  after `?` isn't part of the path: security looks only at the path.
* `anyRequest().denyAll()`: everything not allowed above is allowed to no
  one. The Spring Security docs recommend ending this way. The rules
  become a list of what's allowed, and an endpoint somebody forgot to add
  stays closed, not open.
* `httpBasic(Customizer.withDefaults())`: login with Basic, default
  settings.
* `sessionCreationPolicy(SessionCreationPolicy.STATELESS)`: no session.
  A **session** is the server's memory of who has already logged in: the
  server hands out a cookie and then recognizes the person by it. Basic
  doesn't need a session: the password comes with every request. That's
  why security hands out no cookie.
* `UserDetailsService` is where security gets its users: name, password,
  roles. `InMemoryUserDetailsManager` keeps them in memory, which is
  enough for the sandbox. `{noop}` before the password means "stored as
  is, not encoded": Spring Security requires you to say how a password is
  encoded.

🔴 Passwords in code belong only in a learning sandbox. Anyone who can see
the repository reads the code, and `{noop}` keeps the password in plain
text. In the real project there are no application passwords in code at
all: login there works with a cookie.

⚠️ Online, you'll see a class extending `WebSecurityConfigurerAdapter`,
rules set with `authorizeRequests()`, and configuration chains with
`.and()`. That's Spring Security 5, from Boot 2. Spring Security 7, which
Boot 4 brings, has none of this, and such code won't compile: the rules
are a `SecurityFilterChain` bean, built with `authorizeHttpRequests` and
lambdas, as above.

### Who gets in: one way to say it

There are two ways to say "this endpoint is for `admin` only": a line in
the shared security configuration, as we do, or an annotation on the
controller method, `@PreAuthorize("hasRole('admin')")`. Such annotations
are turned on by `@EnableMethodSecurity` on a configuration class.

In the real project, one way is chosen for the whole application, and
a new endpoint is declared the same way as its neighbors. Nobody invents
a second way: the reviewer checks access by eye, and that's possible only
if it's written the same way everywhere. The journal is the team's
internal business, so we let in only `admin`.

⚠️ The sandbox has one way, the security configuration, and that's no
accident. A refusal from `@PreAuthorize` is an exception thrown from
inside the controller method. Our `Exception` handler from Article 4
would catch it, and `viewer` would get a `500`, "something broke on our side,"
instead of `403`. A rule in the configuration fires before Spring MVC,
and the handler never sees the refusal.

### Refusal: login first, everything else after

`401` means not logged in or the wrong password; `403` means logged in
but not allowed. Sometimes `404` is returned instead of `403`
(Article 4), but the sandbox gives exact `401` and `403`. In the real
project, whoever writes the login decides how to answer "not allowed."
The endpoint's test checks exactly that status.

Security stands **before** the controller: a request without a login
gets `401`, even if it carries `?size=500`. That gives two rules for
tests. A `400` is tested while logged in as `admin`, and on a refusal you
make sure the service wasn't called. If the service was called on
a refusal, a stranger's request reached the data: it has already read the data or, on an endpoint that changes data, already changed it. The refusal
must happen earlier.

Notice what happened to an address that doesn't exist. In Article 4,
Spring answered `/game-day/nothing` with `404`. Now security answers
first: without a login, `401`; as `admin`, `403`, because `denyAll` fired.
Security doesn't know whether such an endpoint exists, and it won't give
a stranger a hint.

### A row in the perimeter table

The real project has a **perimeter test**. It checks every endpoint in the
application against the `DECLARED` table: method, path, and who gets in.
An endpoint without a row turns the test red. In the sandbox we'll set up
the same kind: `PerimeterTest` in `example.gameday`:

```java
@WebMvcTest                                                     // all the app's controllers, no database
class PerimeterTest {

    static final List<Endpoint> DECLARED = List.of(              // method, path, who gets in
            new Endpoint("GET", "/game-day/incidents/{id}", "admin"),
            new Endpoint("GET", "/game-day/incidents", "admin"));

    @Autowired
    private RequestMappingHandlerMapping mappings;               // Spring MVC: which method for which path

    @MockitoBean
    private IncidentService incidentService;                     // controllers need services: mocks

    @MockitoBean
    private IncidentListService incidentListService;

    @Test
    void everyEndpointIsDeclared() {
        List<String> found = new ArrayList<>();
        mappings.getHandlerMethods().forEach((mapping, handler) -> {
            if (handler.getBeanType().getPackageName().startsWith("example.gameday")) {   // ours only
                for (RequestMethod method : mapping.getMethodsCondition().getMethods()) {
                    for (String path : mapping.getPatternValues()) {
                        found.add(method + " " + path);                    // "GET /game-day/incidents"
                    }
                }
            }
        });
        List<String> declared = new ArrayList<>();
        for (Endpoint endpoint : DECLARED) {
            declared.add(endpoint.method() + " " + endpoint.path());
        }
        assertThat(found).containsExactlyInAnyOrderElementsOf(declared);   // the same ones, any order
    }

    record Endpoint(String method, String path, String role) {
    }
}
```

* `@WebMvcTest` with no controller in parentheses is a slice with all of
  the application's controllers (Article 4). The services are mocks:
  without them, the controllers can't be created.
* `RequestMappingHandlerMapping` is a Spring MVC bean that remembers which
  controller method answers which HTTP method and path.
  `getHandlerMethods()` is that whole list. `forEach((mapping, handler) -> …)`
  walks through it in pairs, "address → controller method": the lambda
  has two parameters.
* The package check filters out endpoints that aren't ours, such as
  Boot's own `/error`.
* `containsExactlyInAnyOrderElementsOf` means "the same rows, in any
  order." An extra endpoint or an extra row turns the test red, and the
  test says which one.
* `record Endpoint` inside the class is a record just for this test.

The list has its own row: `new Endpoint("GET", "/game-day/incidents", "admin")`.
The path is exactly as in `@GetMapping`, without `?page&size`; the
by-ID endpoint has its own row, with `{id}`. The test doesn't check
the "who" column. The reviewer checks it against how access is written in
`SecurityConfig`.

🔴 An endpoint without declared access is a door somebody forgot about.
In the sandbox, `denyAll` locks such a door, and the row in `DECLARED`
makes every endpoint declare itself. If an endpoint shows up without
a row, the perimeter test goes red.

---

## Part 4. Tests for every layer

### The pyramid

A **unit test** is the kind from Article 3b: one class, no Spring, no
database. It runs in milliseconds. A web layer test and an `*IT` take
seconds (the first run with Docker takes longer); a demo takes minutes of manual work. That's why tests are arranged in a **pyramid**: many
cheap ones at the bottom, few expensive ones at the top. Kinds of tests
and the pyramid are covered in detail in
[Article 1, "Why tests, and what the project expects from you"](https://hammerhall.io/en/ledger/testing/1-why-tests)
of the "From Red to Green" series.

```
             demo on your machine              one, by hand
          end-to-end: database + real login    one per endpoint
       repository *IT on a real database       a few
    controller web test                        one test per response
service and record unit tests                  many
```

### Mockito without Spring

You know Mockito mocks from Article 4: there, `@MockitoBean` made the
service mock inside Spring. Only one thing is new: Mockito without
Spring. A service unit test doesn't start Spring. Mockito is plugged in
as a JUnit extension (Article 3a), with the
`@ExtendWith(MockitoExtension.class)` annotation on the test class.
Before each test, it creates the mocks and puts them into the fields
marked `@Mock`.

The notation is the same as in Article 4: `when(…).thenReturn(…)`,
`verifyNoInteractions(…)`, plus the new `verify(mock).method(arguments)`:
"the method was called exactly once, with these arguments." In other
people's code you'll also see `mock(SomeClass.class)` instead of a field
with `@Mock`: it's the same mock.

⚠️ Online, you'll see `@Mock` fields that "just work" in a test that
starts the whole application with `@SpringBootTest`, like the `*IT`
tests. That's Boot 2–3. In Boot 4, Boot doesn't handle such fields.
Without `@ExtendWith(MockitoExtension.class)`, the field stays `null`, and
the test fails with a `NullPointerException`.

⚠️ `MockitoExtension` is strict. Stubbed a method with `when`, but the
code never called it? The test goes red with
`UnnecessaryStubbingException`, even if every check passed. That's not
nitpicking: an extra `when` means the test believes something about the
code that the code doesn't do.

### The service: a unit test

```java
@ExtendWith(MockitoExtension.class)
class IncidentListServiceTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository repository;                 // a mock: no Spring, no database

    private IncidentListService service;

    @BeforeEach
    void setUp() {
        service = new IncidentListService(repository);     // a plain new
    }

    @Test
    void returnsPageWithTotalFromRepository() {
        Incident fresh = new Incident("the feed is stuck", T0.plusSeconds(120), "duty-1");
        Incident old = new Incident("the broker is silent", T0, "duty-2");
        when(repository.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 2)))
                .thenReturn(new PageImpl<>(List.of(fresh, old), PageRequest.of(0, 2), 3));

        PageBody<IncidentResponse> page = service.list(PageRequest.of(0, 2), false);

        assertThat(page.items()).containsExactly(                     // all fields, same order
                new IncidentResponse(null, "the feed is stuck", T0.plusSeconds(120), null, "duty-1"),
                new IncidentResponse(null, "the broker is silent", T0, null, "duty-2"));
        assertThat(page.total()).isEqualTo(3);                        // the total, not the length of items
    }

    @Test
    void openOnlyAsksForOpenIncidents() {
        when(repository.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(2, 10), 0));

        service.list(PageRequest.of(2, 10), true);

        verify(repository).findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10));
    }
}
```

`@BeforeEach` is the counterpart of `@AfterEach` from Article 3a: JUnit
runs the method before every test. Mockito compares arguments with
`equals`. The `PageRequest.of(0, 2)` in `when` and the one the test
passed to the service are different objects, but equal ones, like two
records with the same fields (Article 0). The `id` in the responses is
`null`: the database assigns the key on save. The second test checks the fork on `open`; having that test is the journal's choice, just like the fork itself.

⚠️ `PageImpl`, a ready-made page for a mock, quietly fixes up `total` if
the page isn't full. Two rows, `PageRequest.of(0, 20)`, `total` 3, and
`getTotalElements()` returns 2. That's why in the test the page size
equals the number of rows.

**A debt from Article 4.** Article 4 promised that a test without Spring
would check that the by-ID service throws `NoSuchEntryException`
itself. The same technique checks both paths of `IncidentService.get`,
found and not found:

```java
when(repository.findById(ID)).thenReturn(Optional.of(
        new Incident("staging is not responding", Instant.parse("2026-10-05T09:15:00Z"), "duty-1")));
assertThat(service.get(ID).title()).isEqualTo("staging is not responding");  // found: a response

when(repository.findById(ID)).thenReturn(Optional.empty());                  // repository: "nothing here"
assertThatThrownBy(() -> service.get(ID))
        .isInstanceOfSatisfying(NoSuchEntryException.class,                  // an exception of this type…
                e -> assertThat(e.getCode()).isEqualTo("incident_not_found")); // …and with this code
```

`isInstanceOfSatisfying(type, check)` means "an exception of this type,
and here's what's in it": the lambda receives it already as the right
type, with `getCode()`. The whole thing, as two tests, is
`IncidentServiceTest` at the end of the article.

**A debt from Article 3b.** Article 3b deleted `IncidentLogTest` and
admitted honestly that no test checks the notification text anymore. The
check was to come back with Mockito. Here it is, with mocks of the
repository and of `Notifier`:

```java
@ExtendWith(MockitoExtension.class)
class IncidentLogTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository incidents;

    @Mock
    private Notifier notifier;

    @Test
    void addNotifiesDutyWithDetectionTime() {
        when(incidents.save(any(Incident.class))).thenAnswer(call -> call.getArgument(0));   // gives it back
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(T0, ZoneOffset.UTC), incidents);          // clock and roster, as in Article 1

        log.add("Broker is not responding");

        verify(notifier).send("duty-1", "Broker is not responding — detected at 2026-10-05T09:15:00Z");
    }
}
```

* `any(Incident.class)` means "any incident": the test doesn't know in
  advance which object `add` will create;
* `thenAnswer(call -> call.getArgument(0))`: a lambda computes the
  answer. It returns the call's first argument, that is, whatever was
  being saved. The real `save` returns the saved entity, and the mock
  does the same;
* `verify(notifier).send(…)` checks the whole notification: to whom, and
  what text.

`Pages` has its own unit test too: the defaults, the `size` boundary, and
bad numbers in a table, as in Article 0. That's `PagesTest` at the end of
the article.

### The repository: a test on a real database

A mock won't tell you whether Spring Data understood the method name and
whether the query selects the right rows. That's a job for an `*IT`:
a new class, `IncidentPagesIT`, with its own data. Its annotations are the
same as on `IncidentRepositoryIT`, so Spring will take the application
and its container from the cache (Article 3a). We leave
`IncidentRepositoryIT` from Article 3b alone: its tests expect only their
own rows in the table.

```java
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentPagesIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @BeforeEach
    void fillJournal() {
        incidents.save(new Incident("the broker is silent", T0, "duty-1"));
        incidents.save(new Incident("the feed is stuck", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("emails are piling up", T0.plusSeconds(240), "duty-1");   // the newest…
        fixed.fix(T0.plusSeconds(600));                                                         // …but closed
        incidents.save(fixed);
    }

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();                          // shared database: clean up, as in Article 3b
    }

    @Test
    void openOnlyNewestFirst() {
        Page<Incident> page = incidents.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(0, 1));

        assertThat(page.getContent()).extracting(Incident::getTitle).containsExactly("the feed is stuck");
        assertThat(page.getTotalElements()).isEqualTo(2);              // the closed one isn't counted
    }
}
```

Look at the data: the newest incident is closed. If the filter doesn't
work, "emails are piling up" comes first, and the test goes red.

Data for an `*IT` is picked so that a bug **shows up**. You need
a closed row or someone else's row, and different times. Otherwise the
test is green with any code. Which rows an endpoint needs is decided anew
in every task.

Two more tests of this class, "all, newest first" and "a page past the
end," are at the end of the article.

### The controller: a web layer test

The `@WebMvcTest` slice with `MockMvcTester` is the same as in Article 4,
and the service in it is again a `@MockitoBean` mock. Request parameters
are passed with `.param("page", "0")`. Two things are new.

**Security in the slice.** The slice picks up controllers, controller
advice, and filters, but not `@Configuration` classes (Article 4), and
`SecurityConfig` is exactly that kind. So the test brings it in itself,
with `@Import(SecurityConfig.class)`, like `TestcontainersConfiguration`
in the database tests.

**Login in the request.** `.with(ADMIN)` attaches the `Authorization`
header to the request, like `curl -u`. `ADMIN` is a **request add-on**
(`RequestPostProcessor`). It's made by
`SecurityMockMvcRequestPostProcessors.httpBasic(name, password)` from the
test part of Spring Security. The login is real: security checks the
name and password against `SecurityConfig`.

```java
@WebMvcTest(IncidentListController.class)
@Import(SecurityConfig.class)                                     // sandbox security: the slice skips it
class IncidentListControllerTest {

    private static final String PATH = "/game-day/incidents";
    private static final RequestPostProcessor ADMIN =                // login in the request, like curl -u
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");
    private static final RequestPostProcessor VIEWER =
            SecurityMockMvcRequestPostProcessors.httpBasic("viewer", "viewer-local");
    …

    @Test
    void returnsPage() {
        when(service.list(PageRequest.of(0, 2), false)).thenReturn(new PageBody<>(
                List.of(new IncidentResponse(ID, "the feed is stuck", T0, null, "duty-1")), 0, 2, 3));

        assertThat(mvc.get().uri(PATH).param("page", "0").param("size", "2").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[{"id":"7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f","title":"the feed is stuck",
                                   "detectedAt":"2026-10-05T09:15:00Z","fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":2,"total":3}
                        """);
    }

    @ParameterizedTest(name = "{0}={1} → 400 {2}")
    @CsvSource(delimiter = '|', textBlock = """
            page | -1 | page_number_invalid
            size | 0  | page_size_invalid
            size | 51 | page_size_invalid
            """)
    void rejectsBadPageParams(String name, String value, String code) {
        assertThat(mvc.get().uri(PATH).param(name, value).with(ADMIN))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo(code);
        verifyNoInteractions(service);                             // never reached the service
    }

    @Test
    void rejectsWithoutLogin() {
        assertThat(mvc.get().uri(PATH)).hasStatus(HttpStatus.UNAUTHORIZED);         // not logged in
        verifyNoInteractions(service);
    }

    @Test
    void refusesViewer() {
        assertThat(mvc.get().uri(PATH).with(VIEWER)).hasStatus(HttpStatus.FORBIDDEN);   // logged in, refused
        verifyNoInteractions(service);
    }
}
```

The `…` stands for `ID`, `T0`, `mvc`, and the `service` mock, as in
Article 4. The "no parameters" test is in the full example at the end.

⚠️ Forget the `@Import`, and the slice won't fail right away; it will
take Boot's default security instead. That's the user `user` with
a random password, and the test output shows
`Using generated security password: …`. There's no `admin` user in it,
and the tests as `admin` get `401`.

💡 Online, tests with a login are often written with the
`@WithMockUser(roles = "admin")` annotation. It plugs in a logged-in
user, bypassing the password. In Boot 4, it works with the security test
starter. We log in for real: that way the test also checks the users and
passwords from `SecurityConfig`.

The by-ID endpoint from Article 4 is now `admin`-only too. So
`IncidentControllerTest` changes the same way: `@Import(SecurityConfig.class)`,
`.with(ADMIN)` in every request, and two new cases: `401` without
a login, `403` as `viewer`. The whole file is at the end of the article.

### The end-to-end test

Above the `*IT` tests sits one end-to-end test per endpoint. It has the
whole application, a real database, and a real login as `admin`. The
database holds a closed row newer than the open ones. You need to check
`200`, `items`, and `total`. The layers have been tested separately; the
end-to-end test checks that they fit together: path, security, query,
and JSON at once.

```java
@SpringBootTest
@AutoConfigureMockMvc                                       // MockMvcTester over the whole application
@Import(TestcontainersConfiguration.class)
class IncidentListIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");

    @Autowired
    private MockMvcTester mvc;

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void adminGetsOpenIncidentsNewestFirst() {
        Incident older = incidents.save(new Incident("the broker is silent", T0, "duty-1"));
        Incident newer = incidents.save(new Incident("the feed is stuck", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("emails are piling up", T0.plusSeconds(240), "duty-1");   // the newest…
        fixed.fix(T0.plusSeconds(600));                                                         // …but closed
        incidents.save(fixed);

        assertThat(mvc.get().uri("/game-day/incidents").param("open", "true").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[
                            {"id":"%s","title":"the feed is stuck","detectedAt":"2026-10-05T09:17:00Z",
                             "fixedAt":null,"dutyName":"duty-2"},
                            {"id":"%s","title":"the broker is silent","detectedAt":"2026-10-05T09:15:00Z",
                             "fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":20,"total":2}
                        """.formatted(newer.getId(), older.getId()));       // the database assigned the keys
    }
}
```

* `@AutoConfigureMockMvc`: `@SpringBootTest` on its own doesn't provide
  `MockMvcTester`, but this annotation does. The request goes through the
  real security, controller, service, and repository, just without
  Tomcat;
* `"""…""".formatted(a, b)` fills in the values in place of the `%s`
  markers, in order: the database assigned the row keys, so you can't
  know them in advance;
* the data is the same as in `IncidentPagesIT`: the newest incident is
  closed, so the test will notice a broken filter.

The end-to-end test has more annotations than `IncidentPagesIT`, so it can't reuse the cached application (Article 3a). Spring will start a second
one, with its own Postgres container. That's why there's one end-to-end
test per endpoint, not one per case.

### What each test catches

| test | catches | doesn't catch |
|---|---|---|
| service unit test | which query `open` picks; the page reaches the repository; `total`; field conversion | whether the query selects the right rows; HTTP, login |
| `Pages` unit test | defaults and limits of `page` and `size`, error codes | HTTP: the status and the response format |
| repository `*IT` | the method name is understood; the "no `fixedAt`" filter, order, and `total` on Postgres | HTTP, access, conversion to a response |
| web layer test | path, defaults, `400` with `code`, JSON format, `401` and `403` | the database; whether it all works together |
| perimeter test | every endpoint has a row in `DECLARED` | whether access is written correctly: that's for review |
| end-to-end | path, login, query, and JSON together | rare cases: the lower layers catch those |
| demo | `.jar`, migrations, settings from the environment, Tomcat, login with `curl` | anything you can't repeat by hand |

The layers don't replace each other: with a broken query, the service
unit test and the web layer test stay green, because they use mocks.

### The endpoint's case table

An "input → result" table, as in Article 0, with a new column: "where
it's caught."

| case | request | expect | where it's caught |
|---|---|---|---|
| there's data | `?page=0&size=2` as `admin` | 200, two rows, `total` is the overall count | service, web |
| no parameters | no `page` or `size` | 200, the service got `(0, 20)` | `Pages`, web |
| open only | `?open=true` | only rows without `fixedAt` | service (which query), `*IT` (what it selects) |
| newest first | any | by `detectedAt`, descending | `*IT` |
| page past the end | `?page=5` | 200, `items` empty, real `total` (the journal's choice) | `*IT` |
| empty journal | any | 200, `items` empty, `total` 0 | service |
| `page` below 0 | `?page=-1` | 400 `page_number_invalid`, service not called | `Pages`, web |
| `size` outside 1..50 | `?size=0`, `?size=51` | 400 `page_size_invalid`, service not called | `Pages`, web |
| not logged in | any | 401, service not called | web |
| logged in as `viewer` | any | 403, service not called | web |

🔑 **Every row of the case table is a test on the lowest layer that
catches it.** A row without a test is a hole. In the real project, the
first thing a reviewer does is match the table against the tests. Where
the column names two layers, the lower one checks the rule, and the web
layer test checks that the rule produces the right response.

### The top of the pyramid: the demo

The tests are green, so the endpoint is done? Not yet: it has to be shown
live. In the real project, that happens on staging, and the `curl` output
goes into the pull request (Article 4). In the sandbox, staging is your
own machine: Postgres in a container and `java -jar`.

**1. Start.** As in Article 4: the database is the `docker run` from
Article 3a, then the three `SPRING_DATASOURCE_*` variables, then
`./mvnw package` and `java -jar target/game-day-0.0.1-SNAPSHOT.jar`. The
log has no `Using generated security password` line: we defined the users
ourselves. As before, startup wrote "Broker is not responding" to the
journal: an open incident.

**2. Data.** Add two more incidents, one open and one closed. Open `psql`
(`docker exec -it game-day-db psql -U postgres`) and run:

```sql
INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name) VALUES
    ('the feed is stuck',    '2026-10-05T09:17:00Z', NULL,                   'duty-1'),
    ('the broker is silent', '2026-10-05T09:15:00Z', '2026-10-05T09:40:00Z', 'duty-2');
```

```
INSERT 0 2
```

We don't pass `id`: `DEFAULT` generates it (Article 3a).

🔴 Change data by hand only in your own database, in a container.
On the real project's shared staging environments, nothing is changed by
hand: neither the database nor the running services.

**3. Request.** Run it in another console window. Put the address in quotes;
otherwise Git Bash takes `&` to mean "run in the background":

```bash
curl -i -u admin:admin-local "http://localhost:8080/game-day/incidents?page=0&size=20&open=true"
```

What should come back:

```
HTTP/1.1 200
…
Content-Type: application/json
…

{"items":[{"id":"…","title":"Broker is not responding","detectedAt":"2026-10-20T…Z",
           "fixedAt":null,"dutyName":"duty-1"},
          {"id":"…","title":"the feed is stuck","detectedAt":"2026-10-05T09:17:00Z",
           "fixedAt":null,"dutyName":"duty-1"}],"page":0,"size":20,"total":2}
```

The body arrives as a single line; here it's broken up to fit. Your `id`
values and the time of "Broker is not responding" will differ, and the
field order may be different too. "Broker is not responding" is on top:
it was written just now.

The `…` lines are service headers: `Date` and the security headers that Spring Security adds to every response. For example,
`Cache-Control: no-cache, no-store, max-age=0, must-revalidate` means
a response with journal data isn't cached. There's no cookie in the
response: there's no session.

Without `open=true`, all three incidents come back, newest first, with
`"total":3`.

**4. Refusals.** A page that's too big, a request without a login, and
a login as `viewer`:

```bash
curl -i -u admin:admin-local "http://localhost:8080/game-day/incidents?size=500"
curl -i "http://localhost:8080/game-day/incidents"
curl -i -u viewer:viewer-local "http://localhost:8080/game-day/incidents"
```

The first gets `400` and our format:

```
{"code":"page_size_invalid","message":"Page size must be between 1 and 50"}
```

The second gets `401`. Among the headers is a request to log in, and the
body is in Boot's format:

```
HTTP/1.1 401
WWW-Authenticate: Basic realm="Realm", charset="UTF-8"
…

{"timestamp":"…","status":401,"error":"Unauthorized","path":"/game-day/incidents"}
```

The third gets `403` and `{"timestamp":"…","status":403,"error":"Forbidden","path":"/game-day/incidents"}`.

The `401` and `403` bodies are in Boot's format, like the one for the
unknown address in Article 4. Security refused, and the request never
reached the controller or our handler. Boot built the body on `/error`:
that's what the `ERROR` forward was opened for. Your header order may
differ.

The demo format: the `curl` commands and the `200`, `400`, `401`, and `403` responses go into the pull request. How to get data for the demo depends on
the task. Sometimes rows inserted by hand into your own database are
enough. Sometimes the system itself has to create the data; then it's
created through the system's own endpoints.

**Why the demo is part of "done."** In tests, much of what surrounds the
piece under test is swapped out: mocks, a database from Testcontainers,
MockMvc instead of Tomcat, a login attached to the request in code.
Startup is the first place where everything is assembled for real: the
`.jar`, migrations, settings from the environment, Tomcat, `curl` with
a password. That's why in the real project "done" doesn't mean "merged,"
it means "works." In the pull request, the reviewer sees the `curl`
output: proof that the endpoint answers, not that it's supposed to.

Once you've seen it, stop the application with `Ctrl+C`. Need a clean
database? Recreate the container: `docker stop game-day-db`, then
`docker run` again.

---

## Checklist: before the pull request

- [ ] **Contract** as a table: method and path, parameters with defaults,
      response, errors with codes, roles.
- [ ] **Case table**: every row has the layer where you catch it.
- [ ] **Repository**: a paged query; an `*IT` on data where a bug would
      show; cleanup in `@AfterEach`.
- [ ] **Service**: rules and the transaction, no HTTP; a response record
      goes out; a unit test with `MockitoExtension`.
- [ ] **Controller**: parameters → page parsing → service; access
      declared the same way as on neighboring endpoints.
- [ ] **Web layer test**: every response from the error table; a `400`
      has a `code`; the login is real; on a refusal, the service isn't
      called.
- [ ] **End-to-end test**: one per endpoint.
- [ ] **A row in `DECLARED`**; without it the perimeter test goes red:
      check that it does.
- [ ] `./mvnw verify` is green; new classes have 100% of lines and
      branches covered (in the real project, the JaCoCo report shows it).
- [ ] **Demo**: `200`, `400`, `401`, `403`, with the `curl` output in the
      pull request.
- [ ] The pull request explains "how I built the endpoint": what I chose
      and why.

That's how an endpoint is prepared for review in the real project. In
a real task, the places marked "the journal's choice" are decided by
whoever does the task. At review they'll be asked why their answer fits
this endpoint and how the endpoint differs from its neighbors.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. In a list endpoint, what does the controller do, what does the
   service do, and what does the repository do? What does each of them
   not know, and what does that give the tests?
2. The entity and the response record have the same fields. Why does the
   endpoint still return the record? Explain using the attacker's note.
3. Why does `@Transactional` go on the service and not on the controller
   or the repository?
4. Where does `total` in the response come from, and why isn't it the
   length of `items`? What makes `PageImpl` dangerous in a test with
   a mock?
5. How does `401` differ from `403`? Why does `?size=500` without a login
   get `401` and not `400`, and what does an address that doesn't exist
   answer now?
6. Why does the `?size=0` test run as `admin`? Why check on a refusal
   that the service wasn't called, and why does the web layer test need
   `@Import(SecurityConfig.class)`?
7. The service unit test and the web layer test are green, but in the
   demo the endpoint with `open=true` also returns closed incidents.
   Which test should have caught this, and what data does it need?
8. Why have a perimeter test if `denyAll` already locks a forgotten
   endpoint? And why show the endpoint live if all the tests are green?

---

## What's next

This is the last article of the "From Java to Spring Boot" series. The
journal has come a long way: from a notification with no memory to an
endpoint with pages, a login, and tests on every layer.

Next comes the "From Spring to a System" series, about what you run into
in tasks after your first endpoints: staging in Docker, events in JSON,
value objects, more involved data, metrics, and tests that guard the
project's rules. It starts with Article 6, "Build your own staging
environment."

## Sources

* [Spring Framework: Using @Transactional](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html):
  where to put the annotation and what `readOnly` means;
* [Spring Data JPA: Query Methods](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html):
  the Paging, Iterating Large Results, Sorting & Limiting section: pages
  and the cost of counting;
* [Spring Security: Authorize HttpServletRequests](https://docs.spring.io/spring-security/reference/servlet/authorization/authorize-http-requests.html):
  rules by path, their order, `denyAll` at the end, and the `ERROR`
  forward;
* [Spring Security: Basic Authentication](https://docs.spring.io/spring-security/reference/servlet/authentication/passwords/basic.html):
  how security answers `401` and asks you to log in;
* [Spring Security: Testing HTTP Basic Authentication](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/http-basic.html):
  `httpBasic` in MockMvc tests;
* [Spring Boot how-to: Testing](https://docs.spring.io/spring-boot/how-to/testing.html):
  tests with Spring Security, and why a slice doesn't pick up the
  security configuration class by itself;
* [Mockito: the Mockito class javadoc](https://javadoc.io/doc/org.mockito/mockito-core/latest/org/mockito/Mockito.html):
  `when`, `verify`, `thenAnswer`, and strict stubs;
* [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide):
  test starters, `spring-boot-starter-security-test`, and why `@Mock`
  fields need `MockitoExtension`.

---

## The full example, with imports

A learning example. Run it in the `game-day` sandbox after Article 4.
Everything already there stays unchanged: `GameDayApplication`,
`GameDayProperties` with its test, `application.yml` and
`application-stand.yml`, the `V1__game_day_incident.sql` migration,
`TestcontainersConfiguration`, the shared `ErrorBody`, `ErrorHandler`,
`NoSuchEntryException`, and `InvalidInputException`, the journal in
`example.gameday.journal` (`Incident`, `IncidentLog`, `DutyRoster`,
`Notifier`, `ConsoleNotifier`, `GameDayConfig`, `IncidentResponse`,
`IncidentService`, `IncidentIds`, `IncidentController`), and its tests,
except one.

What to change: in `IncidentRepository`, the two paging methods; in
`IncidentControllerTest`, the login as `admin` and the two refusal cases.
Both files are below in full.

What to add: two starters in `pom.xml`; in `example.gameday`, `Pages`,
`PageBody`, and the `SecurityConfig` security configuration; in
`example.gameday.journal`, `IncidentListService` and
`IncidentListController`. Tests: `PagesTest` and `PerimeterTest` in
`example.gameday`; `IncidentListServiceTest`, `IncidentServiceTest`,
`IncidentLogTest`, `IncidentPagesIT`, `IncidentListControllerTest`, and
`IncidentListIT` in `example.gameday.journal`. The database tests need
Docker running; the unit tests and slices don't.

```xml
<!-- pom.xml: inside <dependencies>, next to what's already there -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security-test</artifactId>
    <scope>test</scope>
</dependency>
```

```java
// src/main/java/example/gameday/Pages.java
package example.gameday;

import org.springframework.data.domain.PageRequest;

/** Page number and size from the request: the same defaults and checks for every list. */
public final class Pages {

    public static final int DEFAULT_SIZE = 20;
    public static final int MAX_SIZE = 50;

    private Pages() {
    }

    public static PageRequest request(Integer page, Integer size) {
        int number = 0;
        if (page != null) {
            number = page;
        }
        int rows = DEFAULT_SIZE;
        if (size != null) {
            rows = size;
        }
        if (number < 0) {
            throw new InvalidInputException("page_number_invalid", "Page number must be 0 or greater");
        }
        if (rows < 1 || rows > MAX_SIZE) {
            throw new InvalidInputException("page_size_invalid", "Page size must be between 1 and 50");
        }
        return PageRequest.of(number, rows);
    }
}
```

```java
// src/main/java/example/gameday/PageBody.java
package example.gameday;

import java.util.List;

/** A page of a list in the response: one format for every list. */
public record PageBody<T>(List<T> items, int page, int size, long total) {
}
```

```java
// src/main/java/example/gameday/SecurityConfig.java
package example.gameday;

import jakarta.servlet.DispatcherType;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

/** Sandbox security: Basic login, users in memory, journal endpoints for admin only. */
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain security(HttpSecurity http) {
        http.authorizeHttpRequests(access -> access
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents").hasRole("admin")
                        .requestMatchers(HttpMethod.GET, "/game-day/incidents/{id}").hasRole("admin")
                        .anyRequest().denyAll())
                .httpBasic(Customizer.withDefaults())
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS));
        return http.build();
    }

    @Bean
    public UserDetailsService users() {
        return new InMemoryUserDetailsManager(
                User.withUsername("admin").password("{noop}admin-local").roles("admin").build(),
                User.withUsername("viewer").password("{noop}viewer-local").roles("viewer").build());
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentRepository.java
package example.gameday.journal;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.UUID;

public interface IncidentRepository extends JpaRepository<Incident, UUID> {

    List<Incident> findByDutyName(String dutyName);

    List<Incident> findByFixedAtIsNull();

    @Query("select i from Incident i where i.dutyName = ?1 and i.fixedAt is null order by i.detectedAt")
    List<Incident> findOpenOf(String dutyName);

    Page<Incident> findAllByOrderByDetectedAtDesc(Pageable pageable);

    Page<Incident> findByFixedAtIsNullOrderByDetectedAtDesc(Pageable pageable);
}
```

```java
// src/main/java/example/gameday/journal/IncidentListService.java
package example.gameday.journal;

import example.gameday.PageBody;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class IncidentListService {

    private final IncidentRepository repository;

    public IncidentListService(IncidentRepository repository) {
        this.repository = repository;
    }

    public PageBody<IncidentResponse> list(Pageable pageable, boolean openOnly) {
        Page<Incident> found;
        if (openOnly) {
            found = repository.findByFixedAtIsNullOrderByDetectedAtDesc(pageable);
        } else {
            found = repository.findAllByOrderByDetectedAtDesc(pageable);
        }
        Page<IncidentResponse> responses = found.map(IncidentResponse::of);
        return new PageBody<>(responses.getContent(), pageable.getPageNumber(), pageable.getPageSize(),
                responses.getTotalElements());
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentListController.java
package example.gameday.journal;

import example.gameday.PageBody;
import example.gameday.Pages;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class IncidentListController {

    private final IncidentListService service;

    public IncidentListController(IncidentListService service) {
        this.service = service;
    }

    // access: admin only, set in SecurityConfig
    @GetMapping("/game-day/incidents")
    public PageBody<IncidentResponse> list(
            @RequestParam(name = "page", required = false) Integer page,
            @RequestParam(name = "size", required = false) Integer size,
            @RequestParam(name = "open", defaultValue = "false") boolean open) {
        PageRequest pageRequest = Pages.request(page, size);
        return service.list(pageRequest, open);
    }
}
```

```java
// src/test/java/example/gameday/PagesTest.java
package example.gameday;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.data.domain.PageRequest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PagesTest {

    @Test
    void defaultsWhenNothingCame() {
        assertThat(Pages.request(null, null)).isEqualTo(PageRequest.of(0, 20));
    }

    @Test
    void keepsWhatCame() {
        assertThat(Pages.request(3, 50)).isEqualTo(PageRequest.of(3, 50));
    }

    @ParameterizedTest(name = "page={0}, size={1} → {2}")
    @CsvSource(delimiter = '|', nullValues = "null", textBlock = """
            -1   | null | page_number_invalid
            null | 0    | page_size_invalid
            null | 51   | page_size_invalid
            """)
    void rejectsBadNumbers(Integer page, Integer size, String code) {
        assertThatThrownBy(() -> Pages.request(page, size))
                .isInstanceOfSatisfying(InvalidInputException.class,
                        e -> assertThat(e.getCode()).isEqualTo(code));
    }
}
```

```java
// src/test/java/example/gameday/PerimeterTest.java
package example.gameday;

import example.gameday.journal.IncidentListService;
import example.gameday.journal.IncidentService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** Perimeter test: every endpoint of the application is listed in DECLARED: method, path, who gets in. */
@WebMvcTest
class PerimeterTest {

    static final List<Endpoint> DECLARED = List.of(
            new Endpoint("GET", "/game-day/incidents/{id}", "admin"),
            new Endpoint("GET", "/game-day/incidents", "admin"));

    @Autowired
    private RequestMappingHandlerMapping mappings;

    @MockitoBean
    private IncidentService incidentService;

    @MockitoBean
    private IncidentListService incidentListService;

    @Test
    void everyEndpointIsDeclared() {
        List<String> found = new ArrayList<>();
        mappings.getHandlerMethods().forEach((mapping, handler) -> {
            if (handler.getBeanType().getPackageName().startsWith("example.gameday")) {
                for (RequestMethod method : mapping.getMethodsCondition().getMethods()) {
                    for (String path : mapping.getPatternValues()) {
                        found.add(method + " " + path);
                    }
                }
            }
        });
        List<String> declared = new ArrayList<>();
        for (Endpoint endpoint : DECLARED) {
            declared.add(endpoint.method() + " " + endpoint.path());
        }
        assertThat(found).containsExactlyInAnyOrderElementsOf(declared);
    }

    record Endpoint(String method, String path, String role) {
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentListServiceTest.java
package example.gameday.journal;

import example.gameday.PageBody;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IncidentListServiceTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository repository;

    private IncidentListService service;

    @BeforeEach
    void setUp() {
        service = new IncidentListService(repository);
    }

    @Test
    void returnsPageWithTotalFromRepository() {
        Incident fresh = new Incident("the feed is stuck", T0.plusSeconds(120), "duty-1");
        Incident old = new Incident("the broker is silent", T0, "duty-2");
        when(repository.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 2)))
                .thenReturn(new PageImpl<>(List.of(fresh, old), PageRequest.of(0, 2), 3));

        PageBody<IncidentResponse> page = service.list(PageRequest.of(0, 2), false);

        assertThat(page.items()).containsExactly(
                new IncidentResponse(null, "the feed is stuck", T0.plusSeconds(120), null, "duty-1"),
                new IncidentResponse(null, "the broker is silent", T0, null, "duty-2"));
        assertThat(page.page()).isEqualTo(0);
        assertThat(page.size()).isEqualTo(2);
        assertThat(page.total()).isEqualTo(3);
    }

    @Test
    void openOnlyAsksForOpenIncidents() {
        when(repository.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(2, 10), 0));

        service.list(PageRequest.of(2, 10), true);

        verify(repository).findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(2, 10));
    }

    @Test
    void emptyJournalIsEmptyPage() {
        when(repository.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 20)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 20), 0));

        PageBody<IncidentResponse> page = service.list(PageRequest.of(0, 20), false);

        assertThat(page.items()).isEmpty();
        assertThat(page.total()).isEqualTo(0);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentServiceTest.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IncidentServiceTest {

    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");

    @Mock
    private IncidentRepository repository;

    @Test
    void getReturnsResponse() {
        IncidentService service = new IncidentService(repository);
        when(repository.findById(ID)).thenReturn(Optional.of(
                new Incident("staging is not responding", Instant.parse("2026-10-05T09:15:00Z"), "duty-1")));

        assertThat(service.get(ID).title()).isEqualTo("staging is not responding");
    }

    @Test
    void getThrowsWhenNotFound() {
        IncidentService service = new IncidentService(repository);
        when(repository.findById(ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get(ID))
                .isInstanceOfSatisfying(NoSuchEntryException.class,
                        e -> assertThat(e.getCode()).isEqualTo("incident_not_found"));
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentLogTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class IncidentLogTest {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Mock
    private IncidentRepository incidents;

    @Mock
    private Notifier notifier;

    @Test
    void addNotifiesDutyWithDetectionTime() {
        when(incidents.save(any(Incident.class))).thenAnswer(call -> call.getArgument(0));
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(T0, ZoneOffset.UTC), incidents);

        log.add("Broker is not responding");

        verify(notifier).send("duty-1", "Broker is not responding — detected at 2026-10-05T09:15:00Z");
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentPagesIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentPagesIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @BeforeEach
    void fillJournal() {
        incidents.save(new Incident("the broker is silent", T0, "duty-1"));
        incidents.save(new Incident("the feed is stuck", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("emails are piling up", T0.plusSeconds(240), "duty-1");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);
    }

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void allNewestFirst() {
        Page<Incident> page = incidents.findAllByOrderByDetectedAtDesc(PageRequest.of(0, 3));

        assertThat(page.getContent()).extracting(Incident::getTitle)
                .containsExactly("emails are piling up", "the feed is stuck", "the broker is silent");
        assertThat(page.getTotalElements()).isEqualTo(3);
    }

    @Test
    void openOnlyNewestFirst() {
        Page<Incident> page = incidents.findByFixedAtIsNullOrderByDetectedAtDesc(PageRequest.of(0, 1));

        assertThat(page.getContent()).extracting(Incident::getTitle).containsExactly("the feed is stuck");
        assertThat(page.getTotalElements()).isEqualTo(2);
    }

    @Test
    void pageBeyondEndIsEmpty() {
        Page<Incident> page = incidents.findAllByOrderByDetectedAtDesc(PageRequest.of(5, 2));

        assertThat(page.getContent()).isEmpty();
        assertThat(page.getTotalElements()).isEqualTo(3);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentListControllerTest.java
package example.gameday.journal;

import example.gameday.PageBody;
import example.gameday.SecurityConfig;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@WebMvcTest(IncidentListController.class)
@Import(SecurityConfig.class)
class IncidentListControllerTest {

    private static final String PATH = "/game-day/incidents";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");
    private static final RequestPostProcessor VIEWER =
            SecurityMockMvcRequestPostProcessors.httpBasic("viewer", "viewer-local");

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private IncidentListService service;

    @Test
    void returnsPage() {
        when(service.list(PageRequest.of(0, 2), false)).thenReturn(new PageBody<>(
                List.of(new IncidentResponse(ID, "the feed is stuck", T0, null, "duty-1")), 0, 2, 3));

        assertThat(mvc.get().uri(PATH).param("page", "0").param("size", "2").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[{"id":"7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f","title":"the feed is stuck",
                                   "detectedAt":"2026-10-05T09:15:00Z","fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":2,"total":3}
                        """);
    }

    @Test
    void defaultsWhenNoParams() {
        when(service.list(PageRequest.of(0, 20), false))
                .thenReturn(new PageBody<>(List.of(), 0, 20, 0));

        assertThat(mvc.get().uri(PATH).with(ADMIN)).hasStatusOk();

        verify(service).list(PageRequest.of(0, 20), false);
    }

    @ParameterizedTest(name = "{0}={1} → 400 {2}")
    @CsvSource(delimiter = '|', textBlock = """
            page | -1 | page_number_invalid
            size | 0  | page_size_invalid
            size | 51 | page_size_invalid
            """)
    void rejectsBadPageParams(String name, String value, String code) {
        assertThat(mvc.get().uri(PATH).param(name, value).with(ADMIN))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo(code);
        verifyNoInteractions(service);
    }

    @Test
    void rejectsWithoutLogin() {
        assertThat(mvc.get().uri(PATH)).hasStatus(HttpStatus.UNAUTHORIZED);
        verifyNoInteractions(service);
    }

    @Test
    void refusesViewer() {
        assertThat(mvc.get().uri(PATH).with(VIEWER)).hasStatus(HttpStatus.FORBIDDEN);
        verifyNoInteractions(service);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentControllerTest.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import example.gameday.SecurityConfig;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@WebMvcTest(IncidentController.class)
@Import(SecurityConfig.class)
class IncidentControllerTest {

    private static final String PATH = "/game-day/incidents/{id}";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");
    private static final RequestPostProcessor VIEWER =
            SecurityMockMvcRequestPostProcessors.httpBasic("viewer", "viewer-local");

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private IncidentService service;

    @Test
    void returnsIncident() {
        when(service.get(ID)).thenReturn(new IncidentResponse(ID, "Broker is not responding",
                Instant.parse("2026-10-14T10:05:00Z"), null, "duty-1"));

        assertThat(mvc.get().uri(PATH, ID).with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"id": "7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f",
                         "title": "Broker is not responding",
                         "detectedAt": "2026-10-14T10:05:00Z",
                         "fixedAt": null,
                         "dutyName": "duty-1"}
                        """);
    }

    @Test
    void unknownIncidentIs404() {
        when(service.get(ID))
                .thenThrow(new NoSuchEntryException("incident_not_found", "Incident not found"));

        assertThat(mvc.get().uri(PATH, ID).with(ADMIN))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_not_found");
    }

    @ParameterizedTest(name = "{0} → 400")
    @ValueSource(strings = {"abc", "1-1-1-1-1"})
    void badIdIs400(String badId) {
        assertThat(mvc.get().uri(PATH, badId).with(ADMIN))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_id_invalid");
        verifyNoInteractions(service);
    }

    @Test
    void rejectsWithoutLogin() {
        assertThat(mvc.get().uri(PATH, ID)).hasStatus(HttpStatus.UNAUTHORIZED);
        verifyNoInteractions(service);
    }

    @Test
    void refusesViewer() {
        assertThat(mvc.get().uri(PATH, ID).with(VIEWER)).hasStatus(HttpStatus.FORBIDDEN);
        verifyNoInteractions(service);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentListIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.test.web.servlet.assertj.MockMvcTester;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@AutoConfigureMockMvc
@Import(TestcontainersConfiguration.class)
class IncidentListIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");
    private static final RequestPostProcessor ADMIN =
            SecurityMockMvcRequestPostProcessors.httpBasic("admin", "admin-local");

    @Autowired
    private MockMvcTester mvc;

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void adminGetsOpenIncidentsNewestFirst() {
        Incident older = incidents.save(new Incident("the broker is silent", T0, "duty-1"));
        Incident newer = incidents.save(new Incident("the feed is stuck", T0.plusSeconds(120), "duty-2"));
        Incident fixed = new Incident("emails are piling up", T0.plusSeconds(240), "duty-1");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);

        assertThat(mvc.get().uri("/game-day/incidents").param("open", "true").with(ADMIN))
                .hasStatusOk()
                .bodyJson().isStrictlyEqualTo("""
                        {"items":[
                            {"id":"%s","title":"the feed is stuck","detectedAt":"2026-10-05T09:17:00Z",
                             "fixedAt":null,"dutyName":"duty-2"},
                            {"id":"%s","title":"the broker is silent","detectedAt":"2026-10-05T09:15:00Z",
                             "fixedAt":null,"dutyName":"duty-1"}],
                         "page":0,"size":20,"total":2}
                        """.formatted(newer.getId(), older.getId()));
    }
}
```
