# Данные дальше: конвертеры JPA, JSON в столбце, выборки по времени, индексы

> «От Spring к системе» · статья 9 · читать минут 30
>
> **Для кого.** Ты прочитал статьи 0–8, и у тебя есть песочница
> `game-day` после статьи 8: таблица `game_day.incident` и миграция (3а),
> сущность `Incident`, хранилище и тесты `*IT` на Postgres в контейнере
> (3б), страницы (5). Знаешь, что JSON в Java пишет и читает Jackson
> (статьи 4 и 7).
>
> **Что будет.** Как хранить перечисление в столбце, чтобы правка Java
> не перевернула смысл старых строк. Как положить в столбец JSON и когда
> брать `JSONB`, а когда — текст. Как выбрать «что давно висит» так, чтобы
> база не читала ради этого всю таблицу.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Spring к системе» — следующий шаг
> после «От Java к Spring Boot»: как приложение живёт среди других
> программ. Примеры — учебные: их можно повторить у себя.

---

## Зачем: не всё ложится строкой и числом

После игрового дня тимлид разбирает журнал и задаёт три вопроса, на
которые таблица из статьи 3а не отвечает.

**Насколько серьёзно?** «Стенд не отвечает» и «опечатка в письме» — не
одно и то же. Серьёзность — одно из трёх значений, в Java это
перечисление.

**Что именно сломали?** У атаки на брокер есть цель и атакующий, у атаки
на почту — ещё и адрес. Форма у подробностей разная, и столбец под
каждое поле — это миграция на каждую новую атаку. Подробности хранят
одним столбцом, в JSON.

**Что висит?** В игровой день дежурный смотрит на открытые происшествия,
которые не починили за 30 минут: их пора поднимать мидлу. Это выборка по
времени и состоянию, и на журнале за сезон она должна идти быстро.

Журнал игрового дня — учебный пример. Но в рабочих проектах всё это
встречается на каждом шагу: перечисление в столбце, JSON рядом
с обычными столбцами, выборки «что пора сделать» по времени, списки
с фильтром по состоянию. Такие задачи делают и джуны. Что сделать,
сказано в тексте задачи; статья объясняет то, чего там обычно нет, —
почему так и что сломается, если иначе.

Строим на журнале: `Severity` и `SeverityConverter`; `details`
в столбце `JSONB`; выборку «открытые дольше N минут», индекс под неё
и миграцию в таблицу с данными.

В коротких примерах нет строк `import` — полные файлы в конце статьи.

---

## Часть 1. Перечисление в столбце

### Severity — перечисление с кодом

Перечисление с кодом ты писал в статье 0 — `Area`, а в статье 8 видел
`AttackOutcome`: имя константы — для Java, код — «для базы и JSON».
Серьёзность устроена так же:

```java
public enum Severity {
    LOW("low"), HIGH("high"), CRITICAL("critical");

    private final String code;              // как серьёзность пишется в базе
    // конструктор, code() и fromCode(String) — как у Area в статье 0;
    // незнакомый код — IllegalArgumentException
}
```

### Два готовых способа JPA — и чем ломается каждый

JPA умеет хранить перечисление сама — аннотацией `@Enumerated` над полем
сущности:

```java
@Enumerated(EnumType.STRING)          // или EnumType.ORDINAL; оба — из jakarta.persistence
@Column(name = "severity", nullable = false)
private Severity severity;
```

**`EnumType.ORDINAL`** — номер значения по порядку: `LOW` — 0, `HIGH` — 1,
`CRITICAL` — 2.

🔴 Через год кто-то добавит `MEDIUM` между `LOW` и `HIGH` — так ведь
логичнее. Номера сдвинутся: все старые `HIGH` (1) молча станут `MEDIUM`,
а `CRITICAL` (2) — `HIGH`. Ни ошибки, ни красного теста: в базе те же
числа, просто они теперь значат другое. Узнаешь, когда критичное
происшествие покажут «средним». Переименовать значение при `ORDINAL`
можно — номер тот же; нельзя вставлять и переставлять. Помнишь ⚠️ из
статьи 8: по номеру константы не разбирают чужой код — и по той же
причине не хранят свой.

Если над полем-перечислением нет ни `@Enumerated`, ни преобразователя,
JPA выбирает именно `ORDINAL`. В песочнице такую забывчивость поймает
сверка `validate` из статьи 3б: в столбце строка, а Hibernate ждёт номер,
и приложение не стартует с `wrong column type encountered in column
[severity]`. Без сверки — молча писало бы числа.

**`EnumType.STRING`** — имя значения в Java: `LOW`, `HIGH`, `CRITICAL`.
Добавлять и переставлять теперь можно.

⚠️ Зато имя стало частью базы. Переименуешь `CRITICAL` в `BLOCKER` —
старые строки не прочитаются: в базе `CRITICAL`, а такого значения в Java
больше нет. Переименование превращается в миграцию данных.

Оба способа встречаются в настоящих проектах. Имя проще: ничего писать
не нужно. Код надёжнее, когда у значения есть жизнь за пределами Java:
оно стоит в JSON ручек, в адресе, в настройках, в тегах метрик. Тогда
действует правило «одно понятие — одно написание везде»: в базе то же
`critical`, что в JSON. Журналу нужен код: серьёзность пойдёт и в базу,
и в тег метрики (дальше в серии).

### AttributeConverter — перевод, который пишешь сам

**Преобразователь** (converter, в разговоре — «конвертер») — класс,
который объясняет JPA, как перевести значение поля в значение столбца
и обратно. Договор — интерфейс `AttributeConverter<X, Y>`: `X` — тип
поля в Java, `Y` — тип столбца.

```java
@Converter                                                      // «это преобразователь»
public class SeverityConverter implements AttributeConverter<Severity, String> {

    @Override
    public String convertToDatabaseColumn(Severity severity) {   // при записи: поле → столбец
        if (severity == null) {
            return null;                                         // пусто остаётся пустым
        }
        return severity.code();
    }

    @Override
    public Severity convertToEntityAttribute(String code) {      // при чтении: столбец → поле
        if (code == null) {
            return null;
        }
        return Severity.fromCode(code);                          // незнакомый код — исключение
    }
}
```

Hibernate зовёт первый метод перед записью строки, второй — после
чтения. Бином преобразователь делать не нужно: JPA найдёт его по
аннотации на поле сущности.

```java
@Convert(converter = SeverityConverter.class)                   // поле идёт через преобразователь
@Column(name = "severity", nullable = false)
private Severity severity;
```

Теперь `MEDIUM` можно вставить куда угодно, а `CRITICAL` в Java —
переименовать: в базе по-прежнему `critical`. Менять придётся только сам
код `critical` — и только вместе с миграцией данных.

Серьёзность задаёт тот, кто записывает происшествие: у `IncidentLog`
появляется `add(String title, Severity severity)`, а прежний
`add(String title)` зовёт его с `Severity.LOW` — код прошлых статей
не меняется. Прочитать серьёзность — `getSeverity()` у `Incident`.

⚠️ `@Enumerated` и `@Convert` на одно поле не ставят: стандарт JPA
запрещает преобразователь у поля с `@Enumerated`. Или одно, или другое.
Hibernate 7 такое приложение не поднимет:
`'AttributeConverter' not allowed for attribute 'severity' annotated '@jakarta.persistence.Enumerated'`.

Как вести себя преобразователю, в рабочем проекте договорено так —
и у каждого правила есть причина:

* **`autoApply = true` не включают.** Эта настройка `@Converter`
  применяет преобразователь ко всем полям его типа во всех сущностях
  сразу, без `@Convert`. Удобно, но глядя на поле, уже не скажешь, что
  оно идёт через перевод. С `@Convert` это видно в одной строке над
  полем;
* **`null` пропускают насквозь.** Зовут ли преобразователь с `null`,
  документация JPA не говорит, — поэтому он не падает в любом случае.
  А не пустить пустое — дело конструктора сущности и `NOT NULL`
  в таблице;
* **незнакомый код из базы — исключение, а не `null`.** Код в базе —
  наш, а свой код разбирают строго (статья 8). Незнакомый значит, что
  строку записал кто-то другой: рука в `psql`, старая или новая версия
  приложения. `null` спрятал бы это — поле, обязательное в таблице, молча
  стало бы пустым.

💡 В JPA 3.2 (её выполняет Hibernate 7 из Boot 4) есть и третий путь:
пометить поле `code` в самом перечислении аннотацией `@EnumeratedValue` —
тогда `EnumType.STRING` пишет код, а не имя. В журнале выбран
преобразователь: так перечисление ничего не знает о базе.

💡 Тот же приём кладёт в столбец и объект-значение из статьи 8:
`AttributeConverter<DutyName, String>`.

### Тест преобразователя — без Spring и без базы

Преобразователь — обычный класс: `new SeverityConverter()` — и проверяй:

```java
@Test
void convertsCriticalBothWays() {
    assertThat(converter.convertToDatabaseColumn(Severity.CRITICAL)).isEqualTo("critical");
    assertThat(converter.convertToEntityAttribute("critical")).isEqualTo(Severity.CRITICAL);
}
```

Что в столбце на настоящей базе лежит именно `critical`, проверяет
`IncidentColumnsIT` из полного примера. Здесь — приём, а не полный
набор: в рабочем проекте случаи — каждое значение в обе стороны, `null`,
незнакомый код — перечисляет таблица в тексте задачи.

---

## Часть 2. JSON в столбце

### JSON текстом — когда хватает

JSON в столбце бывает и простым текстом. Скажем, журнал захотел бы
хранить значения для шаблона оповещения — `Map<String, String>`, карту
(помнишь, статья 8): по строке-ключу лежит строка-значение. База в этих
значениях ничего не ищет, только хранит и отдаёт целиком.

Тогда столбец — **текст** (`TEXT`), а в карту и обратно его переводит
преобразователь с Jackson внутри: `AttributeConverter<Map<String, String>, String>`.
Так делают и в рабочих проектах: простой преобразователь не зависит
от того, как Hibernate поддерживает JSON-типы.

### Журналу нужен JSONB — почему

Журналу от подробностей нужно больше: найти все атаки на брокер. Для
этого в Postgres есть тип **`JSONB`** — JSON, который база разобрала
и хранит в своём двоичном виде. Что это даёт:

* **база видит внутрь.** Оператор `->>` достаёт значение по ключу
  текстом — пример под списком. В `TEXT` база видела бы просто строку
  символов;
* **битый JSON не ляжет.** На `'{"target": "broker"'` (нет скобки)
  Postgres ответит `invalid input syntax for type json`. Последний рубеж,
  как `CHECK` в статье 3а. В `TEXT` ляжет что угодно, и упадёт уже
  чтение — поэтому у текстового преобразователя есть тест на «не JSON»;
* **порядок ключей неважен.** `JSONB` не хранит пробелы, порядок ключей
  и повторы ключей, поэтому `{"a":"1","b":"2"}` и `{"b":"2","a":"1"}` для
  него равны. Текст хранит ключи как записали, и одна и та же карта может
  лечь двумя разными строками. Поэтому текстовый преобразователь обычно
  сортирует ключи сам — кладёт карту в `TreeMap`, где ключи всегда
  по алфавиту.

```sql
SELECT title FROM game_day.incident WHERE details ->> 'target' = 'broker';
```

🔑 Тип столбца выбирают по тому, что база должна делать с JSON: только
хранить — можно текст; искать внутри и проверять — `JSONB`.

### Два способа в Hibernate 7

**Первый — преобразователь**, как для текста выше:
`AttributeConverter<Map<String, String>, String>` с Jackson внутри. Для
`TEXT` — то, что нужно. С `JSONB` приложение даже не стартует. Hibernate
при старте сверяет сущность с таблицей (`validate`, статья 3б): ждёт
строковый столбец, а находит `jsonb`. В логе это одна строка, здесь она
разбита надвое:

```
Schema validation: wrong column type encountered in column [details] in table [game_day.incident];
found [jsonb (Types#OTHER)], but expecting [varchar(255) (Types#VARCHAR)]
```

Выключишь сверку — упадёт первая же запись. Строку Hibernate отдаёт
базе как `varchar`, а Postgres сам `varchar` в `jsonb` не превращает:

```
ERROR: column "details" is of type jsonb but expression is of type character varying
```

**Второй — встроенное отображение JSON.** Hibernate 7 умеет класть поле
в JSON-столбец сам, нужно только попросить:

```java
@JdbcTypeCode(SqlTypes.JSON)                        // «столбец — JSON»; на Postgres — jsonb
@Column(name = "details", nullable = false)
private Map<String, String> details;
```

`@JdbcTypeCode` и `SqlTypes` — аннотация и константы самого Hibernate
(пакеты `org.hibernate.annotations` и `org.hibernate.type`), не JPA. Без
них JSON-тип Hibernate не возьмёт. Карту в JSON переводит Jackson 3 —
он в песочнице уже есть, его принёс стартер веба (статья 4), и Hibernate
находит его сам.

Журнал берёт второй способ: из двух только он правильно пишет в столбец
`JSONB`. Что в столбце лежит на самом деле, проверяет `IncidentColumnsIT`
из полного примера: он читает столбец мимо JPA, через `JdbcTemplate`
(статья 3а).

⚠️ В туториалах ты увидишь `@Type(JsonType.class)` из сторонней
библиотеки. Это Hibernate 5 и раньше: `@JdbcTypeCode` появился в 6.0.
В Boot 4 — Hibernate 7, сторонняя библиотека не нужна.

⚠️ Маппер (объект Jackson, который пишет и читает JSON) у Hibernate —
**свой**, не тот бин `JsonMapper`, что пишет JSON ручек. Это тот же
Jackson 3, но Hibernate собирает его сам, с умолчаниями Jackson 2
(`builderWithJackson2Defaults`), а они строже. Помнишь из статьи 7:
Jackson 3 незнакомое поле пропускает. Маппер Hibernate на нём падает.
Настройки `spring.jackson.*` из `application.yml` до него
не долетают.

В одном рабочем проекте в `JSONB` попало поле, которого нет в записи
Java, — и строка перестала читаться целиком, со всеми столбцами.
У карты лишних полей не бывает, зато чтение так же сломает
значение-объект: `{"target": {"host": "broker"}}` база пустит, а
в `Map<String, String>` его не прочитать —
``Cannot deserialize value of type `java.lang.String` from Object value``.
Поэтому `details` пишут только через `Incident`: там карта строк,
и другого в неё не положить.

💡 Ищет Jackson Hibernate сам, и сначала — Jackson 2. Принесёт его
в проект какая-нибудь библиотека — и Hibernate молча возьмёт его,
а не Jackson 3. В песочнице Jackson 2 нет.

---

## Часть 3. Выборка «открытые дольше N минут»

### Граница — от часов

«Открыто дольше 30 минут» значит: не починено, а заметили раньше, чем
«сейчас минус 30 минут». Этот момент — **граница**. Считает её служба,
из часов `Clock`:

```java
public List<Incident> openLongerThan(Duration age) {              // новый метод IncidentLog
    Instant border = clock.instant().minus(age);                  // «сейчас» — только из часов
    return incidents.findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(border);
}
```

Почему не `now()` в SQL: тогда «сейчас» знает только база, и тест не
может его задать. Почему не `Instant.now()` в Java: помнишь правило из
статей 1 и 3б — «сейчас» берут только из бина `Clock`. В рабочем проекте
так устроены все выборки по времени: «сейчас» считает служба, а
в хранилище время приходит параметром.

### Метод по имени — и @Query

Имя читается по частям, как в статье 3б:

| часть имени | что значит | в SQL |
|---|---|---|
| `FixedAtIsNull` | ещё не починено | `fixed_at is null` |
| `And` | и | `and` |
| `DetectedAtBefore` | замечено раньше границы | `detected_at < ?` |
| `OrderByDetectedAtAsc` | старые первыми | `order by detected_at` |

В имени — поля сущности (`fixedAt`), в SQL, который построит Hibernate, —
столбцы (`fixed_at`), как в статье 3б. `Before` — то же «строго меньше»,
что `LessThan`, только словом для времени.

Имя вышло длинным. Тот же запрос можно написать в `@Query`: имя
короче, а запрос виден целиком.

```java
@Query("select i from Incident i where i.fixedAt is null and i.detectedAt < ?1 order by i.detectedAt")
List<Incident> findOpenDetectedBefore(Instant border);
```

Выбери одно. Журнал оставляет имя — как методы страниц из статьи 5.

### Граница — тоже решение

Заметили ровно 30 минут назад — это «дольше 30»? `Before` — строго
меньше, значит, нет. В другой выборке бывает наоборот — `LessThanEqual`,
«меньше или равно»: скажем, письмо, чьё время отправки наступило ровно
сейчас, уже должно уйти. Ни одно не «правильнее». Границу выбирают
по смыслу, пишут строкой в таблицу случаев и проверяют отдельным тестом.

### Тест: часы стоят, данные подобраны

**Служба** — юнит-тест: часы остановлены (`Clock.fixed` из статьи 1),
хранилище — заглушка. Вопрос один: граница посчитана от часов?

```java
// incidents и notifier — заглушки @Mock, как в статье 5
IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
        Clock.fixed(Instant.parse("2026-10-05T10:00:00Z"), ZoneOffset.UTC), incidents);

log.openLongerThan(Duration.ofMinutes(30));

verify(incidents).findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(
        Instant.parse("2026-10-05T09:30:00Z"));                   // 10:00 минус 30 минут
```

**Хранилище** — `*IT` на настоящем Postgres, своим классом
`IncidentAgeIT` с уборкой в `@AfterEach`, как `IncidentPagesIT`
в статье 5. Аннотации у него те же — `@SpringBootTest`
и `@Import(TestcontainersConfiguration.class)`, — так что приложение
и контейнер Spring возьмёт из кэша (статья 3а). Граница — константа,
данные — такие, чтобы ошибка была видна:

```java
private static final Instant BORDER = Instant.parse("2026-10-05T09:30:00Z");

@Test
void findsOpenOlderThanBorderOldestFirst() {
    Incident broker = incidents.save(new Incident("брокер молчит", BORDER.minusSeconds(600), "duty-1"));
    incidents.save(new Incident("лента стоит", BORDER.plusSeconds(1200), "duty-2"));   // свежее
    incidents.save(new Incident("письма копятся", BORDER, "duty-1"));                 // ровно на границе
    Incident disk = incidents.save(new Incident("диск заполнен", BORDER.minusSeconds(1200), "duty-2"));
    Incident fixed = new Incident("стенд не отвечает", BORDER.minusSeconds(1800), "duty-1");
    fixed.fix(BORDER.minusSeconds(1500));                                              // старое, но закрыто
    incidents.save(fixed);

    assertThat(incidents.findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(BORDER))
            .extracting(Incident::getId)
            .containsExactly(disk.getId(), broker.getId());
}
```

Каждая строка ловит свою ошибку. Свежее — забытое условие по времени.
На границе — `<=` вместо `<`. Закрытое и самое старое — забытое `IsNull`.
Вставка не по порядку времени — забытый `OrderBy`. Проверь хотя бы одно:
добавь рядом временный метод без `FixedAtIsNull`, позови его в тесте
вместо настоящего — тест обязан покраснеть. Потом метод удали.

⚠️ Забытый `OrderBy` эти данные ловят не всегда. Когда в таблице
появится индекс из части 4, база может пойти по нему — а он и так
отдаёт строки по времени. Тест зелёный, а порядок держится на плане
базы, который сменится, как только база пересчитает свои строки.
Обещанный порядок пишут в запросе и не надеются на индекс.

---

## Часть 4. Индекс и миграция

### Индекс — указатель в конце книги

Чтобы найти в книге все страницы про Flyway, её не читают подряд —
открывают указатель в конце: слова по алфавиту, у каждого — номера
страниц. **Индекс** в базе — то же самое: отсортированный список
значений столбца, и у каждого — где лежит строка. По умолчанию Postgres
строит индекс-дерево (B-tree): по нему быстро найти значение или
диапазон «меньше границы» — и сразу получить их по порядку.

Без индекса запрос читает таблицу целиком — это **последовательный
просмотр** (в плане базы — `Seq Scan`). Пока в журнале двадцать строк,
разницы нет. За сезон игровых дней их сотни тысяч, а дежурный обновляет
экран каждую минуту.

У индекса есть цена: каждая вставка и правка обновляет и его, и он
занимает место. Поэтому индекс ставят **под конкретный запрос**, а не
«на всякий случай».

### Составной индекс: порядок столбцов

Индекс бывает по нескольким столбцам. `(duty_name, detected_at)`
отсортирован сначала по дежурному, а внутри — по времени. Это указатель
«фамилия, потом имя»: всех Ивановых найти быстро, и среди них имена
уже по алфавиту; всех Петров, не зная фамилии, — только перебором всего
указателя.

Отсюда правило: сначала столбцы, по которым отбирают точно (`=`), потом
те, что сравнивают или сортируют. Такой индекс подошёл бы `findOpenOf`
из статьи 3б — «открытые у дежурного, старые первыми»: дежурного
выбирают точно, по времени сортируют.

Нашей выборке такой индекс не поможет: `duty_name` в ней нет, а индекс
начинается с него.

### Частичный индекс: только открытые

Открытых происшествий в каждый момент — единицы, закрытых — почти все.
Зачем держать в указателе закрытые, если выборка про них не спрашивает?
**Частичный индекс** строится не по всей таблице, а только по строкам,
которые подходят под условие:

```sql
CREATE INDEX ix_incident_open_detected
    ON game_day.incident (detected_at)
    WHERE fixed_at IS NULL;                     -- в указателе только открытые
```

На учебном журнале в 200 000 строк, где открыта каждая двухсотая, такой
индекс занял 40 КБ, а обычный по `detected_at` — 4,3 МБ, в сто с лишним
раз больше.

⚠️ Частичным индексом база пользуется, только если в запросе есть **то
же условие**: доказывать, что одно условие следует из другого, Postgres
почти не умеет. Выборка без `fixed_at IS NULL` («все, замеченные раньше
границы») индекс не возьмёт. Наш метод должен дать `fixed_at is null` —
проверь сам. Включи вывод SQL:
`@TestPropertySource(properties = "spring.jpa.show-sql=true")` над
`IncidentAgeIT` (аннотация теста: добавить настройку только этому
классу) — и найди условие в строке, которая начинается
с `Hibernate:`. Перед коммитом аннотацию убери.

Границу Hibernate шлёт параметром — в его SQL на её месте `?`. Индексу
это не мешает: условие `fixed_at IS NULL` от параметра не зависит.

### EXPLAIN — пошла ли база в индекс

`EXPLAIN` перед запросом возвращает не строки, а **план**: как база
собирается их доставать.

**Где пробовать.** На своей базе в контейнере — «базе на минуту» из
статьи 3а. Подними её той же `docker run` и запусти песочницу, как
в статье 5: три переменные `SPRING_DATASOURCE_*`, затем `./mvnw package`
и `java -jar target/game-day-0.0.1-SNAPSHOT.jar`. Flyway применит обе
миграции — в логе
`Successfully applied 2 migrations to schema "game_day", now at version v2`.
Приложение можно остановить, `Ctrl+C`: таблица осталась в базе. Открой
`psql` в контейнере — `docker exec -it game-day-db psql -U postgres`.

После опыта погаси базу: `docker stop game-day-db`. С `--rm` она уйдёт
вместе с учебными строками. Стенд из статьи 6 тоже годится — `psql` там
в контейнере службы `db`, — только потом сотри его том,
`docker compose down -v`: двести тысяч учебных строк стенду ни к чему.

🔴 Такие опыты — только в своей базе. На общих стендах рабочего проекта
руками не наливают и не правят ничего.

**Сначала налей строк.** ⚠️ План на игрушечной таблице на большую
не переносится. Когда база посчитала свои строки (это делает `ANALYZE`,
ниже), на таблице из десятка строк будет `Seq Scan` даже с индексом.
Это не ошибка: маленькую таблицу дешевле прочитать целиком. А пока
не посчитала — гадает, и план может выйти любым. Этот запрос вставит
200 000 учебных происшествий и даст базе их посчитать:

```sql
INSERT INTO game_day.incident (title, detected_at, fixed_at, duty_name)
SELECT 'учебное ' || n,                                               -- n — число из ряда
       TIMESTAMPTZ '2026-01-01 00:00:00Z' + n * INTERVAL '1 minute',
       CASE WHEN n % 200 = 0 THEN NULL                                -- каждое 200-е — открыто
            ELSE TIMESTAMPTZ '2026-01-01 00:00:00Z' + n * INTERVAL '1 minute' + INTERVAL '5 minutes' END,
       'duty-1'
FROM generate_series(1, 200000) AS n;                                 -- ряд чисел от 1 до 200 000
ANALYZE game_day.incident;                                            -- пересчитать, сколько у базы чего
```

`SELECT` вместо `VALUES` — вставить все строки, которые вернул запрос:
по одной на каждое число ряда. `||` склеивает текст, `%` — остаток от
деления, `CASE WHEN … THEN … ELSE … END` — «если, то, иначе». Серьёзность
и подробности не названы — их даст `DEFAULT` из миграции (ниже).

**Теперь план:**

```sql
EXPLAIN SELECT id FROM game_day.incident
WHERE fixed_at IS NULL AND detected_at < '2026-10-05T09:30:00Z'
ORDER BY detected_at;
```

На учебных строках он вернул:

```
Index Scan using ix_incident_open_detected on incident  (cost=0.28..51.02 rows=900 width=24)
  Index Cond: (detected_at < '2026-10-05 09:30:00+00'::timestamp with time zone)
```

Смотри на начало первой строки. `Index Scan using ix_…` — база пошла по
индексу; `Bitmap Index Scan … ix_…` — тоже индекс. `Seq Scan on incident` —
прочитала всю таблицу, и выше обычно стоит `Sort`: сортировала сама.
У `Index Scan` сортировки нет — строки пришли из индекса по порядку.
В скобках — оценки базы, их пока пропускай: числа у тебя будут другие.

Теперь убери из запроса `fixed_at IS NULL AND` — и план станет `Sort`
над `Seq Scan`: без того же условия частичный индекс база не взяла.

### Миграция: столбцы в таблицу с данными

Всё новое ложится одной миграцией `V2__game_day_incident_severity.sql` —
следующий номер после `V1` (статья 3а). Первое, что хочется написать:

```sql
ALTER TABLE game_day.incident ADD COLUMN severity VARCHAR(10) NOT NULL;
```

⚠️ В тестах эта строка пройдёт: Testcontainers даёт пустую базу. А там,
где в журнале уже есть строки, — в базе из статьи 5, на стенде из
статьи 6, на боевом, — упадёт:

```
ERROR:  column "severity" of relation "incident" contains null values
```

У старых строк новый столбец пуст, а `NOT NULL` пустого не пускает.
Flyway не применит миграцию, и приложение не стартует. В рабочем проекте
так и бывает: сборка зелёная, пул-реквест влит, а на общем стенде,
где данные есть, — красное. Лечится умолчанием: `DEFAULT` отдаёт своё
значение всем старым строкам. Таблицу Postgres при этом не переписывает —
запоминает умолчание у себя.

```sql
ALTER TABLE game_day.incident
    ADD COLUMN severity VARCHAR(10) NOT NULL DEFAULT 'low'
        CONSTRAINT incident_severity_known CHECK (severity IN ('low', 'high', 'critical')),
    ADD COLUMN details  JSONB       NOT NULL DEFAULT '{}'
        CONSTRAINT incident_details_object CHECK (jsonb_typeof(details) = 'object');
```

По строкам:

* `DEFAULT 'low'` — какой серьёзности были старые происшествия,
  неизвестно; `low` — выбор журнала (в рабочем проекте такие выборы
  пишут в описании пул-реквеста). Hibernate пишет столбец всегда, так что
  умолчание нужно старым строкам и SQL-вставкам вроде `IncidentTableIT`
  из статьи 3а — без него тот покраснеет;
* `CHECK (severity IN (…))` — коды маленькими, ровно как пишет
  преобразователь. Сам приём — `VARCHAR` и `CHECK (… IN (…))` —
  в рабочем проекте правило для перечислений в базе; регистр у каждого
  столбца свой — какой пишет Java. `CRITICAL` заглавными база
  не пустит;
* `DEFAULT '{}'` — «подробностей нет» значит пустой объект, а не `NULL`:
  читающему коду не нужна отдельная ветка на «нет вовсе»;
* `jsonb_typeof(details) = 'object'` — функция называет тип значения
  (`object`, `array`…): массив `["broker"]` база не пустит. Что внутри
  объекта — строки или нет, — `CHECK` не смотрит:
  `{"target": {"host": "broker"}}` пройдёт (⚠️ в части 2).

В ту же миграцию — индекс из раздела выше. А в `Incident` — поля
`severity` и `details`, вместе с миграцией: Hibernate при старте сверяет
сущность с таблицей (статья 3б), и поле без столбца не даст приложению
подняться.

⚠️ Имя индекса уникально во всей схеме, а не только в таблице. В одном
рабочем проекте новая миграция взяла занятое имя: Flyway упал,
приложение не поднялось, и 810 тестов отчитались одной и той же ошибкой
контекста. Причину ищи в **первом** падении, выше по логу: дальше Spring
приложение даже не поднимает и пишет коротко —
`ApplicationContext failure threshold (1) exceeded`. А имя перед
`CREATE INDEX` сверь со всеми миграциями.

### Чего здесь нет

Это темы мидлов: как построить индекс на большой боевой таблице,
не остановив запись (обычный `CREATE INDEX` не даёт писать в таблицу,
пока строится, — для этого есть `CREATE INDEX CONCURRENTLY`); как быстро
листать далёкие страницы; изоляция транзакций и блокировки строк.
В рабочем проекте их решают мидлы. Здесь о них одно слово — чтобы ты
узнал их, когда встретишь в чужом коде.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. В `Severity` добавили `MEDIUM` между `LOW` и `HIGH`. Что станет со
   старыми строками при `ORDINAL`, при `STRING` и с преобразователем?
   А если переименовать `CRITICAL`?
2. Можно ли поставить на поле и `@Enumerated`, и `@Convert`? Что даёт
   `@EnumeratedValue` и почему журнал всё равно берёт преобразователь?
   Почему незнакомый код из базы — исключение, а не `null`?
3. Что будет, если преобразователь начнёт писать в столбец `CRITICAL`?
   Какой тест это поймает?
4. Значения для шаблона оповещения можно хранить текстом, а `details`
   журнала — в `JSONB`. Почему оба решения верны? Что будет, если
   в столбец `JSONB` писать строку из преобразователя? От чего
   не защищает `CHECK` на `details`?
5. Почему границу «30 минут назад» считает служба из `Clock`, а не база
   и не `Instant.now()`? Происшествие заметили ровно 30 минут назад —
   попадёт ли оно в выборку и какой тест это сторожит?
6. Что такое частичный индекс? Почему выборка без `fixed_at IS NULL` им
   не воспользуется, а индекс `(duty_name, detected_at)` не поможет
   выборке «открытые дольше N минут»?
7. На локальной базе `EXPLAIN` показал `Seq Scan`, хотя индекс есть.
   Индекс сломан?
8. Миграция `ADD COLUMN severity … NOT NULL` прошла в тестах и упала
   на стенде. Почему и как написать правильно?

---

## Что дальше

Дальше в серии — метрики. Журнал начнёт считать происшествия, и у
счётчика появится тег `severity` — перечисление из этой статьи.

## Первоисточники

* [Hibernate ORM 7: User Guide](https://docs.hibernate.org/orm/7.0/userguide/html_single/) —
  разделы Enums, AttributeConverters и JSON mapping: `@Enumerated`,
  преобразователи, `@JdbcTypeCode(SqlTypes.JSON)`;
* [Spring Data JPA: Repository query keywords](https://docs.spring.io/spring-data/jpa/reference/repositories/query-keywords-reference.html) —
  `Before`, `LessThan`, `LessThanEqual`, `IsNull`, `OrderBy` в имени
  метода;
* [PostgreSQL 17: JSON Types](https://www.postgresql.org/docs/17/datatype-json.html) —
  чем `jsonb` отличается от `json` и текста, что он не хранит;
* [PostgreSQL 17: Multicolumn Indexes](https://www.postgresql.org/docs/17/indexes-multicolumn.html) —
  почему важен ведущий столбец составного индекса;
* [PostgreSQL 17: Partial Indexes](https://www.postgresql.org/docs/17/indexes-partial.html) —
  частичный индекс и когда база может им пользоваться;
* [PostgreSQL 17: Using EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html) —
  как читать план и почему план игрушечной таблицы не переносится
  на большую;
* [PostgreSQL 17: ALTER TABLE](https://www.postgresql.org/docs/17/sql-altertable.html) —
  раздел Notes: `ADD COLUMN` с `DEFAULT` без перезаписи таблицы.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 8: Postgres
в контейнере, миграция `V1__game_day_incident.sql`,
`TestcontainersConfiguration`, журнал в `example.gameday.journal` с
хранилищем, ручками статей 4–5 и объектами-значениями статьи 8, охрана,
Actuator и стенд статьи 6 — всё остаётся. В `pom.xml` ничего добавлять
не нужно: Hibernate приехал со стартером JPA (статья 3б), Jackson 3 —
со стартером веба (статья 4), JUnit, AssertJ и Mockito — со
`spring-boot-starter-test`.

Что поменять: в `Incident` — два поля и второй конструктор;
в `IncidentRepository` — метод «открытые дольше»; в `IncidentLog` —
`add` с серьёзностью и `openLongerThan`. Все три файла ниже целиком.

Что добавить: миграцию `V2__game_day_incident_severity.sql`;
в `example.gameday.journal` — `Severity` и `SeverityConverter`; там же
под `src/test/java` — тесты `SeverityConverterTest`, `IncidentLogAgeTest`,
`IncidentAgeIT` и `IncidentColumnsIT`. Остальное — `DutyRoster`,
`Notifier`, `GameDayConfig` с часами, службы и контроллеры, тесты
прошлых статей — без изменений: старый конструктор `Incident`
и `add(String)` остались.

Запуск: один класс — треугольником в IDE или
`./mvnw test -Dtest=SeverityConverterTest`; весь `./mvnw verify` гоняет
и `*IT` — нужен запущенный Docker. Путь к файлу — комментарием в первой
строке.

```sql
-- src/main/resources/db/migration/V2__game_day_incident_severity.sql
-- Журнал игрового дня: серьёзность, подробности атаки и индекс под «открытые дольше N минут».
ALTER TABLE game_day.incident
    ADD COLUMN severity VARCHAR(10) NOT NULL DEFAULT 'low'
        CONSTRAINT incident_severity_known CHECK (severity IN ('low', 'high', 'critical')),
    ADD COLUMN details  JSONB       NOT NULL DEFAULT '{}'
        CONSTRAINT incident_details_object CHECK (jsonb_typeof(details) = 'object');

CREATE INDEX ix_incident_open_detected
    ON game_day.incident (detected_at)
    WHERE fixed_at IS NULL;
```

```java
// src/main/java/example/gameday/journal/Severity.java
package example.gameday.journal;

public enum Severity {
    LOW("low"), HIGH("high"), CRITICAL("critical");

    private final String code;

    Severity(String code) {
        this.code = code;
    }

    public String code() {
        return code;
    }

    public static Severity fromCode(String code) {
        for (Severity severity : values()) {
            if (severity.code.equals(code)) {
                return severity;
            }
        }
        throw new IllegalArgumentException("незнакомая серьёзность: " + code);
    }
}
```

```java
// src/main/java/example/gameday/journal/SeverityConverter.java
package example.gameday.journal;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

@Converter
public class SeverityConverter implements AttributeConverter<Severity, String> {

    @Override
    public String convertToDatabaseColumn(Severity severity) {
        if (severity == null) {
            return null;
        }
        return severity.code();
    }

    @Override
    public Severity convertToEntityAttribute(String code) {
        if (code == null) {
            return null;
        }
        return Severity.fromCode(code);
    }
}
```

Конструктор статьи 3б остаётся и зовёт новый — с `LOW` и пустыми
подробностями, так что код прошлых статей не меняется. Две новые
проверки конструктора — нет серьёзности, нет подробностей — просятся
строками в таблицу `IncidentTest` из статьи 3б: допиши их сам.
В рабочем проекте без них отчёт JaCoCo покажет две жёлтые ветки
(статья 0).

```java
// src/main/java/example/gameday/journal/Incident.java
package example.gameday.journal;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.util.Collections;
import java.util.Map;
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

    @Convert(converter = SeverityConverter.class)
    @Column(name = "severity", nullable = false)
    private Severity severity;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "details", nullable = false)
    private Map<String, String> details;

    protected Incident() {
    }

    public Incident(String title, Instant detectedAt, String dutyName) {
        this(title, detectedAt, dutyName, Severity.LOW, Map.of());
    }

    public Incident(String title, Instant detectedAt, String dutyName,
                    Severity severity, Map<String, String> details) {
        if (title == null || title.isBlank()) {
            throw new IllegalArgumentException("у происшествия нет заголовка");
        }
        if (detectedAt == null) {
            throw new IllegalArgumentException("не сказано, когда заметили");
        }
        if (dutyName == null || dutyName.isBlank()) {
            throw new IllegalArgumentException("не сказано, кто дежурил");
        }
        if (severity == null) {
            throw new IllegalArgumentException("не сказано, насколько серьёзно");
        }
        if (details == null) {
            throw new IllegalArgumentException("подробностей нет — передай пустую карту");
        }
        this.title = title;
        this.detectedAt = detectedAt;
        this.dutyName = dutyName;
        this.severity = severity;
        this.details = Map.copyOf(details);       // своя неизменяемая копия; null внутри карты не пустит
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

    public Severity getSeverity() {
        return severity;
    }

    public Map<String, String> getDetails() {
        // после чтения из базы карту создаёт Hibernate, и она изменяемая — отдаём только обёртку
        return Collections.unmodifiableMap(details);
    }
}
```

Хранилище — целиком, с методами статей 3б и 5:

```java
// src/main/java/example/gameday/journal/IncidentRepository.java
package example.gameday.journal;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface IncidentRepository extends JpaRepository<Incident, UUID> {

    List<Incident> findByDutyName(String dutyName);

    List<Incident> findByFixedAtIsNull();

    @Query("select i from Incident i where i.dutyName = ?1 and i.fixedAt is null order by i.detectedAt")
    List<Incident> findOpenOf(String dutyName);

    Page<Incident> findAllByOrderByDetectedAtDesc(Pageable pageable);

    Page<Incident> findByFixedAtIsNullOrderByDetectedAtDesc(Pageable pageable);

    List<Incident> findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(Instant border);
}
```

```java
// src/main/java/example/gameday/journal/IncidentLog.java
package example.gameday.journal;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
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
        add(title, Severity.LOW);
    }

    public void add(String title, Severity severity) {
        Incident incident = incidents.save(
                new Incident(title, clock.instant(), roster.currentDuty(), severity, Map.of()));
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

    public List<Incident> openLongerThan(Duration age) {
        Instant border = clock.instant().minus(age);
        return incidents.findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(border);
    }
}
```

```java
// src/test/java/example/gameday/journal/SeverityConverterTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class SeverityConverterTest {

    private final SeverityConverter converter = new SeverityConverter();

    @Test
    void convertsCriticalBothWays() {
        assertThat(converter.convertToDatabaseColumn(Severity.CRITICAL)).isEqualTo("critical");
        assertThat(converter.convertToEntityAttribute("critical")).isEqualTo(Severity.CRITICAL);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentLogAgeTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.mockito.Mockito.verify;

@ExtendWith(MockitoExtension.class)
class IncidentLogAgeTest {

    @Mock
    private IncidentRepository incidents;

    @Mock
    private Notifier notifier;

    @Test
    void borderIsNowMinusAge() {
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(Instant.parse("2026-10-05T10:00:00Z"), ZoneOffset.UTC), incidents);

        log.openLongerThan(Duration.ofMinutes(30));

        verify(incidents).findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(
                Instant.parse("2026-10-05T09:30:00Z"));
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentAgeIT.java
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
class IncidentAgeIT {

    private static final Instant BORDER = Instant.parse("2026-10-05T09:30:00Z");

    @Autowired
    private IncidentRepository incidents;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void findsOpenOlderThanBorderOldestFirst() {
        Incident broker = incidents.save(new Incident("брокер молчит", BORDER.minusSeconds(600), "duty-1"));
        incidents.save(new Incident("лента стоит", BORDER.plusSeconds(1200), "duty-2"));
        incidents.save(new Incident("письма копятся", BORDER, "duty-1"));
        Incident disk = incidents.save(new Incident("диск заполнен", BORDER.minusSeconds(1200), "duty-2"));
        Incident fixed = new Incident("стенд не отвечает", BORDER.minusSeconds(1800), "duty-1");
        fixed.fix(BORDER.minusSeconds(1500));
        incidents.save(fixed);

        assertThat(incidents.findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(BORDER))
                .extracting(Incident::getId)
                .containsExactly(disk.getId(), broker.getId());
    }
}
```

`IncidentColumnsIT` смотрит в столбцы мимо JPA. Первый тест пишет через
хранилище и читает SQL-ом: `queryForObject` — «выполни запрос и верни
одно значение такого типа». `?` в SQL — место для значения; значения
идут следующими аргументами `update` и `queryForObject`, по порядку,
и строки склеивать не нужно. Второй — наоборот: строку, вставленную
SQL-ом, JPA в памяти не держала, значит, `findById` прочитает её из базы.

`saveAndFlush` — «сохрани и сразу отправь в базу». Наш тест своей
транзакции не открывает (статья 3б), так что и `save` отправил бы строку
сразу. `saveAndFlush` делает тест независимым от этого: пометит
его кто-нибудь `@Transactional` — SQL-запрос всё равно увидит строку.

```java
// src/test/java/example/gameday/journal/IncidentColumnsIT.java
package example.gameday.journal;

import example.gameday.TestcontainersConfiguration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
@Import(TestcontainersConfiguration.class)
class IncidentColumnsIT {

    private static final Instant T0 = Instant.parse("2026-10-05T09:15:00Z");

    @Autowired
    private IncidentRepository incidents;

    @Autowired
    private JdbcTemplate jdbc;

    @AfterEach
    void cleanUp() {
        incidents.deleteAll();
    }

    @Test
    void storesSeverityAsCodeAndDetailsAsJsonb() {
        UUID id = incidents.saveAndFlush(new Incident("брокер молчит", T0, "duty-1",
                Severity.CRITICAL, Map.of("target", "broker", "attacker", "teamlead"))).getId();

        assertThat(jdbc.queryForObject(
                "SELECT severity FROM game_day.incident WHERE id = ?", String.class, id))
                .isEqualTo("critical");
        assertThat(jdbc.queryForObject(
                "SELECT details ->> 'target' FROM game_day.incident WHERE id = ?", String.class, id))
                .isEqualTo("broker");
    }

    @Test
    void readsRowWrittenBySql() {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO game_day.incident (id, title, detected_at, duty_name, severity, details)
                VALUES (?, 'диск заполнен', '2026-10-05T09:15:00Z', 'duty-2', 'high', '{"target": "disk"}')
                """, id);

        Incident read = incidents.findById(id).orElseThrow();

        assertThat(read.getSeverity()).isEqualTo(Severity.HIGH);
        assertThat(read.getDetails()).isEqualTo(Map.of("target", "disk"));
    }
}
```

**Порядок проверки** — из папки песочницы:

1. `./mvnw verify` — зелёный, вместе с тестами прошлых статей;
   `IncidentTableIT` из статьи 3а вставляет строку без новых столбцов —
   и проходит благодаря `DEFAULT`;
2. `@TestPropertySource(properties = "spring.jpa.show-sql=true")` над
   `IncidentAgeIT`, затем `./mvnw test -Dtest=IncidentAgeIT` — в строке
   `Hibernate: select …` есть `fixed_at is null` и `detected_at<?`,
   а в `Hibernate: insert …` — `severity` и `details`; аннотацию убери;
3. временный метод без `FixedAtIsNull` в `IncidentAgeIT` вместо
   настоящего — тест красный; метод удали;
4. база на минуту (статья 3а), `java -jar` с `SPRING_DATASOURCE_*` —
   в логе `Successfully applied 2 migrations`; в `psql` — вставка
   200 000 строк и `ANALYZE`, затем `EXPLAIN` — `Index Scan using
   ix_incident_open_detected`; без `fixed_at IS NULL` — `Seq Scan`;
   `docker stop game-day-db`.
