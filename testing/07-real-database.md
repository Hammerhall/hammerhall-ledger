# Тест с настоящей базой

> «От красного к зелёному» · статья 7 · читать минут 30
>
> **Для кого.** Ты прочитал статьи 1–6 этой серии: пишешь модульные
> тесты, выбираешь случаи и подменяешь соседей заглушками. SQL хватит
> на уровне `SELECT`. Серия «От Java к Spring Boot» не нужна.
>
> **Что будет.** Что ловит только настоящая база и чего не заметит
> заглушка; как поднять Postgres для теста — Docker, Testcontainers,
> Flyway и Spring; как тестам делить одну базу и не ронять друг друга.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От красного к зелёному» — как
> работать с тестами на проекте: писать их, читать красную сборку
> и верить зелёному тесту, только если видел его красным. Примеры —
> учебные: их можно повторить у себя.

---

## Зачем настоящая база

В [статье 6 «Когда вокруг твоего кода другой код»](https://hammerhall.io/ledger/testing/6-stubs)
служба `ScoreService` считала балл и записывала его на доску зачётов,
в интерфейс `ScoreBoard`. В тесте вместо неё стояла заглушка
`RememberingBoard`: она складывала каждую запись в список, а мы
проверяли список. Тест честный: он проверяет службу, и служба верна.

Но настоящие зачёты хранят не в списке, а в базе. У базы свои правила:
зачёт по задаче один, а баллов всего три — 0, 50 и 100. Заглушка этих
правил не знает. 70 баллов или второй зачёт за ту же задачу она примет
и запомнит. Что скажет база, знает только база.

Вспомни пирамиду из статьи 1: внизу сотни модульных тестов, этажом выше —
десятки интеграционных, где код проверяют вместе с настоящей базой.
Ошибку в SQL модульный тест не заметит: базы в нём нет. Эта статья —
про второй этаж. И про обещание статьи 1 «тест прибирает за собой»:
здесь станет видно, почему без этого никак.

**Сквозной пример** — тот же зачёт по сроку. Появятся таблица `score`,
класс `JdbcScoreBoard` и его тест `JdbcScoreBoardIT`. Тест идёт
на настоящем **PostgreSQL** (коротко Postgres). Это сервер баз данных:
он хранит таблицы и выполняет запросы на SQL. Ставить его себе
не нужно: Postgres для теста поднимет Docker, о нём часть 2.

---

## Часть 1. Что видит только база

### Таблица зачётов

Таблицу описывают на SQL командой `CREATE TABLE`. В скобках через запятую
идут столбцы, у каждого имя, тип и правила.

```sql
-- src/main/resources/db/migration/V1__score.sql
CREATE TABLE score (
    student_id TEXT NOT NULL,
    task_key   TEXT NOT NULL,
    score      INT  NOT NULL CHECK (score IN (0, 50, 100)),    -- других баллов правило не знает
    PRIMARY KEY (student_id, task_key)                          -- один зачёт на задачу
);
```

По строкам:

* `TEXT` — строка любой длины;
* `INT` — целое число;
* `NOT NULL` — значение обязательно, пустым его не оставить;
* `CHECK (…)` — **ограничение-проверка**: условие, которое база
  проверяет при каждой записи. Здесь балл бывает только 0, 50 или 100,
  как в правиле зачёта;
* `PRIMARY KEY` — **первичный ключ**: по нему строку находят однозначно.
  Ключ здесь из двух столбцов, поэтому не может повториться **пара**
  «студент — задача». Второй зачёт за ту же задачу база не пустит.

Куда кладут этот файл и почему он так назван, расскажет часть 2.
В песочнице всё упрощено: таблица лежит в **схеме** по умолчанию, ключи —
просто строки. Схема — папка для таблиц внутри базы. В рабочем проекте
у приложения своя схема, и её имя пишут явно. Почему — в
[статье 3а «Данные, часть 1: таблица и миграция»](https://hammerhall.io/ledger/articles/3a-table-and-migration)
цикла «От Java к Spring Boot».

### JdbcScoreBoard: зачёты в базе

```java
// src/main/java/example/testy/score/JdbcScoreBoard.java
/** Доска зачётов в базе: настоящая реализация того, что в тестах статьи 6 подменяли. */
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
                .findFirst();                                   // строки нет — пусто
    }
}
```

В коротких примерах нет строк `import`, полные файлы — в конце статьи.

`@Repository` — пометка для Spring: «сделай из этого класса бин». Бин
(статья 6) Spring создаёт сам и отдаёт тем, кому он нужен.

**`JdbcTemplate`** — помощник Spring, который выполняет SQL, переданный
строкой. Он сам берёт соединение с базой, отправляет запрос и разбирает
ответ. В курсах на каждый запрос пишут десяток строк: открыть
соединение, выполнить, разобрать, не забыть закрыть. Здесь это одна
строка.

Приносит его **стартер** `spring-boot-starter-jdbc`. Стартер — набор
библиотек одной зависимостью, как `spring-boot-starter-test` из статьи 1.
Наш класс получает `JdbcTemplate` через конструктор.

* `update` — для команд, которые меняют данные. `INSERT INTO … VALUES …`
  добавляет строку.
* `queryForList(…, Integer.class, …)` выполняет `SELECT` и возвращает
  список значений единственного столбца, числами `Integer`.
  `.stream().findFirst()` берёт первый элемент. Нет его — пустой
  `Optional` из статьи 6.
* `?` — место для значения. Сами значения идут после SQL, по порядку,
  и `JdbcTemplate` подставит их правильно.

🔴 Значения — только через `?`. Никогда не склеивай их со строкой SQL.
Значение, пришедшее снаружи, может нести кусок SQL, и база выполнит его
как команду. Так ломают сайты, и называется это **SQL-инъекция**.

Метода `scoreOf` в интерфейсе `ScoreBoard` нет: службе читать зачёты
незачем, а тесту нужно.

### Что поймает только база

* **Ограничения.** 70 баллов и второй зачёт заглушка запишет, а база
  откажет: их запрещают `CHECK` и `PRIMARY KEY`.
* **Ошибки в SQL.** Опечатка в имени столбца или таблицы заглушке
  безразлична: SQL она не выполняет. База ответит ошибкой на первом
  же запросе.
* **Типы.** Число или текст, время с часовым поясом или без. Сходится ли
  то, что отдаёт Java, со столбцом, видно только при записи.

🔑 **Заглушка отвечает то, что ей велели. База — то, что есть на самом
деле.** Всё, что живёт в SQL и в таблице, проверяет только тест
на настоящей базе.

В старых туториалах для таких тестов берут H2, базу в памяти Java.
Мы берём тот же Postgres, что в работе: у другой базы и ошибки другие.

---

## Часть 2. Как поднять базу для теста

### Docker

**Docker** — программа, которая запускает другие программы
в **контейнерах**. Контейнер — запущенная программа, отгороженная
от остальной машины, уже установленная и настроенная. Поднимают его
из **образа**, готового снимка программы со всем, что ей нужно. Образ
похож на установочный диск, а контейнер — на программу, запущенную
с него, которую не жалко выбросить. Образ `postgres:17-alpine` — это
Postgres 17 на маленьком Linux (Alpine).

**Зачем.** В курсах Postgres ставят себе, и у каждого своя версия
и мусор от прошлых запусков. Контейнер у всех одинаковый и каждый раз
чистый.

**Откуда.** Docker ставят себе один раз. На Windows и macOS это Docker
Desktop, на Linux — Docker Engine. Перед тестами он должен быть
**запущен**. Подробно об образах и контейнерах рассказывает
[статья 6 «Стенд своими руками»](https://hammerhall.io/ledger/articles/6-stand)
цикла «От Spring к системе».

**Как проверить.** Команда `docker ps` печатает запущенные контейнеры.
Ответила без ошибки — Docker жив. Не запущен — тесты на базе упадут
в самом начале с ошибкой `Could not find a valid Docker environment`.

Слово «контейнер» здесь — только про Docker. Набор бинов Spring у нас
всегда **контекст**, как в статье 6 этой серии.

### Testcontainers

**Testcontainers** — Java-библиотека, которая из кода тестов поднимает
контейнеры Docker и убирает их после.

**Зачем.** Чтобы тест сам получил чистый Postgres нужной версии:
у тебя, у коллеги и в проверке пул-реквеста.

**Откуда.** Две зависимости с `<scope>test</scope>`, только для тестов
(статья 1). `testcontainers-postgresql` даёт класс `PostgreSQLContainer`,
контейнер с Postgres. `spring-boot-testcontainers` связывает его
со Spring Boot. Весь кусок `pom.xml` — в «Примере целиком».

**Как запускается.** Сам, той же `./mvnw verify`. Первый прогон долгий:
Docker скачивает образ. Пока идут тесты, `docker ps` покажет контейнер
`postgres:17-alpine` и рядом служебный, уборщик Testcontainers по имени
Ryuk. После прогона не останется ни того, ни другого.

⚠️ В интернете ты увидишь зависимость `org.testcontainers:postgresql`
и класс `org.testcontainers.containers.PostgreSQLContainer<?>`. Знак `<?>`
значит «какой-то параметр типа». Это Testcontainers 1.x. У нас 2.0:
модуль `testcontainers-postgresql` и класс
`org.testcontainers.postgresql.PostgreSQLContainer` без `<?>`.

### Flyway

Таблицу `score` кто-то должен создать: до первого теста, в каждой новой
базе. Руками не успеешь: контейнер живёт, только пока идут тесты.

**Flyway** — библиотека, которая применяет к базе **миграции**,
пронумерованные SQL-файлы. Каждый из них меняет устройство базы. Наша
первая и пока единственная миграция — `V1__score.sql`.

**Зачем.** Чтобы любая база, тестовая, твоя или боевая, получала одно
устройство из одних и тех же файлов. Что уже применено, Flyway помнит
в служебной таблице `flyway_schema_history`. Применяет он только новое:
по порядку номеров, каждую миграцию один раз.

**Откуда.** Стартер `spring-boot-starter-flyway` и модуль
`flyway-database-postgresql`, его стартер не приносит. Ещё нужен
**драйвер** `org.postgresql:postgresql`: библиотека, через которую Java
говорит с Postgres. `<scope>runtime</scope>` у драйвера значит, что он
нужен работающей программе, а не компиляции.

**Как запускается.** Сам, при старте приложения или теста, который его
поднимает, раньше первого обращения к базе. База теста каждый раз
новая, поэтому `V1__score.sql` выполняется в каждом прогоне.

**Имя файла** — по шаблону `V<версия>__<описание>.sql`. `V` значит
«версионная миграция», `1` — номер, потом **два** подчёркивания,
описание и `.sql`. Папка — `src/main/resources/db/migration`, там Flyway
ищет по умолчанию. С одним подчёркиванием он файл просто не увидит,
и таблицы не будет. Миграцию, которая уже прошла на общей базе,
не правят, а пишут новую. Почему — в статье 3а.

⚠️ В интернете ты увидишь, что для Flyway хватает `flyway-core`. Это
Boot 2–3. У нас Boot 4: без стартера Flyway не запускается и молчит.
Ошибка всплывёт позже, на первом запросе к таблице, которой нет.

### Spring в тесте: контекст

Чтобы проверить `JdbcScoreBoard`, его надо собрать. Ему нужен
`JdbcTemplate`, тому — подключение к базе, а до первого запроса Flyway
должен создать таблицу. Руками это десятки строк, и собрал бы ты
не так, как приложение в работе.

Это и делает Spring: сам создаёт бины и собирает их в контекст.
**Spring Boot** — Spring с готовыми настройками. Видит в проекте базу —
сам делает подключение и `JdbcTemplate`.

**В тесте** контекст поднимает пометка **`@SpringBootTest`**. Приложение
собирается целиком, как при настоящем запуске: подключение к базе,
Flyway, `JdbcTemplate` и `JdbcScoreBoard`. Пометку приносит
`spring-boot-starter-test`, он в песочнице с первого дня.

Бин попадает в тест через поле с **`@Autowired`**: «Spring, положи сюда
бин этого типа». В коде приложения зависимости приходят через
конструктор, как у `JdbcScoreBoard`. А тестовый класс создаёт JUnit,
не ты, и поле с `@Autowired` для теста — обычный способ.

### Контейнер — бином

Осталось сказать Spring, где база. Для этого контейнер с Postgres делают
бином:

```java
// src/test/java/example/testy/TestcontainersConfiguration.java
/** Настоящий Postgres в Docker — один на все тесты, которые его подключают. */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection                                          // Spring сам возьмёт адрес, логин и пароль
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

* `@TestConfiguration` — класс с настройками только для тестов.
  `proxyBeanMethods = false` — служебная настройка, так пишет
  документация Boot. На смысл примера она не влияет.
* `@Bean` над методом значит «вот как создать объект, держи его бином».
  Наш бин — контейнер с Postgres.
* `@ServiceConnection` — Spring сам спросит у контейнера адрес, логин
  и пароль и подключит к нему приложение. Руками их не задать: порт
  у контейнера каждый раз новый.

Живёт такой контейнер столько же, сколько контекст. Spring запускает его
раньше всех остальных бинов, в том числе раньше Flyway, которому нужна
база. А останавливает, когда закрывает контекст.

В тест эти настройки подключают строкой
`@Import(TestcontainersConfiguration.class)`. Сама собой
`@TestConfiguration` в тест не попадёт. Spring нарочно её не подхватывает,
чтобы настройки для одних тестов не расползлись по всем.

### Один контекст — один контейнер

Spring держит поднятые контексты в кеше и отдаёт их следующим тестам
с той же конфигурацией (статья 6). У нас `@SpringBootTest`
и `@Import(TestcontainersConfiguration.class)` стоят на двух классах:
на `JdbcScoreBoardIT` и на тесте от Initializr. Конфигурация одна,
значит, и контекст один, и контейнер с Postgres один на весь прогон.

Измени конфигурацию у одного из классов: другой `@Import`, своя
настройка, своя заглушка `@MockitoBean`. Spring поднимет для него второй
контекст, а с ним и второй контейнер.

⚠️ Частая ошибка — общий базовый класс тестов с пометкой
`@Testcontainers` и контейнером в поле `@Container static`. Это
расширение JUnit, как `MockitoExtension` в статье 6: оно поднимает
контейнер перед каждым тестовым классом и гасит после. А Spring держит
контекст в кеше дольше и отдаёт его следующему классу-наследнику,
с подключением к уже погашенному контейнеру. Каждый класс в одиночку
зелёный, а вместе они падают с `Connection refused`. Документация Boot
советует контейнер-бин, как у нас.

### Контейнер на весь прогон: как в команде

В команде база для тестов устроена иначе, но цель та же: один контейнер
на прогон. Интеграционные тесты там наследуют общий базовый класс,
а контейнер в нём — статическое поле. Его запускают один раз и после
класса не гасят: пометки `@Container` там нет, а с ней и ловушки выше.
В конце прогона контейнер уберёт Ryuk. Тест «приложение поднимается»
наследует тот же класс, по той же причине, что и наш тест ниже.

### Тест от Initializr теперь требует базу

В статье 1 мы договорились тест `TestyApplicationTests` не трогать.
Теперь придётся, одной строкой:

```java
// src/test/java/example/testy/TestyApplicationTests.java — от Initializr, плюс одна строка
@SpringBootTest
@Import(TestcontainersConfiguration.class)                      // без базы приложение больше не поднимется
class TestyApplicationTests {

    @Test
    void contextLoads() {
    }
}
```

Его тест `contextLoads` проверяет, что контекст поднимается. Теперь
в приложении есть база, а без её адреса контекст не поднимется. Spring
Boot остановится с ошибкой `Failed to configure a DataSource`, то есть
«не могу настроить подключение к базе». Поэтому `@Import` нужен и здесь.
Само `TestyApplication` без базы теперь тоже не запустить, но песочнице
это и не нужно.

⚠️ Без запущенного Docker теперь красным станет и `TestyApplicationTests`,
хотя таблиц он не трогает: ему нужен контекст, а контексту — контейнер.
`./mvnw verify` целиком без Docker больше не пройдёт, даже если ты правил
одну строку в `DeadlineScore`. Видишь
`Could not find a valid Docker environment` — запусти Docker, код тут
ни при чём.

---

## Часть 3. Тест на настоящей базе

### Четыре теста

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
        jdbc.update("DELETE FROM score");                       // уборка ДО теста: чужое не мешает
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

* `recordedScoreCanBeReadBack` — записали 50, прочитали 50. Самый
  простой тест, и уже то, чего заглушка не проверит: `INSERT` и `SELECT`
  написаны без ошибок и смотрят в одни столбцы.
* `unknownTaskHasNoScore` — строки нет: пусто, а не ошибка и не ноль.
* `secondScoreForSameTaskIsRejected` — второй зачёт за ту же задачу.
  `assertThatThrownBy` из статьи 4 значит «утверждаю, что этот код бросит
  исключение такого типа».
* `scoreOutsideRuleIsRejectedByDatabase` — 70 баллов.
* `@BeforeEach` из статьи 6: перед каждым тестом `DELETE FROM score`
  без условия удаляет из таблицы все строки. Зачем, тоже ниже.

### Что отвечает база и как это слышит Java

Нарушенное правило Postgres возвращает ошибкой. В наших двух случаях
она выглядит так:

```
ERROR:  duplicate key value violates unique constraint "score_pkey"
ERROR:  new row for relation "score" violates check constraint "score_score_check"
```

Имена `score_pkey` и `score_score_check` Postgres придумал сам, из имён
таблицы, столбца и вида ограничения. Кроме текста, у ошибки есть код,
**SQLSTATE**. У повтора ключа он `23505`, у нарушенной проверки — `23514`.
Коды на `23` значат «нарушена целостность данных».

Java получает ошибку от драйвера как `SQLException`, одно исключение
на все случаи. `JdbcTemplate` переводит его в исключения Spring по коду.
Код `23505` он превращает в `DuplicateKeyException`, прочие `23…` —
в `DataIntegrityViolationException`. Первое — наследник второго, его
частный случай. Оба лежат в пакете `org.springframework.dao`, и оба
непроверяемые: ловить их компилятор не заставляет.

💡 Четвёртый тест проверяет только тип. А `DataIntegrityViolationException`
бросит и повтор ключа. Окажись в таблице чужая строка «student-1 — T-7»,
тест позеленеет, даже если `CHECK` пропал. Захочешь строже — проверь
и текст через `hasMessageContaining` из статьи 4: в нём есть имя
`score_score_check`.

### Сначала — красный

Тест на базе может ничего не проверять, как любой другой (статья 5).
Поэтому каждый новый — сломай. Убери из `V1__score.sql` проверку
`CHECK (…)`, и должен покраснеть тест с 70 баллами. Убери строку
`PRIMARY KEY` и запятую после `CHECK (…)`, и покраснеет тест на второй
зачёт.

Теперь ошибка в SQL, которую обещала статья 6. Сделай в `JdbcScoreBoard`
опечатку в `INSERT`: `scor` вместо `score` в списке столбцов. Красными
станут три теста, которые пишут в таблицу. Зелёным останется только
`unknownTaskHasNoScore`, он лишь читает. Заглушка такой опечатки
не увидела бы вовсе.

Покраснели — верни: **зелёному тесту верят, только если видели его
красным.** Править миграцию здесь можно. База тестов каждый раз новая,
и ни одна другая база этот файл ещё не видела.

### Уборка: до теста или после

Таблица `score` живёт в одной базе на весь прогон. Строка, которую
записал один тест, достанется следующему. Удали метод с `@BeforeEach`,
и из `recordedScoreCanBeReadBack` и `secondScoreForSameTaskIsRejected`
один покраснеет при любом порядке.

Оба пишут зачёт «student-1 — T-7». Второй по счёту упадёт на первой же
записи, ещё до проверки, и в отчёте это `Errors` (статья 3). Какой
из двух упадёт, решит порядок, а его JUnit не обещает (статья 2). Это
и есть причина «у меня зелёное, а в сборке красное» из статьи 3: у себя
ты запускаешь один тест, а сборка — все и в своём порядке.

Мы убираем **до** теста. Такой тест начинает с пустой таблицы, кто бы
ни шёл перед ним и что бы ни оставил. Это может быть сосед, забывший
убрать за собой, тест, упавший на середине, или уборка, которая сама
сломалась. Уборка **после** защищает тебя, только если так делают все
остальные, и без ошибок.

Но уборка до бережёт твой тест, а не чужие. Твои строки останутся после
тебя и достанутся следующему. В песочнице таблицу `score` трогает только
`JdbcScoreBoardIT`, и уборки до хватает. Где десятки классов пишут
в общие таблицы, нужно и то и другое.

🔑 **Уборка перед собой защищает твой тест от чужого мусора. От твоего
мусора чужие тесты защищает только уборка после.**

Ещё одно правило базы. Строка одной таблицы может **ссылаться** на строку
другой, такая ссылка называется **внешний ключ**. Пока ссылка есть,
строку, на которую ссылаются, база удалить не даст.

### Уборка за всех

В команде убирают после каждого теста, но сразу за всех, и этого
хватает. Уборка живёт в общем базовом классе, и забыть её нельзя. Чистит
она не «свои» таблицы, а все таблицы своей схемы, кроме истории миграций.
Команда для этого — `TRUNCATE … CASCADE`: очистить таблицу целиком вместе
со строками, которые на неё ссылаются.

### Строки, которые роняли чужие тесты

В одном рабочем проекте контейнер тоже один на прогон, и там записали
два урока об уборке.

Первый. Новый тест чистил «свои» таблицы, а соседний класс оставил
строку в таблице, которую новый «почти не трогал». Тест падал
на собственной вставке с ошибкой «такой ключ уже есть». А в одиночку был
зелёным.

Падение зависело от того, что запускали до него, и выглядело
случайностью, как мигающий тест из статьи 3. Вывод: чистить всё, что тест
трогает.

Второй громче. Тест чистил базу только перед собой. Его строки
пережили его и ссылались на общую таблицу. Её строки стало нельзя
удалить.

Дальше падал каждый тест, который эту таблицу чистил: **341 ошибка,
и ни одна не про виновника.** Виноватым выглядел последний упавший,
а след вёл из первой ошибки. Теперь тот тест убирает и перед собой,
и после.

---

## Часть 4. Интеграционные тесты в сборке

### Имена и шаблоны Surefire

Тест на базе назван `JdbcScoreBoardIT`, где `IT` — integration test.
Surefire, который запускает тесты на шаге `test` (статья 1), такие имена
по умолчанию не берёт. Поэтому шаблоны в `pom.xml` заданы заново:

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

Свой список **заменяет** умолчания, а не дополняет (статья 1). Перечисли
только `*Test` и `*IT`, и `TestyApplicationTests` молча пропадёт: он
кончается на `Tests`. Поэтому шаблонов три, о том и комментарий
у среднего.

Проверка та же, что в статье 1: после `./mvnw verify` тестов в отчёте
стало больше ровно на четыре. Иначе какой-то класс сборка не видит.

В рабочем проекте шаблонов два, `*Test` и `*IT`, а у тестов на базе
один контейнер на весь прогон.

### Сколько это стоит

Сам тест на базе идёт быстро. Дорого всё, что перед ним: поднять
контейнер и контекст, применить миграции, а в первый раз и скачать образ.
Платится это раз за прогон, пока конфигурация у тестов одна.

Пирамида из статьи 1 не меняется. Правило зачёта стерегут модульные
тесты `DeadlineScore`, а тест на базе — только то, что живёт в SQL
и в таблице. Тесты посложнее, для хранилища и транзакции, разбирает
[статья 3б «Данные, часть 2: сущность, хранилище, транзакция»](https://hammerhall.io/ledger/articles/3b-entity-and-transaction)
цикла «От Java к Spring Boot».

### Контексты, которые съели базу

В одном рабочем проекте однажды стали падать тесты, которых никто
не трогал. В одиночку зелёные, вместе — красные
с `Failed to load ApplicationContext`. Причина нашлась в последней
`Caused by:` (статья 3): база отказала в подключении, «слишком много
клиентов».

Контексты в кеше живут до конца прогона, и у каждой конфигурации свой.
Каждый держал свои соединения с базой, и база упёрлась в свой потолок.
А контекст, который однажды не поднялся, Spring второй раз не поднимает:
одна причина дала много красных.

Вывод там записали такой: тесты на базе пишут с одной конфигурацией.
Каждая своя настройка или заглушка добавляет контекст и соединения, а при
контейнере-бине — ещё и контейнер.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Тест службы с заглушкой из статьи 6 зелёный. Почему он не скажет,
   что база не примет 70 баллов, и какой тест это скажет?
2. Что такое контейнер Docker и образ? Что будет с тестами на базе
   и с `TestyApplicationTests`, если Docker не запущен?
3. Кто и когда создаёт таблицу `score` в базе теста? Что будет, если
   назвать файл `V1_score.sql`?
4. Почему `JdbcScoreBoardIT` и `TestyApplicationTests` получают один
   и тот же Postgres? Что изменится, если в одном из них появится
   `@MockitoBean`?
5. Почему контейнер в поле `@Container static` и кеш контекстов Spring
   вместе дают `Connection refused`?
6. Какие тесты покраснеют от опечатки в `INSERT`, а какой останется
   зелёным? Почему заглушка этой опечатки не заметила бы?
7. Что защищает уборка перед тестом и что — уборка после? Почему
   в песочнице хватает одной, а где многие классы пишут в общие
   таблицы, нужны обе?
8. В шаблонах Surefire — `*Test`, `*Tests` и `*IT`. Что пропадёт, если
   убрать средний, и как это заметить?

---

## Что дальше

Это последняя статья серии «От красного к зелёному»: дальше читай тесты
своего проекта и документацию из «Первоисточников» её семи статей.

## Первоисточники

* [Spring Boot — Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html) —
  контейнеры бинами, `@ServiceConnection` и почему не `@Container static`.
* [Spring Framework — Context Caching](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html) —
  что входит в «ту же конфигурацию» и когда контекст поднимается заново.
* [Spring Framework — DAO Support](https://docs.spring.io/spring/reference/data-access/dao.html) —
  как ошибки базы становятся исключениями Spring.
* [Flyway — Versioned migrations](https://documentation.red-gate.com/fd/versioned-migrations-273973333.html) —
  имена файлов, порядок и почему применённое не правят.
* [Testcontainers — General Container runtime requirements](https://java.testcontainers.org/supported_docker_environment/) —
  какой Docker нужен на Windows, macOS и Linux.

---

## Пример целиком — с импортами

Учебный пример живёт в песочнице `testy` из статьи 1. К этой статье
в ней всё из статей 1–6: зачёт по сроку и его тесты, служба
`ScoreService` с интерфейсом `ScoreBoard`, плагин JaCoCo в `pom.xml`.
**Без запущенного Docker пример не пойдёт**: на Windows и macOS нужен
Docker Desktop, на Linux — Docker Engine. Проверь командой `docker ps`.
Первый прогон скачает образ `postgres:17-alpine`, подожди.

В `pom.xml` добавь зависимости и настройку Surefire. Строки `<!-- … -->`
значат: то, что там уже было, оставь.

```xml
<!-- pom.xml песочницы testy: что добавляет статья 7 -->
<dependencies>
    <!-- … что было -->
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
        <!-- … spring-boot-maven-plugin и JaCoCo из статьи 5, что было -->
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
    </plugins>
</build>
```

```sql
-- src/main/resources/db/migration/V1__score.sql
CREATE TABLE score (
    student_id TEXT NOT NULL,
    task_key   TEXT NOT NULL,
    score      INT  NOT NULL CHECK (score IN (0, 50, 100)),    -- других баллов правило не знает
    PRIMARY KEY (student_id, task_key)                          -- один зачёт на задачу
);
```

```java
// src/main/java/example/testy/score/JdbcScoreBoard.java
package example.testy.score;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/** Доска зачётов в базе: настоящая реализация того, что в тестах статьи 6 подменяли. */
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
                .findFirst();                                   // строки нет — пусто
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

/** Настоящий Postgres в Docker — один на все тесты, которые его подключают. */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection                                          // Spring сам возьмёт адрес, логин и пароль
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

```java
// src/test/java/example/testy/TestyApplicationTests.java — от Initializr, плюс одна строка
package example.testy;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

@SpringBootTest
@Import(TestcontainersConfiguration.class)                      // без базы приложение больше не поднимется
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
        jdbc.update("DELETE FROM score");                       // уборка ДО теста: чужое не мешает
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

Сделай руками:

1. Запусти Docker, потом `./mvnw verify` — всё зелёное,
   `Tests run: 28`: 24 после статьи 6 и четыре новых. Пока прогон идёт,
   `docker ps` в соседнем окне покажет один контейнер `postgres:17-alpine`
   и Ryuk.
2. Убери из `V1__score.sql` `CHECK (score IN (0, 50, 100))`. Красный —
   `scoreOutsideRuleIsRejectedByDatabase`. Верни.
3. Убери строку `PRIMARY KEY (student_id, task_key)` и запятую после
   `CHECK (…)`. Красный — `secondScoreForSameTaskIsRejected`. Верни.
4. В `JdbcScoreBoard` замени в `INSERT` столбец `score` на `scor`.
   Красные `recordedScoreCanBeReadBack`, `secondScoreForSameTaskIsRejected`
   и `scoreOutsideRuleIsRejectedByDatabase`, зелёный только
   `unknownTaskHasNoScore`. Верни.
5. Удали метод `emptyTable` вместе с `@BeforeEach`. Красный один тест,
   `recordedScoreCanBeReadBack` или `secondScoreForSameTaskIsRejected`,
   и он в `Errors`. Верни.
6. Убери из шаблонов `**/*Tests.java`. Сборка зелёная, но
   `Tests run: 27`: `TestyApplicationTests` пропал из отчёта. Верни.
7. Останови Docker и снова запусти `./mvnw verify`. Красные пять тестов,
   которым нужен контекст: четыре `JdbcScoreBoardIT` и
   `TestyApplicationTests`. В журнале —
   `Could not find a valid Docker environment`. Остальные тесты зелёные.
   Запусти Docker.

Теперь ты знаешь про эти тесты главное: каждый из них умеет покраснеть,
и краснеет ровно тогда, когда база перестаёт стеречь своё правило. Такому
зелёному можно верить.
