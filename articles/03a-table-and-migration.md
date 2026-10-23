# Данные, часть 1: таблица и миграция

> «От Java к Spring Boot» · статья 3а · читать минут 30
>
> **Для кого.** Ты прочитал статьи 0–2 и завёл песочницу `game-day`:
> в ней бины, настройки Boot и тесты на JUnit. SQL — на уровне `SELECT`.
> Docker поставим по ходу.
>
> **Что будет.** Три вещи: как описать таблицу на SQL, чтобы база сама
> стерегла правила; как менять устройство базы одинаково на всех базах
> сразу — миграции и Flyway; как проверить миграцию тестом на настоящем
> Postgres — Docker и Testcontainers.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Java к Spring Boot» — то, что
> нужно новичку до первой задачи на Spring Boot 4. Примеры — учебные:
> их можно повторить у себя.

---

## Зачем база и почему её устройство не правят руками

Журнал игрового дня из статьи 1 происшествия не хранит — только
оповещает. Сложи их в список в памяти программы — и после перезапуска
список пуст. А перезапускают приложение постоянно: выкатка, падение,
перезагрузка сервера. Данные, которые должны пережить перезапуск,
хранят в базе.

Сложность в другом: база у проекта не одна. Своя у тебя на машине, своя
в каждом прогоне тестов, своя на стенде и на боевом. Устроены они должны
быть одинаково.

Менять их устройство руками — значит «зашёл и поправил». Это верный
путь к расхождениям: на своей поправил, на стенде забыл, на боевом
опечатался. Узнаешь об этом при выкатке, самым дорогим способом.

Тема «Данные» — две статьи. В этой журнал получает таблицу, миграцию
и тест на настоящей базе. Во второй части Java научится с таблицей
работать: сущность, хранилище, транзакция.

---

## Часть 1. База и таблица

### PostgreSQL

**PostgreSQL** (коротко Postgres) — программа-сервер баз данных:
хранит таблицы и выполняет запросы на SQL.

**Зачем.** В курсах базу ставят себе на один вечер. Рабочему сервису
нужна база, устроенная одинаково везде, где он работает.

**Откуда берётся.** Ставить себе не нужно: Postgres поднимают
в контейнере Docker — одной командой, ниже. В тестах базу поднимает
Testcontainers — о нём часть 3.

**Где смотреть.** Клиентом `psql` из того же контейнера или окном баз
данных в IDE.

### Docker

**Docker** — программа, которая запускает другие программы
в изолированных коробках, **контейнерах**. Контейнер поднимают
из **образа** — готового снимка программы: из образа `postgres:17-alpine`
за секунды поднимается Postgres 17 на маленьком Linux (Alpine), а после
удаляется без следа. Контейнер здесь — Docker, не Spring: со словом
из статьи 1 совпало только название.

На Windows и macOS Docker ставят как **Docker Desktop** (docs.docker.com,
раздел Get Docker), на Linux — Docker Engine. Поставь, запусти Docker
Desktop и проверь в консоли:

```bash
docker version
```

Часть `Server` в ответе — сам Docker, который запускает контейнеры.
Нет её, а вместо неё ошибка подключения — Docker Desktop
не запущен. Подробно об образах и контейнерах — в статье 6 «Стенд
своими руками».

### Postgres на минуту

```bash
docker run -d --rm --name game-day-db -p 127.0.0.1:5432:5432 \
    -e POSTGRES_PASSWORD=game-day-local postgres:17-alpine
docker exec -it game-day-db psql -U postgres
```

* `-d` — в фоне; `--rm` — удалить контейнер вместе с данными, когда
  он остановится; `--name` — имя для следующих команд;
* `-p 127.0.0.1:5432:5432` — порт 5432 у тебя ведёт в порт базы
  в контейнере, и только с твоей машины. Занят (у тебя уже стоит
  Postgres) — возьми слева другой: `127.0.0.1:5433:5432`;
* `-e POSTGRES_PASSWORD=…` — переменная окружения (статья 2): пароль
  пользователя `postgres`, без него образ не стартует;
* `docker exec -it … psql -U postgres` — запустить `psql` в контейнере;
  `-it` — чтобы можно было печатать. Git Bash ответил `the input device
  is not a TTY` — допиши в начало команды `winpty`.

Нет подключения — подожди пару секунд: база просыпается. SQL пиши после
`postgres=#`, с `;` в конце; выйти — `\q`. В IDE подключайся
к `127.0.0.1:5432` пользователем `postgres`.

### Схема и роль

Таблицы внутри базы раскладывают по **схемам**. Схема — именованная
папка для таблиц: полное имя таблицы — «схема.таблица». Не назвал
схему — таблица попадёт в схему по умолчанию, обычно `public`.
**Роль** базы — учётная запись, под которой программа входит в базу,
со своими правами: какие схемы видит и что в них может.

В рабочем проекте у приложения своя схема и своя роль, которой чужие
схемы и `public` не видны. На боевом несколько приложений нередко живут
в одном Postgres. Своя роль не даст тронуть чужие таблицы даже
случайно — как своя комната в общей квартире и ключ только от неё.
Прав у роли ровно столько, сколько нужно для работы.

В песочнице схема своя — `game_day`, а своей роли нет: у контейнера
один пользователь со всеми правами, учебной базе хватит.

Правило: имя схемы пишется явно — `game_day.incident`, а не `incident`.
Иначе таблица окажется там, куда укажут настройки подключения, а это
гадание.

### Таблица происшествий

Таблицу создаёт команда `CREATE TABLE имя (…)`: в скобках через запятую
идут столбцы — имя, тип, правила. В конце могут стоять правила на всю
таблицу.

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

Куда положить этот SQL, расскажет часть 2. А пока — по строкам:

* `PRIMARY KEY` — **первичный ключ**: столбец, по которому строку
  находят однозначно. Повтор и пустое значение база в нём не пустит;
* `UUID` — тип ключа: 128-битный идентификатор вида
  `5b0c7a52-6f1e-4c2a-9d4e-0f5a1b2c3d4e`. В отличие от номеров 1, 2, 3
  его не угадать. И создать его можно где угодно, хоть в Java до
  записи. В рабочем проекте свои идентификаторы — `UUID`; номера и имена,
  которые пришли из чужой системы, хранят как есть;
* `DEFAULT gen_random_uuid()` — значение на случай, если его
  не передали: ключ придумает сама база (во второй части ключ будет
  создавать и Java — зачем оба, там же);
* `VARCHAR(200)` — строка не длиннее 200 знаков. Длиннее база
  не примет;
* `NOT NULL` — значение обязательно. `NULL` у `fixed_at` — явное
  «можно пусто»: пусто — значит, ещё не починили;
* `CHECK (…)` — **ограничение-проверка**: условие, которое база
  проверяет при каждой записи. `btrim` убирает пробелы по краям, так что
  заголовок из одних пробелов тоже не пройдёт;
* последний `CHECK` смотрит на два столбца сразу: починить раньше, чем
  заметили, нельзя. `CONSTRAINT …` даёт проверке имя, и база назовёт
  его в ошибке.

Попробуй в `psql`. Схему в базе на минуту создай руками, командой
`CREATE SCHEMA game_day;`. Потом выполни `CREATE TABLE` целиком и вставь
строку, где починили раньше, чем заметили:

```sql
INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1');
```

```
ERROR:  new row for relation "incident" violates check constraint "incident_fixed_after_detected"
```

🔑 Проверки в таблице — последний рубеж: даже если в коде правило
забыли, база испорченную строку не примет. Ошибка, пойманная базой,
лучше тихо испорченных данных.

### Время: TIMESTAMPTZ и Instant

**Часовой пояс** — сдвиг местного времени от всемирного (UTC): 12:15
в Москве и 09:15 по UTC — один и тот же момент. В Postgres для времени
два типа:

* `TIMESTAMP` хранит «часы на стене», например `12:15`, и не знает, чьи
  это часы. Записал сервер с часами по UTC, прочитал ноутбук с московским
  временем — и уже не скажешь, когда на самом деле заметили
  происшествие;
* `TIMESTAMPTZ` хранит **момент**: при записи Postgres переводит время
  в UTC, при чтении показывает в поясе того, кто спрашивает.

Вставь строку как надо, без `fixed_at`, и посмотри на неё из двух
поясов. `SET TIME ZONE` задаёт пояс только для твоего подключения:

```sql
INSERT INTO game_day.incident (title, detected_at, duty_name)
VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', 'duty-1');

SET TIME ZONE 'UTC';
SELECT detected_at FROM game_day.incident;      -- 2026-10-05 09:15:00+00

SET TIME ZONE 'Europe/Moscow';
SELECT detected_at FROM game_day.incident;      -- 2026-10-05 12:15:00+03
```

В Java моменту соответствует `Instant` из статьи 1.
В рабочем проекте пара `TIMESTAMPTZ` ↔ `Instant` — правило.

Посмотрел — выйди (`\q`) и погаси базу: `docker stop game-day-db`.
С `--rm` контейнер удалится вместе со схемой и таблицей. Дальше их
создаёт не рука, а Flyway.

### Внешнего ключа на дежурного нет

**Внешний ключ** (`REFERENCES`) — правило базы: «значение этого столбца
обязано быть ключом строки в той таблице». В журнале стоит
`duty_name VARCHAR(50)` — и без внешнего ключа. Список дежурных журнал
не хранит: его даёт `DutyRoster` из статьи 1, а в рабочем проекте люди
обычно живут в другом сервисе, со своей базой. На локальном стенде
и в тестах той таблицы нет вовсе, а роль приложения чужие схемы не видит:
ссылаться не на что. Поэтому имя хранят просто значением. Внешние
ключи ставят только между таблицами своей схемы: там база сама следит,
чтобы ссылка не повисла в воздухе.

---

## Часть 2. Миграции и Flyway

### Миграция — пронумерованный SQL-файл

Ответ на беду из начала — не менять руками **устройство** базы:
таблицы, столбцы, проверки. Каждое такое изменение записывают в файл
и кладут в git рядом с кодом. Такой файл называют **миграцией**. Наша
первая — `CREATE TABLE` из части 1:

```
src/main/resources/db/migration/
    V1__game_day_incident.sql      ← наша, первая в песочнице
    V2__…                          ← следующее изменение — следующий номер
```

Миграции — как пункты протокола: пронумерованы, новые дописывают
в конец, написанное не исправляют. Выполни их все по порядку — и на
любой машине получишь одну и ту же базу. Выполняет их программа.

### Flyway

**Flyway** — библиотека, которая применяет миграции к базе.

**Зачем.** В курсах таблицу создают руками в клиенте базы — как ты
только что в `psql`: пока база одна и ты один, сойдёт. На работе баз
и людей много, и держать базы одинаковыми может только машина. Flyway
смотрит, какие миграции база уже видела, и применяет только новые —
по порядку номеров, каждую ровно один раз.

Помнит он это в служебной таблице истории `flyway_schema_history`:
номер, описание и **контрольная сумма** каждой применённой миграции.
Сумма — число, вычисленное по содержимому файла: поменяй хоть букву —
сумма станет другой.

**Откуда берётся в проекте.** Из зависимостей в `pom.xml`. В песочнице
их добавляешь ты сам (в рабочем проекте — мидл, статья 0):

```xml
<dependency>                                <!-- подключение к базе и JdbcTemplate (часть 3) -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-jdbc</artifactId>
</dependency>
<dependency>                                <!-- Flyway и его запуск при старте -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-flyway</artifactId>
</dependency>
<dependency>                                <!-- Flyway для Postgres: стартер его не приносит -->
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
<dependency>                                <!-- драйвер Postgres -->
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <scope>runtime</scope>
</dependency>
```

**JDBC** — стандартный способ Java говорить с базами; **драйвер** —
библиотека, которая учит его языку конкретной базы. `<scope>runtime</scope>` —
драйвер нужен работающей программе, а не компиляции. Версии подставляет
`<parent>`, как в статье 0.

Схему Flyway создаст сам — назови её в `application.yml`:

```yaml
spring:
  flyway:
    schemas: game_day        # нет такой схемы — создать; историю вести в ней
```

**Как запускается.** Сам, при старте приложения и при старте тестов
на базе: Spring Boot запускает миграции раньше, чем приложение начнёт
работать с базой. Что сделал, Flyway пишет в лог запуска.

⚠️ В интернете ты увидишь, что для Flyway хватает зависимости
`flyway-core`. Это Boot 2–3. В Boot 4 нужен стартер
`spring-boot-starter-flyway`. Без него Flyway не запускается и молчит:
приложение поднимется, а таблицы не будет — упадёт первый же запрос
к ней.

### Имя файла и папка

Имя `V1__game_day_incident.sql` читается так: `V` — версионная миграция;
`1` — номер, по нему Flyway выстраивает порядок; `__` — **два**
подчёркивания; `game_day_incident` — что делает миграция, маленькими
латинскими буквами через `_`; `.sql`. С одним подчёркиванием Flyway
не узнает в файле миграцию и просто его не увидит: таблицы не будет.

Папка — `src/main/resources/db/migration`: там Flyway ищет миграции
по умолчанию. В рабочем проекте имена, номера и схему во всех файлах
миграций проверяет отдельный тест правил. Такую ошибку там ловит
сборка, а не выкатка.

### Первый запуск

Подними чистую базу — той же `docker run`, что в части 1. Где база,
приложение узнаёт из настроек; задай их переменными окружения, как
стоп-слово в статье 2:

```bash
./mvnw package -DskipTests        # собрать без тестов: тестам на базе нужна часть 3
export SPRING_DATASOURCE_URL=jdbc:postgresql://127.0.0.1:5432/postgres
export SPRING_DATASOURCE_USERNAME=postgres
export SPRING_DATASOURCE_PASSWORD=game-day-local
java -jar target/game-day-0.0.1-SNAPSHOT.jar
```

`SPRING_DATASOURCE_URL` — настройка `spring.datasource.url`, адрес базы
для JDBC: сервер, порт и имя базы (`postgres` образ создал сам). В IDE
те же три переменные — в поле Environment variables.

В логе — строка Flyway, а после неё знакомое по статье 2:

```
Successfully applied 1 migration to schema "game_day", now at version v1 (execution time …)
[оповещение] duty-1: Брокер не отвечает — замечено 2026-…Z
игра PT3H, атакующих 2
```

Историю посмотри в `psql` (`docker exec -it game-day-db psql -U postgres`):

```sql
SELECT version, description, checksum
FROM game_day.flyway_schema_history
ORDER BY installed_rank;
```

```
 version |         description          | checksum
---------+------------------------------+-----------
         | << Flyway Schema Creation >> |
 1       | game day incident            | 280339142
```

Первая строка — пометка Flyway: схему `game_day` создал он сам. Вторая —
наша миграция: номер, описание из имени файла и контрольная сумма.
История лежит в схеме `game_day`, первой из `schemas`. Запусти
приложение ещё раз — в логе будет `Schema "game_day" is up to date.
No migration necessary.`: эту миграцию база уже видела.

### 🔴 Применённую миграцию не правят никогда

Миграция уже прошла на стенде, а ты нашёл в ней ошибку. Хочется поправить
файл: тема-то та же. Нельзя. При следующем запуске Flyway сверит сумму
файла с историей, и они не сойдутся. Приложение **не стартует**
на каждой базе, где миграция уже применена.

Проверь на своей: допиши в V1 после `duty_name` строку
`note VARCHAR(500) NULL,`, пересобери и запусти. Приложение не поднимется:

```
Migration checksum mismatch for migration version 1
-> Applied to database : 280339142
-> Resolved locally    : -1348780172
```

Так однажды в рабочем проекте упала выкатка: в миграцию, три часа
назад ушедшую на боевой, дописали ещё один столбец.

Не спасает и команда `flyway repair`: она перепишет сумму в истории,
но дописанное не выполнит — столбца не будет, и код упадёт на первом
обращении к нему.

🔑 Изменение базы — всегда **новая** миграция: ошибку в V1 чинит V2
с `ALTER TABLE …` (команда SQL, которая меняет существующую таблицу).
Пока пул-реквест не влит, файл живёт только у тебя, и править его
можно. В тестах база каждый раз новая — там правка ничего не ломает.
А если миграция уже прошла на твоей базе в контейнере, пересоздай её:
`docker stop game-day-db` и снова `docker run` — с `--rm` старая уйдёт
вместе с историей. Сейчас так и сделай: убери `note` из V1 и пересоздай
базу.

### Номер — следующий свободный в основной ветке

Номер берут **следующий свободный в основной ветке репозитория
на момент пул-реквеста**, а не начала работы: пока ты писал, кто-то мог
влить миграцию с тем же номером. Git конфликта не покажет — имена
у файлов разные: `V7__a.sql` и `V7__b.sql`. А двух одинаковых номеров
не примет Flyway, и приложение не стартует. В рабочем проекте свой файл
перед слиянием переименовывает тот, кто вливает вторым.

---

## Часть 3. Проверка на настоящей базе

### Почему не «база в памяти»

Миграцию надо проверить: применилась ли она и держат ли проверки.
В старых туториалах для таких тестов берут H2 — базу, которая живёт
прямо в памяти Java и поднимается за миг.

Но H2 — не Postgres: другой SQL, другие типы, схемы и права. Миграция
для Postgres на H2 может не пройти — или пройти, но вести себя иначе:
тест зелёный, а на боевом падает. Поэтому тест базы идёт на настоящем
Postgres.

### Testcontainers

**Testcontainers** — Java-библиотека, которая из кода тестов поднимает
контейнеры Docker и убирает их после.

**Зачем.** Тестам нужна своя база: чистая на каждый прогон, той же
версии, на любой машине — у тебя, у коллеги и в проверке пул-реквеста.

**Откуда берётся в проекте.** Ещё две зависимости, обе только для тестов:

```xml
<dependency>                                <!-- связка Testcontainers со Spring Boot -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-testcontainers</artifactId>
    <scope>test</scope>
</dependency>
<dependency>                                <!-- контейнер с Postgres -->
    <groupId>org.testcontainers</groupId>
    <artifactId>testcontainers-postgresql</artifactId>
    <scope>test</scope>
</dependency>
```

**Как запускается.** Сам, той же `./mvnw verify`, — только Docker должен
быть запущен. Первый прогон долгий: Docker скачивает образ. Пока идут
тесты, `docker ps` покажет контейнер Postgres и служебный контейнер
Ryuk: он прибирает за тестами, даже если прогон оборвался. Не запущен
Docker — тесты на базе упадут в самом начале с ошибкой
`Could not find a valid Docker environment`.

⚠️ В интернете ты увидишь `org.testcontainers:postgresql` и класс
`org.testcontainers.containers.PostgreSQLContainer<?>` (`<?>` — «какой-то
параметр типа»). Это Testcontainers 1.x. В Boot 4 — 2.0: модуль
`testcontainers-postgresql` и класс
`org.testcontainers.postgresql.PostgreSQLContainer` — без `<?>`.

### Контейнер — бином

Тесту нужно приложение, подключённое к контейнеру. Для этого контейнер
делают бином — в отдельном классе настроек рядом с тестами:

```java
@TestConfiguration(proxyBeanMethods = false)                    // настройки только для тестов
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection                                          // Spring сам возьмёт адрес, логин и пароль
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");   // образ — как в части 1
    }
}
```

В коротких примерах, как и раньше, нет строк `import` — они в полном
примере в конце.

* `@TestConfiguration` — `@Configuration` из статьи 1, только для
  тестов. `proxyBeanMethods = false` — служебная настройка, так пишет
  документация Boot; на смысл примера не влияет;
* `@Bean` над методом — как в `GameDayConfig`: «вот как создать объект».
  Наш бин — контейнер с Postgres;
* `@ServiceConnection` — Spring сам спросит у контейнера адрес, логин
  и пароль и подключит к нему приложение. Руками их не задать: порт
  у контейнера каждый раз новый.

Spring запускает такой контейнер раньше остальных бинов, в том числе
раньше Flyway, которому нужна база. А гасит вместе с приложением.

### Тест миграции

Чтобы сунуть в таблицу строку, Java-класс для строки не нужен (он
появится во второй части темы). **`JdbcTemplate`** — помощник Spring,
который выполняет SQL из строки. Его метод `update` — для
команд, которые меняют данные, он вернёт число затронутых строк:

* `INSERT INTO таблица (столбцы) VALUES (значения)` — добавить строку;
* `DELETE FROM таблица` — удалить строки (без `WHERE` — все).

Бин `JdbcTemplate` Boot делает сам, когда в приложении есть база и
`spring-boot-starter-jdbc`.

```java
@SpringBootTest                                   // поднять приложение целиком
@Import(TestcontainersConfiguration.class)        // и подключить его к Postgres в контейнере
class IncidentTableIT {

    @Autowired                                    // Spring положит сюда бин
    private JdbcTemplate jdbc;

    @AfterEach                                    // после каждого теста — убрать за собой
    void cleanUp() {
        jdbc.update("DELETE FROM game_day.incident");
    }

    @Test
    void acceptsOpenIncident() {
        int inserted = jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, duty_name)
                VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', 'duty-1')
                """);                             // id не передаём — его придумает DEFAULT

        assertThat(inserted).isEqualTo(1);
    }

    @Test
    void rejectsFixBeforeDetection() {
        assertThatThrownBy(() -> jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
                VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1')
                """))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("incident_fixed_after_detected");    // сработала именно эта проверка
    }
}
```

Как читать:

* **`@SpringBootTest`** — «подними для теста приложение целиком», как
  `SpringApplication.run` из статьи 2, вместе с Flyway: к первому тесту
  таблица уже на месте. Приезжает со `spring-boot-starter-test`; ею
  помечен и `GameDayApplicationTests` от Initializr;
* `@Import(TestcontainersConfiguration.class)` — добавить к приложению
  класс с контейнером. Сам собой `@TestConfiguration` в тест не попадёт:
  Spring нарочно его не подхватывает, чтобы настройки одних тестов
  не расползлись по всем;
* `@Autowired` над полем в статье 1 был ⚠️: в коде приложения
  зависимости приходят только через конструктор. Тестовый класс
  создаёт JUnit, и поле с `@Autowired` — обычный способ получить в нём
  бин;
* `@AfterEach` — метод, который JUnit выполняет после каждого теста.
  База одна на весь прогон и живёт между тестовыми классами: что
  вставил — то и удали. Иначе упадёт чужой тест, который рассчитывал
  на пустую таблицу;
* SQL записан текстовым блоком `"""` из статьи 0, время — строкой
  с `Z`: Postgres сам поймёт её как момент в UTC;
* нарушенную проверку Postgres возвращает ошибкой, а Spring превращает
  её в непроверяемое исключение `DataIntegrityViolationException`
  (`org.springframework.dao`) — «нарушена целостность данных».
  `hasMessageContaining` убеждается, что сработала **наша** проверка,
  а не, скажем, `NOT NULL` из-за опечатки в тесте. Вот зачем проверкам
  имена.

Здесь — приём, а не полный набор: в рабочем проекте случаи для теста
миграции перечисляет таблица в тексте задачи — каждую строку.

**Почему база одна на прогон.** Поднятое для теста приложение Spring
держит в **кэше** и отдаёт следующему тестовому классу с той же
конфигурацией — те же аннотации, тот же `@Import`. Приложение одно —
и контейнер один.

⚠️ Частая ошибка — общий базовый класс тестов с аннотацией
`@Testcontainers` и полем `static` с аннотацией `@Container`. Это
**расширение JUnit** — дополнение, которое JUnit зовёт до и после
тестов: оно поднимает контейнер перед тестовым классом и гасит после
него. А Spring отдаёт приложение из кэша следующему классу,
с подключением к погашенному контейнеру. Тесты висят и падают
с `Connection refused`, хотя поодиночке каждый класс зелёный.

В одном рабочем проекте так жил базовый класс с тринадцатью
наследниками. После починки два тестовых класса подряд шли
не 5 минут 34 секунды, а 29 секунд. Документация Boot советует
контейнер-бин, как здесь.

### Тесты *IT и Surefire

Тест, который проверяет код вместе с настоящей базой, называется
**интеграционным**; в рабочем проекте его класс оканчивается на `IT`
(integration test). `*Test` идут без базы — за миллисекунды, иногда
с кусочком Spring, как тест на раннере из статьи 2. `*IT` идут
с настоящим Postgres, за секунды. Граница — база, а не Spring.

Помнишь из статьи 0: Maven находит тесты по окончанию имени. Ищет их
**Surefire** — плагин Maven, который на фазе `test` зовёт JUnit; он
приезжает с `<parent>`. `*IT` по умолчанию он не берёт: тест молча
не запустится, а сборка будет зелёной. Поэтому шаблоны поиска задают
в `pom.xml` заново, в `<build><plugins>`:

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-surefire-plugin</artifactId>
    <configuration>
        <includes>
            <include>**/*Test.java</include>
            <include>**/*Tests.java</include>       <!-- иначе пропадёт тест от Initializr -->
            <include>**/*IT.java</include>
        </includes>
    </configuration>
</plugin>
```

Свой список **заменяет** умолчания, а не дополняет. Перечисли только
`*Test` и `*IT` — и `GameDayApplicationTests` молча пропадёт: он
кончается на `Tests`. Поэтому шаблонов три.

### Тест от Initializr теперь требует базу

`GameDayApplicationTests` поднимает приложение, а в нём теперь есть база.
Без её адреса Spring Boot остановится с ошибкой `Failed to configure
a DataSource` — «не могу настроить подключение к базе». Поэтому —
одна строка, как в тесте миграции:

```java
@SpringBootTest
@Import(TestcontainersConfiguration.class)                      // без базы приложение больше не поднимется
class GameDayApplicationTests {

    @Test
    void contextLoads() {
    }
}
```

Ту же ошибку даст `GameDayApplication`, если запустить его без
переменных `SPRING_DATASOURCE_*` из части 2.

Запусти `./mvnw verify`. Flyway применит `V1__game_day_incident.sql`
к настоящему Postgres, и оба теста миграции позеленеют. Таблица есть.
Но Java о ней пока ничего не знает — кроме строки SQL в тесте.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему устройство базы не меняют руками, даже если нужен «всего
   один столбец»? Что делает Flyway вместо этого и как он помнит, что
   уже применено?
2. Миграция V5 уже прошла на стенде, а ты нашёл в ней ошибку. Что будет,
   если поправить файл? Как сделать правильно?
3. Прочитай по строкам `title VARCHAR(200) NOT NULL CHECK (btrim(title) <> '')`.
   Какие три заголовка база не примет?
4. Чем `TIMESTAMPTZ` отличается от `TIMESTAMP`? Почему в Java ему
   соответствует `Instant`?
5. Зачем приложению своя схема и своя роль базы с минимальными
   правами? Почему имя схемы пишут явно и почему у `duty_name` нет
   внешнего ключа?
6. Ты назвал файл `V7_game_day_incident.sql`. Что будет и как ты об этом
   узнаешь?
7. Почему тест миграции идёт на настоящем Postgres в контейнере,
   а не на базе в памяти? Что будет, если Docker не запущен?
8. Зачем `IncidentTableIT` метод с `@AfterEach` и зачем проверке
   в таблице имя? Почему в шаблонах Surefire три строки, а не две?

---

## Что дальше

Во второй части темы «Данные» таблица станет классом Java. Журнал
научится сохранять и находить происшествия, а несколько изменений
сразу — проходить по принципу «всё или ничего».

## Первоисточники

* [Flyway: Versioned migrations](https://documentation.red-gate.com/fd/versioned-migrations-273973333.html) —
  имена файлов, порядок, контрольные суммы и почему применённое
  не правят;
* [Flyway: Validate](https://documentation.red-gate.com/fd/validate-277578898.html) —
  что именно сверяет Flyway перед запуском миграций;
* [Spring Boot how-to: Flyway](https://docs.spring.io/spring-boot/how-to/data-initialization.html#howto.data-initialization.migration-tool.flyway) —
  где Boot ищет миграции и какие зависимости нужны;
* [Testcontainers: Postgres Module](https://java.testcontainers.org/modules/databases/postgres/) —
  модуль Postgres и почему драйвер добавляют отдельно;
* [Spring Boot: Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html) —
  контейнер-бин, `@ServiceConnection` и предупреждение про контейнеры,
  которые гаснут раньше, чем Spring выбросит приложение из кэша.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 2: журнал
в `example.gameday.journal`, `GameDayApplication`, `GameDayProperties`,
`application-stand.yml`, `IncidentLogTest` и `GameDayPropertiesTest` —
без изменений. Что добавить: зависимости и Surefire в `pom.xml`,
миграцию, строки Flyway в `application.yml`, класс с контейнером и тест
миграции; в `GameDayApplicationTests` — строку `@Import`. Нужен
запущенный Docker; первый прогон скачает образ `postgres:17-alpine`.

```xml
<!-- pom.xml: в <dependencies> и в <build><plugins>, рядом с тем, что уже есть -->
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
-- Журнал игрового дня: происшествия, которые заметили дежурные.
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

/** Настоящий Postgres в Docker — один на все тесты, которые его подключают. */
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
// src/test/java/example/gameday/GameDayApplicationTests.java — от Initializr, плюс одна строка
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
                VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', 'duty-1')
                """);

        assertThat(inserted).isEqualTo(1);
    }

    @Test
    void rejectsFixBeforeDetection() {
        assertThatThrownBy(() -> jdbc.update("""
                INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
                VALUES ('стенд не отвечает', '2026-10-05T09:15:00Z', '2026-10-05T09:14:00Z', 'duty-1')
                """))
                .isInstanceOf(DataIntegrityViolationException.class)
                .hasMessageContaining("incident_fixed_after_detected");
    }
}
```
