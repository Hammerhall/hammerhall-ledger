# Your first endpoint: how an application answers over HTTP

> "From Java to Spring Boot" · Article 4 · 35 min read
>
> **Who it's for.** You've read Articles 0–3b, and in the `game-day`
> sandbox the journal stores incidents in Postgres: the `Incident` entity,
> the `IncidentRepository` repository, the `IncidentLog` service. You know
> HTTP at the level of "the browser opens a page."
>
> **What's inside.** Three things: HTTP and `curl` (the request, the response, and how to send one yourself); the controller and JSON (how a Java method becomes an endpoint); errors and the web layer test (how an exception becomes a response, and how to test an endpoint without a database, using a Mockito mock).
>
> **Where it comes from.** The "Bootcamp / Lab" section is about how
> Hammerhall teams write code: the bootcamp works in public repositories,
> the lab in private ones. The "From Java to Spring Boot" series covers
> what a newcomer needs before their first task on Spring Boot 4. The
> examples are for learning: you can reproduce them yourself.

---

## Why you need an endpoint

In Article 3b, the Game Day incidents landed in the `game_day.incident`
table. But only the application itself can see them: the team lead, the
on-call engineers, and the game screen have no way to ask. Give them the
database password? 🔴 No: with the password you can not only read but
also delete, and nobody will check who reads what.

What you need is a pickup window with rules: people ask in an agreed format, and nobody is let in behind it. That window is an **endpoint**: an
address in the application where you ask one kind of question. The
language of questions and answers is **HTTP**: browsers speak it, and so
does any program.

In the real project, endpoints are a common junior task. Usually there's
already a sample endpoint nearby, and you model the new one on it: the
same way, with the same error format, with the same set of tests.

The running example is the `GET /game-day/incidents/{id}` endpoint: "show
me the incident with this ID."

---

## Part 1. HTTP: the essentials

### Requests and responses are text

A browser, the `curl` program (more on it at the end of this part), and
other services send the application a **request** and get back
a **response**. Both are just text. Here's a request to our endpoint:

```
GET /game-day/incidents/7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f HTTP/1.1
Host: localhost:8080
Accept: application/json
```

The first line is the method, the path, and the protocol version
(`HTTP/1.1`):

* the HTTP **method** (don't confuse it with a Java method) says what to
  do: `GET` means "give me," read only; `POST`, "take this and act on
  it"; `PUT`, "replace"; `DELETE`, "delete";
* the **path** says what exactly; the incident ID sits right in the path.

Next come the **headers**, lines of the form "name: value." `Host` says
which server and port the request is going to: `localhost` is your own
machine, and `8080` is the port the application listens on. `Accept` says
what format the client wants the response in. There are others too. For example,
`Cookie` carries a **cookie**: a string the server issued when you logged in. It's attached to every request, and that's how the server knows who's
asking.

After an empty line there may be a **body**: the data itself. A `GET` has
no body; for `POST` and `PUT` it's usually JSON.

**Query parameters** are pairs after `?`, separated by `&`:
`…/incidents?open=true&page=0`. The path says **what** you asked for, the
parameters say **how**: "only open ones, first page" (pages are counted
from zero).

The response is built the same way:

```
HTTP/1.1 200
Content-Type: application/json

{"id":"7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f","title":"Broker is not responding",
 "detectedAt":"2026-10-14T10:05:00Z","fixedAt":null,"dutyName":"duty-1"}
```

The first line is the version and the **status**: a number that sums up
the result. The word after the number (`OK`) is an explanation for
people, and it may be missing: Tomcat, for example, doesn't write it. Then
come the headers: `Content-Type` says what's in the body.

After an empty line comes the body. It arrives as a single line; here
it's split in two to fit. The order of the fields may differ for you: in
JSON it doesn't matter.

### Status codes

The first digit of a status is its family: **2xx** means it worked;
**4xx**, the client made a mistake, and sending the same request again
gets the same refusal; **5xx**, something broke on the server. These are
the ones you'll see most often:

| status | what it means |
|---|---|
| `200 OK` | here's the answer |
| `202 Accepted` | got it, I'll do it later |
| `400 Bad Request` | the request is invalid: a malformed ID, page `-1` |
| `401 Unauthorized` | I don't know who you are: you haven't logged in |
| `403 Forbidden` | I know who you are, but you're not allowed |
| `404 Not Found` | there's no such thing |
| `409 Conflict` | it contradicts what's already there |
| `500 Internal Server Error` | something broke on the server |

⚠️ `401` is called Unauthorized, which sounds like "not allowed," but it
means "not logged in." "Logged in, but not allowed" is `403`.

A refusal based on role is sometimes returned as `404` too: that way an
outsider isn't even told the door exists.

### JSON

JSON (Article 0) is a text format programs use to exchange data:

* `{ … }` is an **object**: `"name": value` pairs separated by commas;
  `[ … ]` is an **array**, a list of values;
* strings are in double quotes; numbers and `true`/`false` aren't;
* `null` means "no value": the incident hasn't been fixed, so `fixedAt`
  is empty;
* `UUID` and time are strings: `"2026-10-14T10:05:00Z"` is the ISO 8601
  format, and `Z` means "in UTC." That's how Jackson writes any `Instant`.

### A path reads like nested folders

You read a path left to right, from general to specific: `/game-day` is
the Game Day, `/incidents` its incidents, `/{id}` one of them. The list of
all incidents would live at `/game-day/incidents`, a single incident at
`/game-day/incidents/<id>`. Names are plural nouns, in lowercase, with
hyphens between words. The method says what to do, not the path: `GET`, not `/getIncident`.

💡 In real projects the path often also starts with the version of the
contract with clients: `/v1/…`. An incompatible change to a response gets
`/v2/…`, while old clients stay on `v1`. The sandbox's only client is
you, so its paths have no version.

### curl: a request by hand

**curl** is a command-line program: it sends an HTTP request and prints
the response. A browser is a poor tool for checking endpoints: the address
bar sends only `GET`, and the browser hides the status and headers. In
the real project, you check an endpoint with `curl` on staging and paste
the output into the pull request. curl already comes with Git Bash, macOS,
and Linux.

```bash
curl -i http://localhost:8080/game-day/incidents/7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f
```

`-i` means print the status and headers, not just the body. There's no
endpoint yet: you'll send this request at the end of Part 3, once the
journal learns to answer.

⚠️ Type each command on a single line: in Git Bash, multi-line pastes
get glued together. In Windows PowerShell, `curl` is a different command
with the same name: type `curl.exe` or work in Git Bash.

---

## Part 2. The controller

### Spring MVC and the web starter

Tomcat (the web server inside the application, Article 2) hands the
request to the program as is. Without help, for every endpoint you'd have
to match the method and the path yourself, cut out the ID, and assemble
the JSON character by character. That work is done by **Spring MVC**, the
part of Spring that routes HTTP requests to methods of your classes.

Spring MVC, Tomcat, and Jackson come with the `spring-boot-starter-webmvc`
starter from the table in Article 2. Add it to the sandbox's `pom.xml`:

```xml
<dependency>                                <!-- web: Spring MVC, Tomcat, Jackson -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc</artifactId>
</dependency>
```

`<parent>` fills in the version. The old name you'll find online,
`spring-boot-starter-web`, is deprecated in Boot 4 (same table).

### The controller: a method becomes an endpoint

A **controller** is a bean whose methods answer HTTP requests. One method,
one endpoint.

```java
@RestController                                       // controller; what a method returns is the body
public class IncidentController {

    private final IncidentService service;            // service (below) via the constructor, as in Article 1

    public IncidentController(IncidentService service) {
        this.service = service;
    }

    @GetMapping("/game-day/incidents/{id}")           // GET on this path; {id} is the part that changes
    public IncidentResponse get(@PathVariable("id") String id) {   // the {id} part goes into id
        UUID incidentId = IncidentIds.parse(id);      // string → UUID, or a 400 error (below)
        return service.get(incidentId);               // the response is an IncidentResponse record (below)
    }
}
```

* `@RestController` means "a controller; whatever its methods return is
  the response body." Spring finds it during component scanning, like
  `@Service`;
* `@GetMapping("…")` means "call this method on a `GET` to this path";
  `{id}` is a **path variable**, and anything can stand in its place;
* `@PathVariable("id")` means "put the `{id}` part into this parameter."
  The name is written out explicitly: that way the endpoint doesn't depend
  on whether the compiler kept the parameter names.

As before, the short examples have no `import` lines; the full files are
at the end of the article. The controller and everything it needs live in
the journal's package, `example.gameday.journal`.

### Query parameters: @RequestParam

Our endpoint has no parameters, but the list endpoint will. They're read with
`@RequestParam`:

```java
@RequestParam(name = "open", required = false) Boolean open    // ?open=true → true; no parameter → null
```

`Boolean` is a wrapper: unlike `boolean`, it can be `null`. Without
`required = false`, Spring itself rejects a request that lacks the
parameter, with status `400`. But the response won't be in the format our
errors use (more on that in Part 3). Spring answers `?open=abc` the same
way: `abc` isn't a `Boolean`. That's why in the real project, parameters
such as the page number are made optional and checked by your own code,
with a response in the shared format.

### The response is a record; Jackson makes the JSON

```java
public record IncidentResponse(UUID id, String title, Instant detectedAt,
                               Instant fixedAt, String dutyName) {        // fixedAt can be null

    public static IncidentResponse of(Incident incident) {               // factory method (Article 0)
        return new IncidentResponse(incident.getId(), incident.getTitle(),
                incident.getDetectedAt(), incident.getFixedAt(), incident.getDutyName());
    }
}
```

The controller method returns a record; Spring hands it to Jackson (from Articles 0 and 2) and responds with status `200`. Jackson writes the JSON without
any annotations: a record field becomes a JSON field, `UUID` and `Instant`
become strings, and `null` stays `null`.

⚠️ Online, people add `jackson-datatype-jsr310` for dates: that's
Jackson 2; in Jackson 3, dates are built in. Not every annotation moved:
`@JsonProperty` from `jackson-annotations` stayed in
`com.fasterxml.jackson.annotation`, while `@JsonSerialize` now lives in
`tools.jackson.databind.annotation`.

**Why a record and not the `Incident` entity.** The entity mirrors the
table: rename a column, and a screen silently breaks. It can also hold
things that must not go outside. The response is a contract with
clients, and it changes separately from the table. More on this later in
the series.

### The service: where the controller gets its data

The controller knows HTTP, and the data is fetched by a service: a bean
with `@Service`, like `IncidentLog` in Article 3b. The service holds the
data and the rules; you can call it from places other than an endpoint
and test it without the web. `IncidentLog` records and notifies, while
a separate `IncidentService` does the showing. Why it already returns an
`IncidentResponse` and not the entity is covered later in the series.

```java
@Service
@Transactional(readOnly = true)                       // for all methods of the class; read only (below)
public class IncidentService {

    private final IncidentRepository repository;      // the repository from Article 3b

    public IncidentService(IncidentRepository repository) {
        this.repository = repository;
    }

    public IncidentResponse get(UUID id) {
        // either the incident exists, or a "no such thing" exception (Part 3)
        Incident incident = repository.findById(id)
                .orElseThrow(() -> new NoSuchEntryException("incident_not_found", "Incident not found"));
        return IncidentResponse.of(incident);
    }
}
```

`@Transactional` on a class applies to all its public methods.
`readOnly = true` is a hint: the transaction only reads, so Hibernate may
skip tracking changes to the objects it has read (the persistence context,
Article 3b). There's just one step here, but in the real project read
services are marked this way as a whole.

⚠️ The import is Spring's (Article 3b). Here it's no longer a matter of
style: `jakarta.transaction.Transactional` has no `readOnly` attribute at
all, and the code won't compile.

`findById(…).orElseThrow(…)` works as in `fixAll` from Article 3b: no
incident, an exception. Only it's not an `IllegalArgumentException` but
our own `NoSuchEntryException`, with a code and a message. What happens to it next is covered in Part 3.

### A malformed ID in the path: 400

You could declare the parameter as a `UUID` right away, and Spring would
parse the string itself. We don't, for two reasons. First: then garbage
like `abc` gets an answer not from our code but from Spring itself:
a `400` in Spring's own format, without our error code.

Second: Spring's parsing is lenient. It calls `UUID.fromString`, and that
accepts even `1-1-1-1-1`: it pads it with zeros and gets
`00000001-0001-0001-0001-000000000001`. A request with garbage would
reach the service and get "Incident not found" instead of "This is not an
incident number."

So the ID is taken as a string and parsed strictly, in a small class next
to the controller:

```java
public final class IncidentIds {                      // final: no subclasses needed

    private IncidentIds() {                           // no objects needed, just the method
    }

    public static UUID parse(String raw) {
        try {
            UUID id = UUID.fromString(raw);           // lenient parsing: 1-1-1-1-1 gets through too
            if (id.toString().equals(raw)) {          // strict check: back to a string, it must match exactly
                return id;
            }
        } catch (IllegalArgumentException e) {
            // not a UUID at all: the same response as below
        }
        throw new InvalidInputException("incident_id_invalid", "This is not an incident number");
    }
}
```

`UUID.toString()` always writes an ID the same way: 36 characters in the
`8-4-4-4-12` pattern, in lowercase. If that matches what was sent, the ID
is genuine. `1-1-1-1-1` turned into a different string, so it's a `400`.
An ID in uppercase is a `400` too: that's not how Java writes it. This is
the journal's choice: the rule "the way Java itself writes it" is the
shortest one there is.

The message of the `IllegalArgumentException` from `fromString` repeats
what was sent: `Invalid UUID string: abc`. That's why it doesn't go
outside, and our exception has its own message. Why that matters is in
Part 3. `InvalidInputException` is the second of our own exceptions, "the
input is invalid"; more on it there too.

In the real project, all "by ID" endpoints follow one pattern: the ID as
a string, strict parsing, `400` on garbage. The task itself is usually
not about parsing the ID but about what the endpoint fetches.

### Who gets in

Right now anyone who can reach port 8080 can call the journal endpoint.
In the real project that's not allowed: every request carries a login cookie, and
a person has **roles**, say `admin` and `viewer`. This is a person's
role, not the database role from Article 3a: same word, different thing.
Only an `admin` would be allowed to call the journal endpoint. Logging in and
role-based access come later in the series; in this article, the endpoint
is open to everyone.

---

## Part 3. Errors

### An endpoint doesn't catch errors, it throws them

Imagine every controller catching errors and building the response
itself. Ten endpoints, ten copies of `try/catch`: one forgot the error
code, another has its message in a different language, a third returns
`200` with the error in the body. The client can no longer rely on either
the status or the format.

🔑 **Code throws an exception, and one shared place turns it into
a response: the error handler.**

In the sandbox, that takes four classes. They're shared by the whole
application and sit in the root package, `example.gameday`, like
the `GameDayProperties` settings record.

The first two are exceptions: `NoSuchEntryException`, "no such thing,"
and `InvalidInputException`, "the input is invalid." Both are unchecked,
like all errors in the real project (Articles 0 and 3b). Each carries
a **code**, such as `incident_not_found`, and a **message** for people:

```java
public class NoSuchEntryException extends RuntimeException {

    private final String code;                        // for machines: incident_not_found

    public NoSuchEntryException(String code, String message) {
        super(message);                               // the message for people: getMessage() returns it
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```

`InvalidInputException` is built the same way; it's shown in full at the
end of the article.

The handler picks the status: "no such thing" is `404`, "invalid" is
`400`. The exception says what happened, and how to say it in HTTP is the
web layer's business, because the service is also called from places
with no HTTP at all: from `main`, from another service, from a scheduled
job.

The third class is the error response body, one format for all
endpoints:

```java
public record ErrorBody(String code, String message) {
}
```

The fourth is the handler itself; more on it below. Anything unexpected
it returns as `500` with the code `unexpected_error` and no details:
outsiders have no business knowing how the application is built.

The two fields of the response have two readers. `code` is for
**machines**: the client's code branches on it. `message` is for
**people**: one sentence in plain English, without whatever the client
sent. The client knows that already. And what was sent could be anything,
a very long string or even a line break, and it would end up in the
response and in the log (Article 2).

The third reader is whoever searches the log for a request; more on that
below, in "Request ID."

### How the handler finds the exception

The exception from the service flies up through the controller, and
nobody catches it. Spring MVC picks it up and looks for someone who knows
how to deal with it:

```
GET /game-day/incidents/7d1e…
    IncidentController.get
        IncidentService.get → throw NoSuchEntryException("incident_not_found", …)
    ↑ nobody catches it
Spring MVC: is there an @ExceptionHandler for NoSuchEntryException?
    → ErrorHandler.noSuchEntry
    → 404 {"code":"incident_not_found","message":"Incident not found"}
```

The handler is an ordinary bean with two annotations:

```java
@RestControllerAdvice                                 // advice for all controllers in the application
public class ErrorHandler {

    @ExceptionHandler(NoSuchEntryException.class)     // "NoSuchEntryException was thrown: call me"
    public ResponseEntity<ErrorBody> noSuchEntry(NoSuchEntryException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)             // status 404
                .body(new ErrorBody(e.getCode(), e.getMessage()));     // the body: the shared format
    }

    @ExceptionHandler(InvalidInputException.class)
    public ResponseEntity<ErrorBody> invalidInput(InvalidInputException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)           // status 400
                .body(new ErrorBody(e.getCode(), e.getMessage()));
    }
    …
}
```

* `@RestControllerAdvice` means "this bean helps all controllers at
  once"; whatever its method returns is the response, as with
  `@RestController`. Spring finds the bean itself: it's a component too,
  and the scanning from Article 2 sees it;
* `@ExceptionHandler(…)` means "if any controller throws this exception,
  call me instead of producing the normal response";
* `ResponseEntity` is the whole response: Spring takes the status, the
  headers, and the body from it (the angle brackets hold the body type,
  as in `List<String>`). `HttpStatus` is Spring's enum of statuses:
  `NOT_FOUND` is `404`.

### The unexpected: 500

The handler's third method catches everything else:

```java
    @ExceptionHandler(Exception.class)                // everything with no more specific method
    public ResponseEntity<ErrorBody> unexpected(Exception e) throws Exception {
        if (e instanceof ErrorResponse || e instanceof TypeMismatchException) {
            throw e;                                  // an error from Spring MVC itself: let Spring answer
        }
        logger.error("Unexpected error", e);          // to the log: everything, with the stack trace
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)        // to the client: no details
                .body(new ErrorBody("unexpected_error", "Unexpected error"));
    }
```

Read it in order.

* `Exception.class` matches any exception. Out of several matching
  methods, Spring picks the one whose type is **closest**:
  `NoSuchEntryException` has its own method, so that one gets called.
  What lands here is whatever nobody recognized: a `NullPointerException`,
  a database that went down, a bug in our code.
* Spring MVC throws exceptions of its own too: no such address, the wrong
  method, a missing required parameter, `?open=abc`. Spring knows their
  status and returns it itself, as long as you don't get in its way.
  Almost all of them are marked with the `ErrorResponse` interface from
  `org.springframework.web`, meaning "I know my HTTP status" (don't
  confuse it with our `ErrorBody`). Of the ones a read endpoint will run
  into, the only one without the mark is the error converting
  a parameter to the required type, `TypeMismatchException`.
  `throw e` means "not mine": Spring passes the exception on to its own
  handler, as if our method weren't there. Without this `if`, a request
  to a nonexistent address would get not a `404` but a `500`, "something
  broke on our side."
* The client gets only the code and a generic phrase, and the details go
  to the application **log**, with the stack trace: that's what you use to fix the problem.

`logger` is a field of the class:

```java
    private static final Logger logger = LoggerFactory.getLogger(ErrorHandler.class);
```

**SLF4J** is the library code uses to write to the log; `Logger`
and `LoggerFactory` are its classes. Why bother, when there's `System.out`
from Article 1? A line in the console won't tell you when, where, and how
serious it was, and a log line will: the time, the **level** (`ERROR`
means something broke, `WARN` something suspicious, `INFO` just for your
information), and the class name. You don't need to install it: it comes
with any Boot starter, and the lines themselves are printed by Logback,
the same library that prints the startup log. Where to look: in the same
place, the console, next to Boot's lines.
`getLogger(ErrorHandler.class)` creates a logger named after this class;
`logger.error(text, e)` writes a line at the `ERROR` level, with the
exception's stack trace under it.

What happens if the service throws a plain `RuntimeException("not found")`?
The handler won't recognize it as "no such thing." The client gets
`500 unexpected_error`, that is, "something broke on our side" instead of
"no such thing." And the log gets an `ERROR` line that someone will spend
a morning on.

💡 The list in the `if` is for this article: the endpoint only reads. For
endpoints that accept a body, Spring has more errors of its own, such as
invalid JSON in the request body. In the real project, the shared handler
is written once for the whole application, usually by a mid-level
developer; it knows all of Spring's errors and answers them in the same
format as our own. In the sandbox, Spring's errors come in Spring's own
format: that's one of the sandbox's simplifications.

### Request ID: X-Request-Id

In the real project, every request has an ID. The application issues one
to each request or takes the one sent in the `X-Request-Id` header. It
returns the ID in the same response header and as the third field of the
error body, `requestId`. The same ID appears in every log line for that
request.

Someone writes "I got an error, ID 8c1f…," and you can trace exactly that request in the log among thousands of others. The sandbox has no
request ID: there's one client, and the log is short.

⚠️ A common mistake is expecting Spring to return errors in the
`ProblemDetail` format (the fields `type`, `title`, `status`, `detail`):
advice online claims it does that on its own. In Boot 4.1, this format is
off by default for Spring MVC errors
(`spring.mvc.problemdetails.enabled=false`).
And the sandbox, like the real project, has its own format: clients
expect the `code` field. Don't turn it on.

### Check it by hand: curl

Build and start the sandbox as in Article 3b: Postgres in a container,
the three `SPRING_DATASOURCE_*` variables, and

```bash
./mvnw package
java -jar target/game-day-0.0.1-SNAPSHOT.jar
```

`./mvnw package` runs the database tests too; your Docker is already
running. There's something new in the log, a Tomcat line:

```
Tomcat started on port 8080 (http) with context path '/'
```

And most importantly: the application no longer exits. In Article 3b it
recorded an incident and quit, since there was nobody to wait for. Now it
has Tomcat inside, and Tomcat waits for requests until you stop the
application: `Ctrl+C` in the console or the red square in your IDE. The
lines from `main` are still there: `[notification] …` and
`game PT3H, attackers 2`. Each start still records "Broker is not
responding" in the journal.

Get the incident ID from the database, in another console window:

```bash
docker exec game-day-db psql -U postgres -c "SELECT id, title FROM game_day.incident"
```

`-c` means run one command and exit; you don't type anything into `psql`,
so you don't need `-it` either.

```
                  id                  |          title
--------------------------------------+--------------------------
 5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e | Broker is not responding
(1 row)
```

There may be more rows: each start adds one. Your ID will be different.
Ask the endpoint:

```bash
curl -i http://localhost:8080/game-day/incidents/5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e
```

```
HTTP/1.1 200
Content-Type: application/json
…

{"id":"5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e","title":"Broker is not responding",
 "detectedAt":"2026-10-20T09:15:03.512704Z","fixedAt":null,"dutyName":"duty-1"}
```

`…` stands for a couple more service headers, such as `Date`.
`detectedAt` came back with fractions of a second: the clock recorded the
moment precisely, and `TIMESTAMPTZ` stores it down to the microsecond
(Article 3b).

Now an ID that isn't in the journal, and garbage instead of an ID:

```bash
curl -i http://localhost:8080/game-day/incidents/7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f
curl -i http://localhost:8080/game-day/incidents/1-1-1-1-1
```

```
HTTP/1.1 404
Content-Type: application/json
…

{"code":"incident_not_found","message":"Incident not found"}
```

The second request gets a `400` and
`{"code":"incident_id_invalid","message":"This is not an incident number"}`:
it never reached the service.

And an address that doesn't exist at all:

```bash
curl -i http://localhost:8080/game-day/nothing
```

```
HTTP/1.1 404
Content-Type: application/json
…

{"timestamp":"…","status":404,"error":"Not Found","path":"/game-day/nothing"}
```

This time Spring answered on its own: our handler rethrew Spring's error. The
status is right, but the format is the one Boot builds, without `code`.

Take a look at the application log. There isn't a single `ERROR` line:
neither the `404` nor the `400` counts as unexpected. For its own `404`,
Spring left a `WARN` line with `NoResourceFoundException`, meaning "no
such address."

Also, a warning appeared on startup:
`spring.jpa.open-in-view is enabled by default`. With the web, Boot keeps
the persistence context (Article 3b) open for the whole request, right up
to the response. That doesn't bother our endpoint: the response is
assembled in the service, inside the transaction. We won't go into this
setting here; leave it alone for now.

Once you've had a look, stop the application with `Ctrl+C`. You can leave
the database running.

---

## Part 4. The web layer test

### A slice: the web without a database

`curl` is manual and doesn't run on every build. A test with the whole
application and the database (`*IT`, Article 3a) is slow, and it can also fail for reasons that have nothing to do with the endpoint. But you need to check the path, the ID
parsing, the status, the JSON, and the errors. For that there's
a **slice** (remember Article 2: a test that starts one layer), like an
engine on a test bench, without the car.

**`@WebMvcTest`** is Boot's annotation for a web slice. It starts Spring
MVC, Jackson, the controller you name, and advice beans such as the error
handler: no services, no repositories, no database. Without a controller
in the parentheses, all controllers would start. There's no database, so
the test is named `*Test`, not `*IT`: the boundary is the database
(Article 3a).

The slice comes with its own test starter:

```xml
<dependency>                                <!-- web slice: @WebMvcTest, MockMvcTester -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc-test</artifactId>
    <scope>test</scope>
</dependency>
```

⚠️ Online, `@WebMvcTest` comes from the
`org.springframework.boot.test.autoconfigure.web.servlet` package, right
in `spring-boot-starter-test`. That's Boot 2–3. In Boot 4 it has its own
test starter, `spring-boot-starter-webmvc-test` (Article 2), and the
package `org.springframework.boot.webmvc.test.autoconfigure`.

💡 The slice is based on `GameDayApplication` with all its annotations,
but it narrows the scanning. `GameDayConfig`, with the clock and the
on-call engineer, doesn't make it into the slice: the slice skips
`@Configuration` classes. The settings record isn't there either:
`@ConfigurationPropertiesScan` on the application class obeys the same
filter, and the slice doesn't create `GameDayProperties`. Set
`attackers: 0`, and the application won't start, but the slice stays
green. If the controller needs the record, add
`@EnableConfigurationProperties(GameDayProperties.class)` to the test
(Article 2): then Boot fills it from `application.yml` and checks
`@Validated`, just as when the application starts.

### A mock: Mockito and @MockitoBean

The slice has no service, but the controller needs one. You need
a **stub**: remember `RememberingNotifier` from Article 1? It's an object
that stands in for the real one in a test. Writing stubs by hand takes
a while: a class for every dependency, and `IncidentService` doesn't even
have an interface. For the repository in Article 3b it didn't work at
all: `JpaRepository` has dozens of methods.

**Mockito** is a library that makes such a stand-in, a **mock**, from any
class or interface in one line. Courses don't cover it, but at work it's
in nearly every service or endpoint test. You don't need to install it:
it's part of `spring-boot-starter-test`. It works inside the test: you
tell the mock what to answer, then check how it was called; if it was
called the wrong way, the test fails and says which call it expected.
Hand-written stubs and Mockito are covered in detail in
[Article 6, "When your code is surrounded by other code"](https://hammerhall.io/en/ledger/testing/6-stubs)
of the "From Red to Green" series.

* `when(service.get(ID)).thenReturn(response)` means "when someone asks
  for `get(ID)`, return this." Inside `when(…)`, the call to the mock's method isn't a real one: Mockito remembers which call is being set up
  and returns the response when the controller makes that call;
* `when(…).thenThrow(exception)` means "…throw this";
* `verifyNoInteractions(service)` means "the mock was never called."

`when` and `verifyNoInteractions` are static methods of the `Mockito`
class; you bring them into the test with `import static`. Without `when`,
the mock answers `get(ID)` with `null`. In the Boot documentation you'll
see `given(…).willReturn(…)` from `BDDMockito`: the same thing, written
differently.

**`@MockitoBean`** is an annotation on a test field: "put a mock of this
type into the Spring context and give it to me." If the context has a real
bean of that type, the mock replaces it. The controller gets the mock
through its constructor, like the real service.

In Article 3b, a second clock bean didn't get through: Boot doesn't allow
overriding beans. `@MockitoBean` is the permitted way to override one, for
tests only. In a database test of the journal, the field
`@MockitoBean private Clock clock;` takes the place of the `clock` bean,
and `when(clock.instant()).thenReturn(T0)` stops time for the journal.
But give such a test a class of its own: the mock applies to the whole
class. Without `when`, the mock clock answers `null`, and in tests that
didn't expect that, `fixAll` fails with a `NullPointerException`.

⚠️ Online you'll see `@MockBean`. That's Boot 2–3; it was removed in
Boot 4.0. In Boot 4 it's `@MockitoBean` from
`org.springframework.test.context.bean.override.mockito`.

### MockMvcTester: a request without the network

**MockMvc** is Spring's tool for web tests: it sends a request straight
into Spring MVC, without Tomcat and without the network.
**`MockMvcTester`** is the same thing with AssertJ-style assertions
(Article 0); `@WebMvcTest` registers it as a bean itself. JUnit creates
the test class, so the test asks for the bean through a field with
`@Autowired`, as in the Article 3a tests.

### A table-driven test

| case | request | service mock | expected |
|---|---|---|---|
| it exists | `…/incidents/7d1e…` | returns a response | `200`, the whole JSON |
| it doesn't exist | `…/incidents/7d1e…` | throws `NoSuchEntryException` | `404`, `code` is `incident_not_found` |
| malformed ID | `…/abc`, `…/1-1-1-1-1` | not called | `400`, `code` is `incident_id_invalid` |

```java
@WebMvcTest(IncidentController.class)                 // start only the web layer and this controller
class IncidentControllerTest {

    private static final String PATH = "/game-day/incidents/{id}";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");

    @Autowired
    private MockMvcTester mvc;                        // requests without the network, AssertJ assertions

    @MockitoBean
    private IncidentService service;                  // a mock instead of the real service

    @Test
    void returnsIncident() {
        when(service.get(ID)).thenReturn(new IncidentResponse(ID, "Broker is not responding",
                Instant.parse("2026-10-14T10:05:00Z"), null, "duty-1"));

        assertThat(mvc.get().uri(PATH, ID))           // GET …/incidents/7d1e…; {id} ← ID
                .hasStatusOk()                        // 200
                .bodyJson().isStrictlyEqualTo("""
                        {"id": "7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f",
                         "title": "Broker is not responding",
                         "detectedAt": "2026-10-14T10:05:00Z",
                         "fixedAt": null,
                         "dutyName": "duty-1"}
                        """);                         // the whole JSON, no extra fields
    }

    @Test
    void unknownIncidentIs404() {
        when(service.get(ID))
                .thenThrow(new NoSuchEntryException("incident_not_found", "Incident not found"));

        assertThat(mvc.get().uri(PATH, ID))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_not_found");
    }

    @ParameterizedTest(name = "{0} → 400")
    @ValueSource(strings = {"abc", "1-1-1-1-1"})
    void badIdIs400(String badId) {
        assertThat(mvc.get().uri(PATH, badId))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_id_invalid");
        verifyNoInteractions(service);                // the request never reached the service
    }
}
```

* `mvc.get().uri(PATH, ID)` is a `GET` request, with `ID` in place of
  `{id}`; `assertThat(…)` runs it and gives you assertions on the
  response;
* `bodyJson().isStrictlyEqualTo("""…""")` checks the whole JSON: the order
  of fields doesn't matter, but there must be no extra fields. If
  something leaks out of the entity, the test will notice.
  `"fixedAt": null` is a check too: the field is there, the value isn't;
* `extractingPath("$.code")` picks one field: `$` is the whole JSON,
  `.code` is the `code` field. An error's message may change, but what
  matters to machines is the code, so that's what we check;
* `verifyNoInteractions` checks that the ID is rejected **before** any
  work with the data. If this test fails, the request reached the
  service: the ID isn't being checked in the controller.

🔑 **The slice checks the web; the mock takes care of the rest.** The
`404` test doesn't touch the repository: the mock throws an exception, and
the test checks the path "exception → handler → `ErrorBody`." That the
service itself throws `NoSuchEntryException` is a job for its own test
without Spring, later in the series.

This shows the technique, not a complete set: in the real project, the
cases for an endpoint test are listed in the table in the task
description, and each row gets its own test.

**Running it.** `./mvnw verify` runs all the tests, the database tests
included, and those need Docker running (Article 3a). To run just the
slice, use `./mvnw test -Dtest=IncidentControllerTest`, where `-Dtest=`
means "only this class," or the triangle in your IDE. The slice doesn't
need Docker: there's no database in it.

⚠️ A test and the live application may answer differently. Errors that
Spring answers itself are visible in MockMvc only by their status. These
are, say, an unknown address or the wrong method. Their body is built by
the internal `/error` address, and MockMvc never gets that far. That's
why in a slice such responses are checked by status, and the body with
`curl` against the running application.

There's also a third case, `hasFailed()`: an exception nobody caught.
With the sandbox's handler it never comes to that: everything Spring
doesn't recognize becomes a `500`.

---

## Check yourself

Answer in your own words, out loud or on paper. If you can't, reread the
section.

1. What are an HTTP request and response made of? Where in the request
   is the incident ID, and where would "only open ones" go?
2. How does `401` differ from `403`? Why is a refusal based on role
   sometimes returned as `404`?
3. Why does the endpoint return an `IncidentResponse` and not the
   `Incident` entity?
4. Why is the ID from the path taken as a string and not as a `UUID`
   right away? What does `UUID.fromString` do with `1-1-1-1-1`, and how
   does `IncidentIds` notice?
5. The service threw `NoSuchEntryException`. Who catches the exception,
   who picks the status, and why isn't it the exception itself?
6. The handler catches `Exception`. Why does it need the `if` with
   `throw e`, and what would happen without it? Why does the client get
   a generic phrase while the details go to the log?
7. Why use a `@WebMvcTest` slice when you could start the whole
   application? Why is it a `*Test` and not an `*IT`, and what's missing
   from it?
8. How does a Mockito mock differ from the stub you wrote by hand in
   Article 1? What actually happens to the call inside `when(…)`?

---

## What's next

Next in the series is the full endpoint: a paged list of incidents,
role-based access, and tests for every layer, including a service test
without Spring.

## Sources

* [MDN: An overview of HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Overview):
  the request, the response, headers, and statuses;
* [RFC 9110: HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html):
  the HTTP standard itself; read it selectively: methods are in Section 9,
  statuses in Section 15;
* [Spring Framework: Exceptions](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-exceptionhandler.html):
  `@ExceptionHandler`, how the method is chosen, and what it means to
  rethrow an exception;
* [Spring Boot: Testing Spring Boot Applications](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html):
  `@WebMvcTest`, what goes into the slice, and `@MockitoBean` in action;
* [Spring Framework: MockMvc — AssertJ Integration](https://docs.spring.io/spring-framework/reference/testing/mockmvc/assertj.html):
  every `MockMvcTester` assertion;
* [Spring Framework: @MockitoBean and @MockitoSpyBean](https://docs.spring.io/spring-framework/reference/testing/annotations/integration-spring/annotation-mockitobean.html):
  how a mock takes the place of a bean.

---

## The full example, with imports

A learning example. Run it in the `game-day` sandbox after Article 3b.
Everything already there stays unchanged: `GameDayApplication`,
`GameDayProperties` with its test, `application.yml` and
`application-stand.yml`, the `V1__game_day_incident.sql` migration,
`TestcontainersConfiguration`, the journal in `example.gameday.journal`
(`Incident`, `IncidentRepository`, `IncidentLog`, `DutyRoster`,
`Notifier`, `ConsoleNotifier`, `GameDayConfig`), and its tests.

What to add: two starters in `pom.xml`; in `example.gameday`, the
`NoSuchEntryException` and `InvalidInputException` exceptions, the
`ErrorBody` error body, and the `ErrorHandler` handler; in
`example.gameday.journal`, `IncidentResponse`, `IncidentService`,
`IncidentIds`, `IncidentController`, and the `IncidentControllerTest`
test. The database tests need Docker running; the slice doesn't.

```xml
<!-- pom.xml: in <dependencies>, next to what's already there -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-webmvc-test</artifactId>
    <scope>test</scope>
</dependency>
```

```java
// src/main/java/example/gameday/NoSuchEntryException.java
package example.gameday;

/** "No such thing": the handler answers 404. The code is for machines, the message for people. */
public class NoSuchEntryException extends RuntimeException {

    private final String code;

    public NoSuchEntryException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```

```java
// src/main/java/example/gameday/InvalidInputException.java
package example.gameday;

/** "The input is invalid": the handler answers 400. The code is for machines, the message for people. */
public class InvalidInputException extends RuntimeException {

    private final String code;

    public InvalidInputException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```

```java
// src/main/java/example/gameday/ErrorBody.java
package example.gameday;

/** The error response body, the same for all endpoints. */
public record ErrorBody(String code, String message) {
}
```

```java
// src/main/java/example/gameday/ErrorHandler.java
package example.gameday;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.TypeMismatchException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ErrorHandler {

    private static final Logger logger = LoggerFactory.getLogger(ErrorHandler.class);

    @ExceptionHandler(NoSuchEntryException.class)
    public ResponseEntity<ErrorBody> noSuchEntry(NoSuchEntryException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(new ErrorBody(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(InvalidInputException.class)
    public ResponseEntity<ErrorBody> invalidInput(InvalidInputException e) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorBody(e.getCode(), e.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorBody> unexpected(Exception e) throws Exception {
        if (e instanceof ErrorResponse || e instanceof TypeMismatchException) {
            throw e;
        }
        logger.error("Unexpected error", e);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new ErrorBody("unexpected_error", "Unexpected error"));
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentResponse.java
package example.gameday.journal;

import java.time.Instant;
import java.util.UUID;

public record IncidentResponse(UUID id, String title, Instant detectedAt,
                               Instant fixedAt, String dutyName) {

    public static IncidentResponse of(Incident incident) {
        return new IncidentResponse(incident.getId(), incident.getTitle(),
                incident.getDetectedAt(), incident.getFixedAt(), incident.getDutyName());
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentService.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class IncidentService {

    private final IncidentRepository repository;

    public IncidentService(IncidentRepository repository) {
        this.repository = repository;
    }

    public IncidentResponse get(UUID id) {
        Incident incident = repository.findById(id)
                .orElseThrow(() -> new NoSuchEntryException("incident_not_found", "Incident not found"));
        return IncidentResponse.of(incident);
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentIds.java
package example.gameday.journal;

import example.gameday.InvalidInputException;

import java.util.UUID;

/** The incident ID from the path: strictly in the form UUID.toString() writes it. */
public final class IncidentIds {

    private IncidentIds() {
    }

    public static UUID parse(String raw) {
        try {
            UUID id = UUID.fromString(raw);
            if (id.toString().equals(raw)) {
                return id;
            }
        } catch (IllegalArgumentException e) {
            // not a UUID at all: the same response as below
        }
        throw new InvalidInputException("incident_id_invalid", "This is not an incident number");
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentController.java
package example.gameday.journal;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
public class IncidentController {

    private final IncidentService service;

    public IncidentController(IncidentService service) {
        this.service = service;
    }

    @GetMapping("/game-day/incidents/{id}")
    public IncidentResponse get(@PathVariable("id") String id) {
        UUID incidentId = IncidentIds.parse(id);
        return service.get(incidentId);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentControllerTest.java
package example.gameday.journal;

import example.gameday.NoSuchEntryException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

import java.time.Instant;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@WebMvcTest(IncidentController.class)
class IncidentControllerTest {

    private static final String PATH = "/game-day/incidents/{id}";
    private static final UUID ID = UUID.fromString("7d1e3c52-9a4b-4f10-8c2d-1b2a3c4d5e6f");

    @Autowired
    private MockMvcTester mvc;

    @MockitoBean
    private IncidentService service;

    @Test
    void returnsIncident() {
        when(service.get(ID)).thenReturn(new IncidentResponse(ID, "Broker is not responding",
                Instant.parse("2026-10-14T10:05:00Z"), null, "duty-1"));

        assertThat(mvc.get().uri(PATH, ID))
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

        assertThat(mvc.get().uri(PATH, ID))
                .hasStatus(HttpStatus.NOT_FOUND)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_not_found");
    }

    @ParameterizedTest(name = "{0} → 400")
    @ValueSource(strings = {"abc", "1-1-1-1-1"})
    void badIdIs400(String badId) {
        assertThat(mvc.get().uri(PATH, badId))
                .hasStatus(HttpStatus.BAD_REQUEST)
                .bodyJson().extractingPath("$.code").isEqualTo("incident_id_invalid");
        verifyNoInteractions(service);
    }
}
```
