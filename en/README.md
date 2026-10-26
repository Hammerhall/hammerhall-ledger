# Hammerhall Ledger — English edition

[![Article examples](https://github.com/Hammerhall/hammerhall-ledger/actions/workflows/examples.yml/badge.svg)](https://github.com/Hammerhall/hammerhall-ledger/actions/workflows/examples.yml)

Articles for Java juniors from Hammerhall. The English edition so far: the
"From Java to Spring Boot" cycle and the "From Red to Green" series on tests;
more cycles follow.

**Easier to read on the site → [hammerhall.io/en/ledger](https://hammerhall.io/en/ledger)**

The same texts live here in Markdown. Links inside the articles lead to
the site. The code from the articles is in [`examples/en/`](../examples/en/):
every CI run builds it and runs its tests.

Russian edition → [README.md](../README.md).

---

# Bootcamp / Lab

How Hammerhall teams write code: the bootcamp works in public repositories,
the lab in private ones. The "From … to …" series cover what a newcomer
needs before their first task. Read the articles in order: they share one
example that grows from article to article, the learning project "Game Day".

## From Java to Spring Boot

What to know before Spring, why you need it at all, how Spring Boot 4
works, how an application stores data and answers over HTTP.

| # | Article | Text | Code |
|---|---|---|---|
| 0 | [What to know before Spring](https://hammerhall.io/en/ledger/articles/0-before-spring) | [md](articles/00-before-spring.md) | [example](../examples/en/articles/00-before-spring) |
| 1 | [Why Spring](https://hammerhall.io/en/ledger/articles/1-why-spring) | [md](articles/01-why-spring.md) | [example](../examples/en/articles/01-why-spring) |
| 2 | [Spring Boot 4 for absolute beginners](https://hammerhall.io/en/ledger/articles/2-spring-boot-4) | [md](articles/02-spring-boot-4.md) | [example](../examples/en/articles/02-spring-boot-4) |
| 3a | [Data, part 1: a table and a migration](https://hammerhall.io/en/ledger/articles/3a-table-and-migration) | [md](articles/03a-table-and-migration.md) | [example](../examples/en/articles/03a-table-and-migration) |
| 3b | [Data, part 2: entity, repository, transaction](https://hammerhall.io/en/ledger/articles/3b-entity-and-transaction) | [md](articles/03b-entity-and-transaction.md) | [example](../examples/en/articles/03b-entity-and-transaction) |
| 4 | [Your first endpoint: how an application answers over HTTP](https://hammerhall.io/en/ledger/articles/4-web) | [md](articles/04-web.md) | [example](../examples/en/articles/04-web) |
| 5 | [The full endpoint: layers, access, paging, tests on every layer](https://hammerhall.io/en/ledger/articles/5-full-endpoint) | [md](articles/05-full-endpoint.md) | [example](../examples/en/articles/05-full-endpoint) |

## From Red to Green

How to work with tests on a project: writing them, reading a red build,
and trusting a green test only if you've seen it red.

| # | Article | Text | Code |
|---|---|---|---|
| 1 | [Why tests, and what the project expects from you](https://hammerhall.io/en/ledger/testing/1-why-tests) | [md](testing/01-why-tests.md) | [example](../examples/en/testing/01-why-tests) |
| 2 | [Your first unit test: from an empty file to a green report](https://hammerhall.io/en/ledger/testing/2-first-test) | [md](testing/02-first-test.md) | [example](../examples/en/testing/02-first-test) |
| 3 | [The test went red: what to do](https://hammerhall.io/en/ledger/testing/3-red-test) | [md](testing/03-red-test.md) | [example](../examples/en/testing/03-red-test) |
| 4 | [Which cases to test](https://hammerhall.io/en/ledger/testing/4-which-cases) | [md](testing/04-which-cases.md) | [example](../examples/en/testing/04-which-cases) |
| 5 | [A test that checks nothing](https://hammerhall.io/en/ledger/testing/5-test-that-checks-nothing) | [md](testing/05-test-that-checks-nothing.md) | [example](../examples/en/testing/05-test-that-checks-nothing) |
| 6 | [When your code is surrounded by other code](https://hammerhall.io/en/ledger/testing/6-stubs) | [md](testing/06-stubs.md) | [example](../examples/en/testing/06-stubs) |
| 7 | [A test with a real database](https://hammerhall.io/en/ledger/testing/7-real-database) | [md](testing/07-real-database.md) | [example](../examples/en/testing/07-real-database) |

Coming in English: "From Spring to a System" (6–11), "From a System to
the Business" (12–18), the "Streams, Step by Step" series and the rest
of the library. Until then, links to those texts lead to the Russian pages.

## New articles

Texts appear here on the day they go live on the site. Star ⭐ the
repository and press Watch to catch new ones.

## License

Texts — [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/):
share and adapt with attribution, not for sale, under the same terms.
Code from the articles and examples — [MIT](../LICENSE-CODE). Details —
[LICENSE.md](../LICENSE.md).
