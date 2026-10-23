# Данные, часть 2: сущность, хранилище, транзакция

> «От Java к Spring Boot» · статья 3б · читать минут 30
>
> **Для кого.** Ты прочитал статьи 0–2 и первую часть темы «Данные» —
> статью 3а. В песочнице `game-day` есть таблица `game_day.incident`,
> её миграция и тест `IncidentTableIT` на Postgres в контейнере. Docker
> у тебя стоит.
>
> **Что будет.** Три вещи: как Java-объект становится строкой таблицы
> и обратно — сущность и хранилище; как сделать несколько изменений
> по принципу «всё или ничего» — транзакция; как проверить и то и другое
> тестом на настоящей базе.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Java к Spring Boot» — то, что
> нужно новичку до первой задачи на Spring Boot 4. Примеры — учебные:
> их можно повторить у себя.

---

## Зачем сущность и хранилище

В статье 3а ты писал SQL строкой через `JdbcTemplate`. Для теста
миграции сойдёт. А журналу так пришлось бы каждый запрос собирать
строкой. Каждую строку ответа пришлось бы раскладывать по полям объекта
руками, а при записи — наоборот. Для каждой таблицы и каждого запроса —
десятки однообразных строк, и в каждой можно перепутать столбцы.

В этой статье журнал игрового дня наконец начнёт хранить происшествия.
Таблица станет классом `Incident`, у журнала появится хранилище, а
закрытие нескольких происшествий разом пойдёт одной транзакцией.
Перезапуск приложения журнал больше не обнулит — с этой беды тема
«Данные» и начиналась.

Журнал игрового дня — учебный пример. Но сущности и хранилища в рабочем
проекте пишут и джуны, так что всё, что в нём есть, ещё встретится
в задачах.

---

## Часть 1. Сущность

### ORM — переводчик между строками и объектами

**ORM** (object-relational mapping, «отображение объектов на таблицы»)
делает перевод между строками и объектами за тебя. Как переводчик: база
говорит строками и столбцами, Java — объектами и полями. Один раз описал,
какой класс ложится на какую таблицу, — дальше ORM переводит сам.

### JPA и Hibernate — кто есть кто

**JPA** (Jakarta Persistence) — стандарт: аннотации и правила, как
описать класс для ORM. Сам он ничего не делает. Почему «JPA»: раньше
стандарт звался Java Persistence API, потом его переименовали, а
сокращение осталось.

**Hibernate** — библиотека, которая этот стандарт выполняет: создаёт
объекты из строк, пишет SQL, следит за изменениями. JPA для Hibernate —
как интерфейс `Notifier` из статьи 1 для `ConsoleNotifier`: код пишется
по стандарту, работу делает реализация. Не путай с Hibernate Validator
из статьи 2: авторы те же, библиотека другая.

Над ними — **Spring Data JPA**: он избавляет даже от кода хранилищ
(часть 2). Всё вместе приносит стартер `spring-boot-starter-data-jpa`.
В `pom.xml` песочницы он встаёт на место `spring-boot-starter-jdbc`
из статьи 3а.

```xml
<dependency>                                <!-- вместо spring-boot-starter-jdbc -->
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
```

Почему вместо, а не рядом: стартер JPA сам приносит стартер JDBC —
подключение к базе и `JdbcTemplate`. Объявлять его второй раз незачем.
`IncidentTableIT` из статьи 3а со своим `JdbcTemplate` работает как
прежде. Flyway, драйвер Postgres и Testcontainers остаются на месте,
версию подставляет `<parent>`.

Запускать Hibernate не нужно: Boot поднимает его сам при старте
приложения. Что пошло не так, видно в логе запуска.

⚠️ В интернете ты увидишь аннотации из `javax.persistence`. Это Boot 2
и более ранние. В Boot 4 — `jakarta.persistence`; `javax.*` Spring
Framework 7 не поддерживает вовсе.

⚠️ Частая ошибка — настройка `ddl-auto: update` из туториалов: Hibernate
сам создаёт и меняет таблицы по классам. Тогда таблицы меняли бы двое,
Flyway по миграциям и Hibernate по классам. И базы снова разъехались
бы, как в начале статьи 3а. В рабочем проекте — `validate`: таблицы
создаёт только Flyway, а Hibernate при старте лишь сверяет с ними
классы. Не сошлись — приложение не стартует.

В песочнице так же. Допиши в `application.yml` под тот же `spring:`,
где уже стоит `flyway:`:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate     # таблицы — только миграции; Hibernate их сверяет
```

### Сущность Incident

**Сущность** (entity) — класс, объекты которого JPA хранит строками
таблицы: один объект — одна строка. Классы журнала живут там же, где
и были, в пакете `example.gameday.journal`, рядом с `IncidentLog`.
Сущности и хранилища Spring ищет только внутри пакета приложения —
`example.gameday` и ниже.

Как и в прошлых статьях, в коротких примерах нет строк `import`,
а `…` — пропущенный кусок. Полные файлы — в конце статьи.

```java
@Entity                                                // «это сущность»
@Table(name = "incident", schema = "game_day")         // её таблица; схема — явно
public class Incident {

    @Id                                                // первичный ключ
    // ключ создаст Hibernate при сохранении: для UUID — случайный UUID
    @GeneratedValue
    private UUID id;

    @Column(name = "title", nullable = false)          // пометка «в таблице NOT NULL»; проверяет сама база
    private String title;

    @Column(name = "detected_at", nullable = false)    // имя столбца — явно, как в таблице
    private Instant detectedAt;

    @Column(name = "fixed_at")                         // может быть пустым
    private Instant fixedAt;

    @Column(name = "duty_name", nullable = false)
    private String dutyName;

    protected Incident() {                             // для JPA
    }

    public Incident(String title, Instant detectedAt, String dutyName) {
        // проверки — как в компактном конструкторе из статьи 0; целиком — в конце
        this.title = title;
        this.detectedAt = detectedAt;
        this.dutyName = dutyName;
    }

    public void fix(Instant now) {                     // «починили»
        if (fixedAt != null) {
            throw new IllegalStateException("происшествие «" + title + "» уже закрыто");
        }
        if (now.isBefore(detectedAt)) {
            throw new IllegalArgumentException("починили раньше, чем заметили: " + now);
        }
        fixedAt = now;
    }

    public UUID getId() {
        return id;
    }
    // getTitle(), getDetectedAt(), getFixedAt(), getDutyName() — так же
}
```

Столбцу `UUID` в Java соответствует класс `UUID` из `java.util`,
а `TIMESTAMPTZ` — `Instant`, как договорились в статье 3а.
`IllegalStateException` — родственник `IllegalArgumentException` из
статьи 0: «в таком состоянии так нельзя». Виноват не аргумент,
а то, что происшествие уже закрыто.

Это описание Hibernate сверяет с таблицей при каждом старте, спасибо
`validate`. Опечатайся в имени столбца, напиши `@Column(name = "fixed")`
вместо `fixed_at` — и приложение не поднимется:

```
Schema validation: missing column [fixed] in table [game_day.incident]
```

Упасть при старте лучше, чем на первом запросе посреди игрового дня.

### Правила сущности

Так сущности пишут в рабочем проекте — и в песочнице тоже.

**Поля `private`, геттеры — явно.** JPA читает и пишет поля напрямую,
мимо методов; геттеры нужны твоему коду. В рабочем проекте их пишут
руками, без Lombok — библиотеки, которая генерирует такой код сама.
⚠️ Имена — `getTitle()`, а не `title()`, как у записей из статьи 0.

**Сеттеров нет.** Будь вместо `fix` метод `setFixedAt(Instant)`,
любое место кода могло бы закрыть происшествие дважды, «раньше, чем
заметили», или тихо открыть заново (`setFixedAt(null)`). И правило
пришлось бы проверять в каждом. С `fix` правило живёт в одном месте.
А имя говорит, что произошло, а не какое поле поменяли.

**Конструктор без аргументов — `protected`.** Читая строку, JPA сначала
создаёт пустой объект, потом раскладывает по полям значения столбцов.
Для этого и нужен конструктор без аргументов. Hibernate требует только,
чтобы он был не `private`. `protected` — «доступен наследникам
и классам того же пакета»: снаружи пакета пустое происшествие
не создать. А внутри действует договорённость: этот конструктор
только для JPA. Новые происшествия создаются публичным конструктором.

**Не запись и не `final`.** `final` у класса значит «наследовать
нельзя». Hibernate иногда подставляет вместо сущности созданного им
наследника — например, когда отдаёт ссылку на объект, который ещё
не прочитал из базы. Поэтому сущность `final` быть не может. А запись
`final` всегда, да ещё и неизменяема, — JPA же нужно создать объект
пустым и заполнить потом. Поэтому сущность — обычный класс.

**Время — снаружи.** `fix` получает `now` параметром, а время берёт
вызывающий из часов `Clock`: `incident.fix(clock.instant())`.
`Instant.now()` внутри сущности не пиши: тест не сможет проверить,
какое время записано. Это правило команды из статьи 1: «сейчас» берут
только из `Clock`.

💡 Ключ задан дважды, через `@GeneratedValue` и `DEFAULT` в таблице.
И это не лишнее. Через JPA ключ создаёт Hibernate ещё в Java, а `DEFAULT`
сработает, когда строку вставят простым SQL, как в `IncidentTableIT`.

---

## Часть 2. Хранилище

### IncidentRepository

**Хранилище** (repository) — интерфейс, через который код находит
и сохраняет сущности. Реализацию писать не нужно:

```java
public interface IncidentRepository extends JpaRepository<Incident, UUID> {
}
```

В угловых скобках — параметры типа, как в `List<String>` из статьи 1:
хранилище сущностей `Incident` с ключом `UUID`.

Реализацию при старте напишет Spring Data и сделает её бином — получай
её через конструктор, как любую зависимость. Готовые методы уже есть:
`save`, `findById`, `findAll`, `count`, `deleteAll` и другие. `save`
сохраняет и возвращает сохранённую сущность, уже с ключом.

`findById` возвращает `Optional<Incident>` — коробку, в которой объект
либо есть, либо нет. Метод честно говорит: «могу и не найти».
`orElseThrow` значит «достань, а если пусто — брось вот это исключение»:

```java
Incident incident = incidents.findById(id)
        .orElseThrow(() -> new IllegalArgumentException("нет происшествия " + id));
```

### Методы по имени

Свой запрос часто писать не нужно: достаточно назвать метод по правилам
Spring Data.

```java
List<Incident> findByDutyName(String dutyName);    // … where i.dutyName = ?1
List<Incident> findByFixedAtIsNull();              // … where i.fixedAt is null — ещё открытые
```

Spring Data разбирает имя по словам: `findBy` — «найти по», дальше
поле сущности и, если надо, условие (`IsNull`). В имени — поля Java
(`dutyName`), а не столбцы (`duty_name`). Опечатаешься — Spring Data
не поймёт метод, и приложение не стартует.

Например, `findByDuty_name` — по столбцу, а не по полю. Знак `_` для
Spring Data — шаг внутрь вложенного объекта: он ищет у `Incident` поле
`duty`, чтобы взять у него `name`. Такого поля нет:

```
No property 'duty' found for type 'Incident'
```

### @Query — когда имени мало

Условий много — и имя становится нечитаемым. Тогда запрос пишут сами:

```java
@Query("select i from Incident i where i.dutyName = ?1 and i.fixedAt is null order by i.detectedAt")
List<Incident> findOpenOf(String dutyName);         // открытые у дежурного, старые первыми
```

Это **JPQL** — язык запросов JPA. Он похож на SQL, но говорит
о сущностях и полях: `Incident` и `dutyName`, а не `game_day.incident`
и `duty_name`. Перепутать легко: таблица и столбцы — в миграции, класс
и поля — в `@Query`. `?1` — первый параметр метода.

---

## Часть 3. Журнал хранит, транзакция закрывает

### IncidentLog — служба

```java
@Service                                               // было @Component
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;
    private final IncidentRepository incidents;       // четвёртая зависимость — хранилище

    // конструктор с четырьмя параметрами — как в статье 1, плюс incidents

    public void add(String title) {
        Incident incident = incidents.save(new Incident(title, clock.instant(), roster.currentDuty()));
        notifier.send(incident.getDutyName(), title + " — замечено " + incident.getDetectedAt());
    }
    …
}
```

`@Service` из статьи 1 — тот же `@Component`. В рабочем проекте
так помечают классы с логикой, данными и транзакциями и зовут их
**службами**. Журнал теперь как раз такой.

`add` сначала сохраняет, потом оповещает: оповещение о происшествии,
которого нет в журнале, хуже, чем никакого.

### Новый журнал — на место старого

Новый `IncidentLog` ложится в тот же файл, что и старый,
`src/main/java/example/gameday/journal/IncidentLog.java`, — заменяет
его, а не встаёт рядом. А тест журнала из статьи 1 придётся отпустить.

⚠️ **Старый журнал рядом не оставляй.** Положишь новый в другой пакет,
а старый сохранишь «на всякий случай». Тогда у приложения окажутся два
бина с одним именем `incidentLog`: имя бина Spring берёт из имени класса.
Приложение не поднимется с `ConflictingBeanDefinitionException`:

```
Annotation-specified bean name 'incidentLog' … conflicts with existing, non-compatible bean definition …
```

**`IncidentLogTest` из статьи 1 удали.** Он создаёт журнал через `new`
с тремя аргументами, а конструктор теперь просит четыре. Компилятор
ответит `cannot be applied to given types`, и не соберутся все тесты
песочницы. Переписать его не выйдет. Четвёртым аргументом нужно
хранилище, а рукописную заглушку для него, как `RememberingNotifier`
для `Notifier`, не написать: в `JpaRepository` десятки методов.
Заглушки для таких интерфейсов делает библиотека Mockito, она дальше
в серии.

Поэтому удали тест вместе с его заглушкой `RememberingNotifier`.
Журнал целиком, с хранилищем и базой, проверит `IncidentLogIT`
из части 4. Честно о потере: текст оповещения теперь не проверяет
ни один тест, его видно только в логе запуска. Проверка вернётся
вместе с Mockito.

### Журнал пережил перезапуск

`GameDayApplication` из статьи 2 не менялся: он берёт журнал и зовёт
`add("Брокер не отвечает")`. Но теперь `add` пишет в базу, и каждый
запуск оставляет в таблице строку. Без базы приложение не стартовало
и раньше, и запуск — как в статье 3а: Postgres в контейнере,
три переменные `SPRING_DATASOURCE_*` и `java -jar`. Собери заново —
`./mvnw package`. Тесты на базе теперь идут и в сборке: Docker
у тебя запущен.

В логе — знакомые строки:

```
[оповещение] duty-1: Брокер не отвечает — замечено 2026-…Z
игра PT3H, атакующих 2
```

Запусти ещё раз и загляни в таблицу
(`docker exec -it game-day-db psql -U postgres`):

```sql
SELECT title, duty_name, fixed_at FROM game_day.incident;
```

```
       title        | duty_name | fixed_at
--------------------+-----------+----------
 Брокер не отвечает | duty-1    |
 Брокер не отвечает | duty-1    |
(2 rows)
```

Два запуска — две строки, `fixed_at` пуст: ещё не починили. Приложение
перезапустилось, а журнал помнит. Нужна чистая база — пересоздай
контейнер, как в статье 3а: `docker stop game-day-db` и снова
`docker run`.

### Всё или ничего

Перевод денег между счетами — два шага: списать с одного, зачислить
на другой. Сломалось после первого — деньги не должны пропасть. Либо
прошли оба шага, либо ни одного.

**Транзакция** — группа изменений в базе, которая выполняется целиком
или не выполняется вовсе. Закончилась без ошибок — **фиксация**
(commit): все изменения разом становятся видны всем. Ошибка посреди —
**откат** (rollback): база возвращается к состоянию до начала, будто
ничего не было.

В журнале это выглядит так. Атака уронила брокер на стенде, и дежурные
завели из-за этого пять происшествий. Мидл починил причину — все пять
закрывают разом:

```java
    @Transactional                                     // весь метод — одна транзакция
    public void fixAll(List<UUID> ids) {
        Instant now = clock.instant();
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("нет происшествия " + id));
            incident.fix(now);                         // уже закрыто — исключение
            incidents.save(incident);
        }
    }                                                  // вышли без исключения — фиксация
```

Дежурный передал пять ключей, и в четвёртом опечатка. С транзакцией три
сделанных закрытия откатятся. В базе всё как было, дежурный поправит
список и повторит. Без транзакции каждый `save` фиксируется сразу: три
происшествия закрыты, два открыты, и какие именно — выясняй по базе.

### @Transactional

`@Transactional` — аннотация Spring над методом бина: «выполни метод
в транзакции». Начало метода — начало транзакции, нормальный выход —
фиксация, исключение — откат.

IDE может предложить два импорта `Transactional`. Второй —
`jakarta.transaction.Transactional`: он приезжает вместе со стартером
JPA. Spring понимает оба, но в рабочем проекте ради одного стиля на весь
код пишут только Spring-овый:
`org.springframework.transaction.annotation.Transactional`.

Ставят её на методы службы, где шагов несколько, а не на хранилище
и не на сущность. Готовые методы хранилища, например `save`
и `findById`, и так идут каждый в своей маленькой транзакции.
Транзакция службы объединяет их в одну. В рабочем коде `@Transactional`
встретишь почти в каждой службе, которая меняет данные.

### ⚠️ Откат — только на непроверяемых исключениях

По умолчанию Spring откатывает транзакцию, только если вылетело
**непроверяемое** исключение (`RuntimeException` и наследники) или
`Error`. На проверяемом исключении он фиксирует всё, что метод успел
сделать.

Вот ещё одна причина, почему в рабочем проекте ошибки — непроверяемые
исключения (статья 0). Будь исключение из примера проверяемым, три
закрытия остались бы в базе. Это ровно то полусостояние, от которого
транзакция должна защищать.

### ⚠️ Вызов изнутри того же класса транзакцию не создаёт

Spring ставит перед бином **прокси** — объект-посредник с теми же
методами: он открывает транзакцию, зовёт настоящий метод, потом
фиксирует или откатывает. Вызов из другого бина идёт через посредника.
А вызов изнутри класса идёт прямо в объект, мимо посредника. Таков,
например, `this.fixAll(ids)` из другого метода `IncidentLog` без
`@Transactional`.

Аннотация на `fixAll` тогда молча не срабатывает: ни ошибки, ни
транзакции, и снова возможно полусостояние. Нужна транзакция — зови
метод снаружи, из другого бина.

### Контекст постоянства

Внутри транзакции `save` для прочитанной сущности, строго говоря,
не нужен. JPA помнит объекты, которые прочитала в этой транзакции.
Эта память называется **контекстом постоянства** (persistence context).
При фиксации JPA сама сравнит объекты с тем, что прочитала, и запишет
изменения. В `fixAll` `save` написан явно — так виднее, что происходит.

⚠️ Не путай с контекстом Spring из статей 1–2: тот держит бины, пока
работает приложение, а контекст постоянства — прочитанные сущности,
пока идёт одна транзакция.

У этой памяти есть обратная сторона. Повторное чтение того же ключа
в той же транзакции вернёт объект из памяти, а не из базы. В коде это
удобно, в тестах — ловушка. О ней — в части 4.

---

## Часть 4. Тесты на базе

### IncidentTest — правила без базы

Правила сущности базе не нужны: `fix` и проверки конструктора — обычная
Java. Их проверяет модульный тест `IncidentTest`, без Spring и без базы.
Каждая проверка конструктора — строка таблицы, как учила статья 0:

```java
    @ParameterizedTest(name = "{0}, {1}, {2} — ошибка")
    @CsvSource(delimiter = '|', nullValues = "null", textBlock = """
            null  | 2026-10-05T09:15:00Z | duty-1
            ''    | 2026-10-05T09:15:00Z | duty-1
            '   ' | 2026-10-05T09:15:00Z | duty-1
            стенд | null                 | duty-1
            стенд | 2026-10-05T09:15:00Z | null
            стенд | 2026-10-05T09:15:00Z | '   '
            """)
    void rejectsMissingParts(String title, Instant detectedAt, String dutyName) {
        assertThatThrownBy(() -> new Incident(title, detectedAt, dutyName))
                .isInstanceOf(IllegalArgumentException.class);
    }
```

`nullValues = "null"` — слово `null` в таблице станет настоящим `null`:
так `null` наконец помещается в таблицу. Строку `2026-10-05T09:15:00Z`
JUnit сам превратит в `Instant`, как текст `130` — в `int` в статье 0.

Вместе с тестами на `fix` это все ветки `Incident` — 100%, столько
рабочий проект требует от новых классов (статья 0). Строки тоже все,
кроме конструктора для JPA. Его зовёт только Hibernate, когда собирает
объект из строки таблицы, и покроют его тесты на базе. JaCoCo в песочнице
не подключён, но в рабочем проекте отчёт покажет ровно это.

### IncidentRepositoryIT — запросы на настоящей базе

Хранилище проверяют на настоящем Postgres — так же, как миграцию
в `IncidentTableIT` из статьи 3а:

```java
@SpringBootTest                                        // приложение целиком
@Import(TestcontainersConfiguration.class)             // и Postgres в контейнере
class IncidentRepositoryIT {

    // неподвижное «сейчас» для всех тестов класса
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();                         // база общая — убрать за собой
    }

    @Test
    void findsOnlyOpen() {
        Incident open = incidents.save(new Incident("стенд не отвечает", T0, "duty-1"));
        Incident fixed = new Incident("очередь растёт", T0, "duty-2");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);

        assertThat(incidents.findByFixedAtIsNull())
                .extracting(Incident::getId)           // от каждого найденного — только ключ
                .containsExactly(open.getId());
    }
    …
}
```

Аннотации и `@Import` — те же, что у `IncidentTableIT`. Поэтому Spring
отдаст тесту поднятое приложение из кэша (статья 3а), и контейнер
на прогон по-прежнему один.

`Incident::getId` — **ссылка на метод**, короткая запись лямбды
`i -> i.getId()`. `extracting` берёт от каждого найденного объекта
ключ, и дальше AssertJ сравнивает уже список ключей. Сравниваем ключи,
а не сами объекты: найденный объект не обязан быть тем же Java-объектом,
что сохранял тест.

⚠️ Время в тестах — только неподвижное, `Instant.parse(…)`.
`TIMESTAMPTZ` хранит время с точностью до микросекунды, а `Instant`
бывает точнее — у `Instant.now()` на некоторых машинах больше знаков
после запятой. Записал одно, прочитал другое — тест красный на ровном
месте.

### Контекст постоянства в тестах

Помнишь обратную сторону контекста постоянства? Контекст живёт столько
же, сколько транзакция. Если тест сам идёт в одной транзакции, то
«сохранил и прочитал» вернёт тот же объект из памяти. Тест зелёный,
а о базе не сказал ничего.

Наши тесты в транзакции не идут: `@SpringBootTest` её не открывает.
Каждый вызов хранилища в `IncidentRepositoryIT` получает свой, новый
контекст постоянства и закрывает его за собой. Поэтому чтение идёт
в базу по-настоящему и возвращает новый объект. Вот почему тест
сравнивает ключи.

Транзакцию на каждый тест открывает `@Transactional` над тестовым
классом или методом. В конце теста Spring её откатывает, и убирать
за собой не нужно. Так устроен **`@DataJpaTest`** — срез базы (статья 2):
он каждый тест заворачивает в транзакцию.

В таких тестах контекст сбрасывают руками, методами объекта JPA
`EntityManager`. `flush` — отправить изменения в базу, `clear` — забыть
объекты в памяти. Следующее чтение пойдёт в базу по-настоящему.

В песочнице `@DataJpaTest` нет: хранилище проверяет тот же
`@SpringBootTest` с контейнером, что и миграцию. В рабочем проекте
хранилища тоже проверяют так.

⚠️ В интернете ты увидишь `@DataJpaTest` из пакета
`org.springframework.boot.test.autoconfigure.orm.jpa`, прямо
в `spring-boot-starter-test`. Это Boot 2–3. В Boot 4 у него свой
тестовый стартер `spring-boot-starter-data-jpa-test` и пакет
`org.springframework.boot.data.jpa.test.autoconfigure`.

### IncidentLogIT — доказать откат

Главное обещание части 3, «три закрытия откатятся», проверяет тест
на настоящей базе. Журнал он берёт целиком, как бин, со всеми четырьмя
зависимостями.

```java
@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentLogIT {

    // в прошлом: fixAll берёт «сейчас» из настоящих часов
    private static final Instant T0 = Instant.parse("2026-09-01T09:15:00Z");

    @Autowired
    private IncidentLog log;

    @Autowired
    private IncidentRepository incidents;

    …

    @Test
    void fixAllRollsBackWhenOneIdIsUnknown() {
        List<UUID> ids = new ArrayList<>();
        for (String title : List.of("стенд не отвечает", "очередь растёт", "письма не уходят")) {
            ids.add(incidents.save(new Incident(title, T0, "duty-1")).getId());
        }
        ids.add(UUID.randomUUID());                    // такого ключа в базе нет

        assertThatThrownBy(() -> log.fixAll(ids))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("нет происшествия");   // упало именно на четвёртом ключе

        assertThat(incidents.findByFixedAtIsNull()).hasSize(3);   // все три по-прежнему открыты
    }
}
```

`hasSize(3)` — «в списке ровно три элемента».

⚠️ Откат так проверить можно, только если сам тест не открывает
транзакцию. Наш не открывает: на нём нет `@Transactional`. Поэтому
`fixAll` открывает свою, настоящую, откат доходит до базы, а проверка
после ошибки — новый запрос в базу.

Поставь `@Transactional` на класс `IncidentLogIT` — и тест покраснеет
даже с исправным `fixAll`:

```
Expected size: 3 but was: 0 in:
[]
```

`fixAll` присоединился к транзакции теста. Ошибка лишь пометила её
«в конце откатить». До конца теста закрытия живут в той же
незавершённой транзакции, и проверка, которая идёт в ней же, их видит.
Откатится всё после теста, когда проверять уже нечего. Транзакции служб
проверяют тестом без своей транзакции — как здесь.

🔑 Проверь, что тест умеет падать: убери `@Transactional` с `fixAll`
и запусти его. Он обязан покраснеть с тем же
`Expected size: 3 but was: 0` — три происшествия окажутся закрыты.
Остался зелёным — проверка смотрит не туда, и откат она не доказывает.
Тест, который не умеет сказать «нет», — не тест.

💡 Почему `T0` здесь — первое сентября, а не остановленные часы, как
в `IncidentLogTest` статьи 1? Там журнал собирали через `new` и часы
передавали руками. Здесь журнал — бин, и часы ему даёт Spring: бин
`clock` из `GameDayConfig`, настоящий. `fixAll` закроет происшествия
«сейчас». Чтобы `fix` не решил, что починили раньше, чем заметили,
их заводят в прошлом.

Второй бин часов для теста тут не поможет. Скопируешь метод `clock()`
с остановленными часами в класс настроек для тестов с `@TestConfiguration`,
как `TestcontainersConfiguration` в статье 3а. Подключишь его через
`@Import` — а бин с именем `clock` уже есть, и подменять бины Boot
не разрешает. Приложение не поднимется:
`A bean with that name has already been defined … and overriding is disabled`.

Назовёшь метод иначе — старт пройдёт, но журнал подмены не заметит.
Из двух бинов `Clock` Spring отдаст тот, чьё имя совпало с именем
параметра конструктора, то есть `clock`. Как подменять бины в тестах —
дальше в серии, вместе с Mockito.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Чем JPA отличается от Hibernate? Кто в песочнице создаёт таблицы
   и что Hibernate делает при старте?
2. Зачем сущности конструктор без аргументов и почему он `protected`?
   От кого `protected` не защищает?
3. Почему у `Incident` нет `setFixedAt`? Где живёт правило «закрыть
   можно только один раз»?
4. Метод `findByDuty_name` не даёт приложению стартовать — почему?
   Чем запрос в `@Query` отличается от SQL в миграции?
5. `fixAll` закрыл три происшествия и упал на четвёртом. Что окажется
   в базе с `@Transactional` и без неё?
6. Что будет, если исключение в `fixAll` окажется проверяемым? А если
   `fixAll` позвать из другого метода того же класса?
7. Что такое контекст постоянства? Почему из-за него тест «сохранил
   и прочитал» может ничего не проверить?
8. Как убедиться, что `IncidentLogIT` действительно доказывает откат?
   Почему он покраснеет, если пометить `@Transactional` сам тест?

---

## Что дальше

Дальше в серии — веб. Журнал научится отвечать по HTTP: возьмёт
происшествие из хранилища по ключу и вернёт его в JSON, а если такого
нет — понятную ошибку.

## Первоисточники

* [Spring Data JPA: Query Methods](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html) —
  таблица слов для методов по имени (`IsNull`, `OrderBy` и другие)
  и `@Query`;
* [Spring Framework: Using @Transactional](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html) —
  прокси и почему вызов изнутри класса идёт мимо транзакции;
* [Spring Framework: Rolling Back a Declarative Transaction](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/rolling-back.html) —
  на каких исключениях откат, а на каких фиксация;
* [Introduction to Hibernate 7](https://github.com/hibernate/hibernate-orm/tree/7.4.1/documentation/src/main/asciidoc/introduction) —
  требования к сущности: конструктор без аргументов, не `final`,
  способы создать ключ;
* [Spring Boot: Testing Spring Boot Applications](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html) —
  как тесты поднимают приложение и какие тесты идут в транзакции.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 3а:
миграция `V1__game_day_incident.sql`, `TestcontainersConfiguration`,
`IncidentTableIT`, `GameDayApplicationTests` с `@Import`,
`GameDayApplication`, `GameDayProperties` с тестом, `application-stand.yml`
и помощники журнала из статьи 1 — `DutyRoster`, `Notifier`,
`ConsoleNotifier` и `GameDayConfig` с бином часов — без изменений.

Что поменять: в `pom.xml` `spring-boot-starter-jdbc` заменить
на `spring-boot-starter-data-jpa`; в `application.yml` дописать
`ddl-auto: validate`; `IncidentLog` заменить новым. Что добавить:
`Incident`, `IncidentRepository` и три теста — `IncidentTest`,
`IncidentRepositoryIT`, `IncidentLogIT`. Что удалить: `IncidentLogTest`
и `RememberingNotifier` из `src/test/java/example/gameday/journal`.
Нужен запущенный Docker.

```xml
<!-- pom.xml: в <dependencies> — вместо spring-boot-starter-jdbc, остальное как после статьи 3а -->
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
            throw new IllegalArgumentException("у происшествия нет заголовка");
        }
        if (detectedAt == null) {
            throw new IllegalArgumentException("не сказано, когда заметили");
        }
        if (dutyName == null || dutyName.isBlank()) {
            throw new IllegalArgumentException("не сказано, кто дежурил");
        }
        this.title = title;
        this.detectedAt = detectedAt;
        this.dutyName = dutyName;
    }

    public void fix(Instant now) {
        if (fixedAt != null) {
            throw new IllegalStateException("происшествие «" + title + "» уже закрыто");
        }
        if (now.isBefore(detectedAt)) {
            throw new IllegalArgumentException("починили раньше, чем заметили: " + now);
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
        notifier.send(incident.getDutyName(), title + " — замечено " + incident.getDetectedAt());
    }

    @Transactional
    public void fixAll(List<UUID> ids) {
        Instant now = clock.instant();
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("нет происшествия " + id));
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

    // неподвижное «сейчас» для всех тестов класса
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Test
    void newIncidentIsOpen() {
        Incident incident = new Incident("стенд не отвечает", T0, "duty-1");

        assertThat(incident.getId()).isNull();                 // ключ появится при сохранении
        assertThat(incident.getTitle()).isEqualTo("стенд не отвечает");
        assertThat(incident.getDetectedAt()).isEqualTo(T0);
        assertThat(incident.getDutyName()).isEqualTo("duty-1");
        assertThat(incident.getFixedAt()).isNull();
    }

    @Test
    void fixRemembersTime() {
        Incident incident = new Incident("стенд не отвечает", T0, "duty-1");

        incident.fix(T0.plusSeconds(600));

        assertThat(incident.getFixedAt()).isEqualTo(T0.plusSeconds(600));
    }

    @Test
    void cannotFixTwice() {
        Incident incident = new Incident("стенд не отвечает", T0, "duty-1");
        incident.fix(T0.plusSeconds(600));

        assertThatThrownBy(() -> incident.fix(T0.plusSeconds(900)))
                .isInstanceOf(IllegalStateException.class);
        assertThat(incident.getFixedAt()).isEqualTo(T0.plusSeconds(600));   // первое время не тронуто
    }

    @Test
    void cannotFixBeforeDetected() {
        Incident incident = new Incident("стенд не отвечает", T0, "duty-1");

        assertThatThrownBy(() -> incident.fix(T0.minusSeconds(1)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThat(incident.getFixedAt()).isNull();
    }

    @ParameterizedTest(name = "{0}, {1}, {2} — ошибка")
    @CsvSource(delimiter = '|', nullValues = "null", textBlock = """
            null  | 2026-10-05T09:15:00Z | duty-1
            ''    | 2026-10-05T09:15:00Z | duty-1
            '   ' | 2026-10-05T09:15:00Z | duty-1
            стенд | null                 | duty-1
            стенд | 2026-10-05T09:15:00Z | null
            стенд | 2026-10-05T09:15:00Z | '   '
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

    // неподвижное «сейчас» для всех тестов класса
    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void findsOnlyOpen() {
        // save вернёт сущность уже с ключом
        Incident open = incidents.save(new Incident("стенд не отвечает", T0, "duty-1"));
        Incident fixed = new Incident("очередь растёт", T0, "duty-2");
        fixed.fix(T0.plusSeconds(600));
        incidents.save(fixed);

        assertThat(incidents.findByFixedAtIsNull())
                .extracting(Incident::getId)
                .containsExactly(open.getId());
    }

    @Test
    void findsByDutyName() {
        Incident first = incidents.save(new Incident("стенд не отвечает", T0, "duty-1"));
        Incident second = incidents.save(new Incident("письма не уходят", T0.plusSeconds(300), "duty-1"));
        incidents.save(new Incident("очередь растёт", T0, "duty-2"));

        assertThat(incidents.findByDutyName("duty-1"))
                .extracting(Incident::getId)
                .containsExactlyInAnyOrder(first.getId(), second.getId());   // без order by порядок не обещан
    }

    @Test
    void findsOpenOfDutyOldestFirst() {
        Incident later = incidents.save(new Incident("письма не уходят", T0.plusSeconds(300), "duty-1"));
        Incident earlier = incidents.save(new Incident("стенд не отвечает", T0, "duty-1"));
        Incident fixed = new Incident("очередь растёт", T0, "duty-1");
        fixed.fix(T0.plusSeconds(60));
        incidents.save(fixed);
        incidents.save(new Incident("диск заполнен", T0, "duty-2"));

        assertThat(incidents.findOpenOf("duty-1"))
                .extracting(Incident::getId)
                .containsExactly(earlier.getId(), later.getId());            // порядок задан в @Query
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

    // в прошлом: fixAll берёт «сейчас» из настоящих часов
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
        log.add("стенд не отвечает");

        assertThat(incidents.findByDutyName("duty-1"))                       // дежурный — из GameDayConfig
                .extracting(Incident::getTitle)
                .containsExactly("стенд не отвечает");
    }

    @Test
    void fixAllRollsBackWhenOneIdIsUnknown() {
        List<UUID> ids = new ArrayList<>();
        for (String title : List.of("стенд не отвечает", "очередь растёт", "письма не уходят")) {
            ids.add(incidents.save(new Incident(title, T0, "duty-1")).getId());
        }
        ids.add(UUID.randomUUID());

        assertThatThrownBy(() -> log.fixAll(ids))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("нет происшествия");

        assertThat(incidents.findByFixedAtIsNull()).hasSize(3);
    }
}
```
