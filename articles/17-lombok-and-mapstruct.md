# Lombok и MapStruct: код, который пишут за тебя

> «От системы к делу» · статья 17 · читать минут 35
>
> **Для кого.** Ты прочитал статьи 0–16а, и у тебя есть песочница
> `game-day` после статьи 16а. Особенно пригодятся сущность (статья 3б)
> и ответ `IncidentResponse.of` (статья 4), строитель (статья 7),
> равенство записей и `HashSet` (статья 8).
>
> **Что будет.** Как Lombok дописывает в класс геттеры, конструкторы
> и строитель, пока класс компилируется, — и где это бьёт. Как MapStruct
> пишет перевод «сущность → ответ» и где лежит этот код. Чем за это
> платят и что из этого Java умеет сама.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От системы к делу» — следующий шаг
> после «От Spring к системе»: как правила дела — сроки, деньги,
> обещания людям — живут в коде. Примеры — учебные: их можно повторить
> у себя.

---

## Зачем: код, который никто не читает

Вспомни куски учебной CRM из прошлых статей. Служба лидов зовёт
`lead.getStatus()` и `lead.setStatus(…)` (статья 13), служба
продлений — `props.getDaysBefore()` (статья 15), сверка броней —
`task.getPersonId()` (статья 16). А в самих классах этих методов не
видно. Статья 15 так и сказала: геттеры и сеттеры класса настроек
дописывает при компиляции Lombok, а как и чего это стоит — в продолжении
серии. Вот оно.

**Lombok** дописывает в класс методы и конструкторы, пока класс
компилируется. У него есть сосед того же рода — **MapStruct**. Он пишет
**мапперы** (mapper): так называют классы, которые переводят объект
одного вида в другой, например сущность в ответ ручки. В службе есть
вызов `mapper.toResponse(lead)`, а реализации у метода в исходниках
нет: её пишет MapStruct.

В рабочих проектах команды встречается и то и другое. В одном Lombok
не берут вовсе: геттеры пишут руками, как у `Incident` в статье 3б.
Ответы там — записи с фабричным методом `of`, как `IncidentResponse.of`
в статье 4. В другом Lombok на каждом шагу.

Задача статьи — научить читать оба способа: видеть, что в коде
написано, а что дописано, и где дописанное ломается.

Решение, вокруг которого всё построено: **кто пишет однообразный код** —
ты руками, генератор при сборке или сам язык. У каждого ответа своя цена.

Сквозной пример — карточка лида на пути от строки таблицы к ответу
ручки. В учебной CRM этот путь — сущность `Lead` → маппер
`LeadResponseMapper` → ответ `LeadResponse`. Свой путь у статьи —
`LeadCard` → `LeadCardView`: сначала руками, чтобы увидеть, какую
работу берут на себя Lombok и MapStruct.

Куски учебной CRM клуба из статей 12–16а — для чтения, выброшенное в них
помечено `// …`. Код в них написан с Lombok и MapStruct. Свой код
статьи — карточка `LeadCard`, её вид снаружи `LeadCardView` и тест
`LeadCardTest`. Они на чистой Java, без Lombok, в пакете `example.crm`.

В коротких примерах нет строк `import` — полные файлы своего кода
в конце статьи.

---

## Часть 1. Карточка лида руками

### Шесть полей — полторы сотни строк

Возьмём шесть полей карточки лида из статьи 13: номер, имя, телефон,
статус, источник и когда пришёл. Напишем руками всё, что в учебной CRM
дописывает Lombok: пустой конструктор, конструктор на все поля, геттер
и сеттер на каждое поле и строитель (о нём ниже). Источник — откуда
лид пришёл: `"site"` значит заявку с сайта, `"call"` — звонок.

```java
public class LeadCard {

    private UUID id;
    private String firstName;
    private String phone;
    private String status;                       // по умолчанию "NEW" — как, увидим ниже
    private String source = "call";              // откуда лид; по умолчанию — звонок
    private Instant createdAt;

    public LeadCard() { … }                      // пустой конструктор
    public LeadCard(UUID id, String firstName, String phone,
                    String status, String source, Instant createdAt) { … }   // на все поля

    public String getPhone() {                   // геттер
        return phone;
    }

    public void setPhone(String phone) {         // сеттер
        this.phone = phone;
    }
    // … ещё пять пар — по одной на поле
}
```

Целиком файл занимает полторы сотни строк, а смысла в них — шесть
объявлений полей. У сущности лида учебной CRM полей почти вдвое
больше: в ней вся карточка из статьи 13. Руками вышло бы за две сотни
строк. Такой код никто не читает, поэтому ошибку в нём не видят:
сеттер `setPhone`, который после копипасты пишет в `messenger`, доживёт
до первой жалобы менеджера.

### Строитель: поля по именам

Строитель (builder) ты видел в статье 7: объект-помощник, у которого
зовёшь методы с именами полей в любом порядке, в конце — `build()`.

```java
LeadCard card = LeadCard.builder()     // новый строитель
        .firstName("Гость")            // каждое значение — с именем поля
        .source("site")
        .build();                      // собрать карточку
```

Зачем, если есть конструктор? Посмотри на
`new LeadCard(null, "Гость", null, null, "site", null)`: что из этого
телефон, а что статус?

В учебной CRM хуже. У задачи менеджеру `Task` из статьи 16 десять
полей. Конструктор на все поля (его тоже дописывает Lombok) принимает
десять значений подряд.

Четыре из них — `Instant`: срок задачи `dueAt`, срок брони `untilAt`,
когда задачу завели и когда закрыли. Среди них те самые два срока,
которые нельзя путать (статья 12). Ещё три — `UUID`: человек, группа
и номер брони. Поменяешь местами — компилятор промолчит: типы совпали.

Строитель называет каждое значение. Так служба броней заводит задачу
по строке опроса:

```java
// учебная служба броней: новая задача по строке опроса — сокращено
Instant now = clock.instant();
tasks.save(Task.builder()
        .kind(HOLD)                            // «довести до оплаты»
        .personId(row.personId())
        .groupId(row.groupId())
        .holdId(row.holdId())                  // номер брони — для ссылки на оплату
        .dueAt(now)                            // срок задачи: сейчас
        .untilAt(row.heldUntil())              // срок брони
        .note(holdNote(row))                   // текст задачи
        .createdAt(now)
        .build());
```

`row`, `holdNote` и `tasks` — строка ответа системы клуба `HoldRow`,
текст задачи и хранилище задач из статьи 16. Чего не передали,
строитель оставит пустым: `id` появится при сохранении,
а пустой `doneAt` и значит «задача открыта».

### Значение по умолчанию — отдельная забота

Новый лид — в статусе `NEW`. Для пустого конструктора хватило бы
`private String status = "NEW"`. Но строитель создаёт карточку
конструктором на все поля и передаёт туда **всё, что у него лежит**.
Статус не задали — у строителя там `null`, и `null` уйдёт в карточку.
Значит, строитель должен сам помнить, задавали ли поле:

```java
// в строителе LeadCardBuilder: рядом с полем status — boolean statusSet
public LeadCardBuilder status(String status) {
    this.status = status;
    this.statusSet = true;                                 // флажок: статус задали явно
    return this;                                           // вернуть строитель — для цепочки
}

public LeadCard build() {
    return new LeadCard(id, firstName, phone,
            statusSet ? status : LeadCard.defaultStatus(), // не задали — "NEW"
            source,                                        // не задали — null
            createdAt);
}
```

`defaultStatus()` — закрытый статический метод карточки, он отдаёт
`"NEW"`; пустой конструктор зовёт его же. Так значение по умолчанию
живёт в одном месте.

У поля `source` такого флажка нет — и `build()` без `.source(…)` даст
`null`, хотя в поле написано `"call"`. Запомни это расхождение: в части 2
оно окажется ловушкой Lombok.

---

## Часть 2. Lombok: то же самое — аннотациями

### Что это и как он работает

**Lombok** — библиотека, которая по аннотациям над классом дописывает
в него методы и конструкторы во время компиляции. Написал над классом
`@Getter` — в готовом `.class` есть геттеры, хотя в `.java` их нет.

Как это возможно. Компилятор `javac` умеет посреди компиляции запускать
**обработчики аннотаций** (annotation processors) — программы, которые
видят твои классы и их аннотации. По правилам Java обработчик может
только создавать **новые** файлы.

Lombok идёт дальше: он меняет сам
твой класс, пока компилятор держит его в памяти. Стандартного способа
для этого нет, и Lombok пользуется внутренними классами `javac`. Поэтому
каждая новая версия Java ждёт своей версии Lombok: поддержка Java 25
появилась в Lombok 1.18.40.

Боль, которую он снимает, — вся часть 1. Вот та же карточка на Lombok,
целиком:

```java
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class LeadCard {

    private UUID id;
    private String firstName;
    private String phone;
    @Builder.Default
    private String status = "NEW";
    private String source = "call";
    private Instant createdAt;
}
```

Пятнадцать строк вместо полутора сотен — а в `.class` те же
конструкторы, геттеры, сеттеры и строитель; строителю Lombok добавит
ещё `toString()`. Что значит каждая аннотация — ниже. В песочницу этот
вариант не клади: Lombok там нет, а `LeadCard` руками уже лежит
в `example.crm`.

### Откуда берётся в проекте

`pom.xml` учебной CRM, сокращено:

```xml
<!-- учебная CRM клуба: pom.xml — сокращено -->
<dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok</artifactId>
    <optional>true</optional>
</dependency>
<!-- … -->
<plugin>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-maven-plugin</artifactId>
    <configuration>
        <excludes>
            <exclude>
                <groupId>org.projectlombok</groupId>
                <artifactId>lombok</artifactId>
            </exclude>
        </excludes>
    </configuration>
</plugin>
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <annotationProcessorPaths>
            <path>
                <groupId>org.projectlombok</groupId>
                <artifactId>lombok</artifactId>
                <version>${lombok.version}</version>
            </path>
            <!-- … ещё два <path> — для MapStruct, в части 3 -->
        </annotationProcessorPaths>
    </configuration>
</plugin>
```

Что здесь важно:

* у зависимости нет версии — её подставляет родитель, «завхоз»
  из статьи 0. Spring Boot 4.1.1 даёт Lombok 1.18.46. Тот же номер
  родитель держит в свойстве `lombok.version`, и путь к обработчику
  берёт его оттуда — `${lombok.version}`;
* `<optional>true</optional>` — Lombok не передаётся дальше тем, кто
  подключит этот проект как библиотеку; а `<exclude>` у плагина Boot
  не кладёт его в готовый `.jar`: он нужен только компилятору,
  дописанные методы уже лежат в `.class`;
* `annotationProcessorPaths` — где `javac` искать обработчики.

⚠️ В интернете ты увидишь Lombok одной зависимостью, без
`annotationProcessorPaths`. Так работало до JDK 23: `javac` сам искал
обработчики среди библиотек проекта. Начиная с JDK 23 сам не ищет:
обработка аннотаций идёт, только если её попросили явно — путём
к обработчикам, их именами или ключом `-proc:full`. В инструкции Lombok
путь к обработчику с JDK 23 обязателен. В учебной CRM и в песочнице —
Java 25, и путь указан явно.

Без пути сборка падает не там, где ждёшь. Lombok молча не запустится,
`@Getter` останется просто надписью, и сама `LeadCard` соберётся. Упадут
те, кто зовёт `builder()` и геттеры: `cannot find symbol` — «такого
имени нет».

### Как запускается и где смотреть

Отдельно запускать не нужно: Lombok работает при каждой компиляции —
`./mvnw compile` или сборка в IDE. Но исходника с дописанными методами
нет нигде: они только в `.class`. Посмотреть можно так.

**`javap`** из JDK печатает, что лежит в `.class`. Попробуй на своей
карточке — в песочнице, после `./mvnw compile`:

```
$ javap -p -cp target/classes example.crm.LeadCard
Compiled from "LeadCard.java"
public class example.crm.LeadCard {
  private java.util.UUID id;
  …
  private static java.lang.String defaultStatus();
  public example.crm.LeadCard();
  …
  public java.lang.String getPhone();
  public void setPhone(java.lang.String);
  …
  public static example.crm.LeadCard$LeadCardBuilder builder();
}
```

Ключ `-p` показывает и закрытое (`private`), `-cp` говорит, где искать
классы, а `…` — пропущенные строки. `LeadCard$LeadCardBuilder` — так
в `.class` зовётся вложенный класс строителя. На классе с Lombok `javap` покажет
то же самое: методы, которых в `.java` нет.

**delombok** — режим самого Lombok, который пишет исходник «как без
Lombok»: `java -jar lombok.jar delombok src -d src-delomboked`.

IDEA понимает Lombok через плагин; в свежих версиях он встроен.
Настройки обработчиков IDEA берёт из `pom.xml` при импорте проекта.
Если IDEA подчёркивает `getFirstName()` красным, а `./mvnw compile`
проходит, — дело в IDE: проверь, что плагин Lombok включён и в настройках
компилятора включена обработка аннотаций.

### Что Lombok пишет

Аннотации, которые ты встретишь чаще всего:

| аннотация | что дописывает | где обычно стоит |
|---|---|---|
| `@Getter`, `@Setter` | `getX()` и `setX(…)` на каждое поле | сущности, классы настроек, запросы |
| `@NoArgsConstructor` | пустой конструктор, `public` | сущности, ответы |
| `@AllArgsConstructor` | конструктор на все поля по порядку | сущности со строителем, ответы |
| `@Builder` | строитель и `builder()` | сущности, ответы |
| `@RequiredArgsConstructor` | конструктор на все `final`-поля | службы, контроллеры |
| `@Slf4j` | поле-логгер `log` | службы |
| `@Data` | геттеры, сеттеры, конструктор на `final`-поля плюс `equals`, `hashCode`, `toString` | ответы и запросы |

Вот как это выглядит на сущности. Лид учебной CRM (статья 13),
сокращено:

```java
// учебная CRM клуба: сущность лида — сокращено
@Entity
@Table(name = "lead", schema = "sales")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Lead {

    @Id
    @GeneratedValue
    private UUID id;

    private String firstName;
    private String phone;
    private String messenger;
    private String email;
    // … источник, канал, интерес, менеджер, когда пришёл

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 32)
    private LeadStatus status;
}
```

Поле статуса — то самое из статьи 13. А методов в классе нет ни одного:
`getStatus()` и `setStatus(…)`, которые зовёт служба лидов, дописал
Lombok.

🔑 Читай аннотацию Lombok как код, записанный коротко. `@Builder` —
это «здесь строитель из части 1 со всеми его свойствами». В том числе
с тем, что значения по умолчанию он сам не знает.

### @RequiredArgsConstructor: внедрение, которого не видно

Служба лидов учебной CRM, начало класса:

```java
// учебная служба лидов — начало класса
@Service
@RequiredArgsConstructor
public class LeadService {

    private final LeadRepository leads;
    private final LeadResponseMapper mapper;
    private final LeadNotifier notifier;
    private final Clock clock;
```

Поля службы: хранилище лидов `leads`, маппер `mapper` из части 3,
оповещатель о смене статуса `notifier` из статьи 13 и часы бином `clock`
(статья 1).

Конструктора в тексте нет, но он есть в `.class`: четыре параметра
в том порядке, в каком объявлены поля, и в каждом —
`this.поле = параметр`. Это ровно внедрение через конструктор из
статьи 1: поля `final`, конструктор один, Spring зовёт его сам
и передаёт бины. Просто конструктор не написан, а дописан. Поле
без `final` в него не попадёт: `@RequiredArgsConstructor` берёт только
обязательные поля, те, что `final`.

Лог учебная CRM заводит руками, как журнал в статье 4:
`private static final Logger logger = LoggerFactory.getLogger(…)`.
В чужом коде ты часто встретишь `log.info(…)` без всякого поля `log`
в классе — ищи над классом `@Slf4j`. Он дописывает одну строку:

```java
private static final org.slf4j.Logger log =
        org.slf4j.LoggerFactory.getLogger(LeadService.class);
```

Имя у этого поля — `log`, а не `logger`, как в журнале.

### ⚠️ Три аннотации конструкторов — и все нужны

У сущностей учебной CRM со строителем три аннотации про конструкторы:
у `Lead` выше и у задачи `Task`. Каждая на месте.

* `@NoArgsConstructor` — JPA создаёт сущность пустой, а потом
  раскладывает по полям значения столбцов (как `protected Incident()`
  в 3б). Lombok делает этот конструктор `public`, так что пустую
  сущность можно создать откуда угодно; в журнале статьи 3б он
  `protected`, а сеттеров у `Incident` нет вовсе. Lombok умеет и так:
  `@NoArgsConstructor(access = AccessLevel.PROTECTED)`.
* `@Builder` на классе сам делает себе конструктор на все поля — но
  только если в классе нет других конструкторов. Пустой от
  `@NoArgsConstructor` уже есть, и строитель остался бы без своего:
  `build()` позовёт конструктор, которого нет, — сборка упадёт.
* Поэтому `@AllArgsConstructor` — явно, для строителя.

### ⚠️ @Builder.Default: строитель и значение по умолчанию

Вернись к карточке на Lombok: у `status` стоит `@Builder.Default`,
у `source` — нет. Это ровно случай из части 1: строитель передаёт
в конструктор всё, что у него лежит.

* **С `@Builder.Default`** — так у `status`. Lombok делает то же, что
  мы руками: выносит `"NEW"` в отдельный метод (у Lombok он зовётся
  `$default$status()`), заводит в строителе флажок `status$set`
  и подставляет `"NEW"`, если статус не задавали. Пустой конструктор
  от `@NoArgsConstructor` тоже ставит `"NEW"`. Конструктор, написанный
  тобой самим, — уже нет: там значение придётся ставить руками.
* **Без неё** — так у `source`. Строитель про `= "call"` не знает:
  `LeadCard.builder()` без `.source(…)` даст `source = null`, хотя
  в поле написано `"call"`.

Lombok об этом предупредит при сборке: «@Builder will ignore the
initializing expression entirely» — «строитель полностью проигнорирует
значение в поле». Но это **предупреждение**, а не ошибка: сборка
зелёная, и строку легко не заметить среди сотни других.

На сущности та же ловушка опаснее. Представь, что «новый лид — `NEW`»
перенесли из службы (статья 13) в поле сущности:
`private LeadStatus status = LeadStatus.NEW;` — а `@Builder.Default`
забыли. Лид, собранный строителем без `.status(…)`, придёт со статусом
`null`.

Столбец `status` в таблице лидов — `NOT NULL` (статья 13). Упадёт
сохранение, далеко от строки, где забыли статус. `DEFAULT 'NEW'`
из миграции не поможет: Hibernate называет в `INSERT` все столбцы,
и `null` уходит в базу явно. Так в учебной CRM **не** написано, статус
там ставит служба. Но в чужом коде такое встретишь.

На своей карточке обе половины держит тест в конце статьи: строитель
без `.status(…)` даёт `"NEW"`, `new LeadCard()` даёт источник `"call"`,
а строитель — `null`.

### ⚠️ Почему на сущностях нет @Data

`@Data` — пять аннотаций сразу: `@Getter`, `@Setter`, `@ToString`,
`@EqualsAndHashCode`, `@RequiredArgsConstructor`. В учебной CRM она
стоит на ответе `LeadResponse` (часть 3), а на сущностях — нет. И не
зря: у сущности три причины отказаться.

**`equals` и `hashCode` по всем полям.** Помнишь `HashSet` из статьи 8:
он ищет элемент по `hashCode`. У сущности меняются статус через
`setStatus(…)`, менеджер, канал, а с ними и `hashCode`. Положил лида
в `HashSet`, сменил статус — и множество его больше не находит. А `id`
появляется только при сохранении. Документация Hibernate говорит прямо:
изменяемые поля в `hashCode` не включать, и поля, которые выдаёт база,
тоже.

**Ленивые связи.** Заметки менеджера о разговоре (статья 12) учебная CRM
держит отдельной таблицей, по строке на заметку. Сущность заметки
`LeadNote`, сокращено:

```java
// учебная CRM клуба: заметка менеджера о разговоре — сокращено
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "lead_id", nullable = false)
private Lead lead;
```

`@ManyToOne` — «много заметок у одного лида»: в поле `lead` лежит сам
лид. `LAZY` значит «лида не загружать, пока не спросят»: Hibernate
кладёт в поле заместителя, и первый же вызов метода у него идёт в базу.
А если Hibernate уже отпустил этот объект — бросает
`LazyInitializationException`. `toString()` от `@Data` обходит все поля,
включая `lead`. Печать заметки в лог превратилась бы в запрос к базе
или в исключение.

🔴 **`toString()` печатает всё.** У `Lead` — телефон, мессенджер, почта.
`toString()` от Lombok выводит каждое поле:
`Lead(id=…, firstName=…, phone=…, messenger=…, …)`. Одна строка лога
с лидом — и личные данные лежат там, где их читают многие и хранят
долго (статья 8).

Своего `equals` у сущностей учебной CRM нет: лид равен только самому
себе, как `Incident` журнала.

### Классы настроек

Ещё одно место Lombok в учебной CRM — классы настроек из статьи 15:

```java
// учебная CRM клуба: настройки продления — начало класса
@Getter
@Setter
@Validated
@ConfigurationProperties(prefix = "club.sales.renewals")
public class RenewalsProperties {
```

Вот откуда у службы продлений `props.getDaysBefore()`, которого в классе
не видно. Это не запись, а обычный класс с сеттерами: Boot создаёт
объект пустым конструктором и раскладывает настройки через сеттеры
(статья 15). Документация Boot так и пишет: Lombok для геттеров
и сеттеров годится. Но особого конструктора он такому классу делать
не должен — объект создаёт сам Spring. Настройки журнала из статьи 2 —
запись: ей ни сеттеры, ни Lombok не нужны.

---

## Часть 3. MapStruct: перевод, который пишут за тебя

### Сущность — в ответ

Сущность наружу не отдают (статья 4): ответ — договор с клиентами,
а сущность повторяет таблицу. Значит, нужен перевод. Классы ответов
и запросов часто кладут в пакет `dto` — от **DTO** (data transfer
object, «объект для передачи данных»); в журнале ответ звался просто
`IncidentResponse`.

Перевод руками учебная CRM тоже пишет — в обратную сторону, из формы
в сущность. Служба лидов при создании (статья 13), сокращено:

```java
// учебная служба лидов, создание — сокращено
Lead lead = new Lead();
lead.setFirstName(form.firstName());
lead.setPhone(form.phone());
lead.setMessenger(form.messenger());
// … ещё четыре строки того же вида
lead.setStatus(LeadStatus.NEW);
```

А из сущности в ответ — MapStruct.

### Что это и откуда

**MapStruct** — обработчик аннотаций, который по интерфейсу с `@Mapper`
пишет при компиляции класс-реализацию. В отличие от Lombok, он делает
ровно то, что разрешено стандартом: создаёт **новый** файл и твой
не трогает. Маппер лида учебной CRM — целиком, без `import`:

```java
// учебная CRM клуба: маппер лида
@Mapper
public interface LeadResponseMapper {

    LeadResponse toResponse(Lead lead);
}
```

И ответ, в который он переводит, — тоже целиком:

```java
// учебная CRM клуба: ответ ручки лида
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class LeadResponse {

    private UUID id;
    private String firstName;
    private String phone;
    private String messenger;
    private String email;
    private String status;                       // в сущности — LeadStatus, здесь — строка
    private Instant createdAt;
}
```

В `pom.xml` у MapStruct две части: аннотации в зависимости `mapstruct`
и обработчик `mapstruct-processor`, второй путь
в `annotationProcessorPaths`. Версию учебная CRM задаёт сама: Boot
версией MapStruct не управляет.

```xml
<!-- учебная CRM клуба: pom.xml, MapStruct — сокращено -->
<properties>
    <mapstruct.version>1.6.3</mapstruct.version>
</properties>
<!-- … -->
<dependency>
    <groupId>org.mapstruct</groupId>
    <artifactId>mapstruct</artifactId>
    <version>${mapstruct.version}</version>
</dependency>
<!-- … в annotationProcessorPaths — после пути к Lombok из части 2 -->
<path>
    <groupId>org.mapstruct</groupId>
    <artifactId>mapstruct-processor</artifactId>
    <version>${mapstruct.version}</version>
</path>
<path>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok-mapstruct-binding</artifactId>
    <version>0.2.0</version>
</path>
<!-- … и рядом с annotationProcessorPaths, в той же configuration -->
<compilerArgs>
    <arg>-Amapstruct.defaultComponentModel=spring</arg>
</compilerArgs>
```

Третий путь и ключ `-A…` — ниже.

### Где лежит код и как его читать

Тут MapStruct удобнее Lombok: его код — обычный файл, который можно
открыть. После `./mvnw compile` он лежит
в `target/generated-sources/annotations/`, в той же папке пакета, что
и интерфейс. Имя — имя интерфейса и `Impl` на конце. Так MapStruct
пишет реализацию маппера лида, сокращено:

```java
// так MapStruct пишет реализацию маппера лида — сокращено
@Generated(…)                                                     // «написано генератором»
@Component                                                        // бин Spring — ниже
public class LeadResponseMapperImpl implements LeadResponseMapper {

    @Override
    public LeadResponse toResponse(Lead lead) {
        if ( lead == null ) {
            return null;
        }

        LeadResponse.LeadResponseBuilder leadResponse = LeadResponse.builder();   // строитель от Lombok

        leadResponse.id( lead.getId() );                              // одинаковые имена — сами
        leadResponse.firstName( lead.getFirstName() );
        // … ещё три поля с одинаковыми именами
        if ( lead.getStatus() != null ) {
            leadResponse.status( lead.getStatus().name() );           // перечисление → строка
        }
        leadResponse.createdAt( lead.getCreatedAt() );

        return leadResponse.build();
    }
}
```

Пробелы внутри скобок, как в `( lead == null )`, ставит сам MapStruct:
руками так обычно не пишут, и по ним сгенерированный файл видно сразу.
Править его бесполезно — следующая сборка напишет файл заново.

Правила, по которым он пишет:

* поле с тем же именем — переносится само; перечисление в строку —
  через `name()`, с проверкой на `null`;
* разные имена — аннотацией `@Mapping`. Маппер заметок учебной CRM:

  ```java
  // учебная CRM клуба: маппер заметок
  @Mapper
  public interface LeadNoteMapper {

      @Mapping(target = "leadId", source = "lead.id")
      @Mapping(target = "text", source = "body")
      LeadNoteResponse toResponse(LeadNote note);
  }
  ```

  В `@Mapping` атрибут `target` называет поле ответа, `source` — откуда брать,
  а `lead.id` значит «у поля `lead` взять `id`». Ответ заметки — запись
  `LeadNoteResponse(UUID id, UUID leadId, String text, Instant createdAt)`:
  в записи MapStruct тоже пишет — через их конструктор;
* перевод, которого MapStruct не знает, — свой `default`-метод: метод
  с телом прямо в интерфейсе. MapStruct зовёт его везде, где типы
  совпали. В учебной CRM время — `Instant`, и `Instant` в ответ уходит
  как есть. А в чужом коде ты встретишь такой метод:

  ```java
  // учебный маппер: так бывает в чужом коде — в сущности OffsetDateTime, в ответе LocalDateTime
  default LocalDateTime map(OffsetDateTime time) {
      return time != null ? time.toLocalDateTime() : null;
  }
  ```

  Встроенного перевода из `OffsetDateTime` в `LocalDateTime`
  у MapStruct нет, и кто-то написал свой. ⚠️ `toLocalDateTime()`
  отбрасывает пояс: остаются «часы на стене» из статьи 3а, и по ответу
  уже не скажешь, какой это момент:

  ```java
  OffsetDateTime moscow = OffsetDateTime.parse("2026-10-05T12:15+03:00");
  OffsetDateTime utc = OffsetDateTime.parse("2026-10-05T09:15Z");
  moscow.isEqual(utc);                                        // true: один и тот же момент
  moscow.toLocalDateTime().equals(utc.toLocalDateTime());     // false: 12:15 и 09:15
  ```

  `isEqual` сравнивает моменты, а у `LocalDateTime` момента нет —
  только «часы на стене»;
* поле есть в ответе, но нет в сущности, — MapStruct оставит его пустым
  и **предупредит** при сборке. Скажем, в ответе поле назвали `name`,
  а в сущности оно `firstName`: в выводе сборки будет
  `Unmapped target property: "name".`, а в ответе — `null`;
* поле есть в сущности, но нет в ответе, — пропустит **молча**. У `Lead`
  есть источник, канал, интерес и менеджер, у `LeadResponse` их нет —
  и это никак не отмечено.

### Маппер — бин

В `pom.xml` есть строка `<arg>-Amapstruct.defaultComponentModel=spring</arg>`
— настройка обработчика: ключ `-A` передаёт её через `javac`. С ней
MapStruct ставит на реализацию аннотацию `@Component`, и она становится
бином. Дальше всё знакомо: в службе лидов поле
`private final LeadResponseMapper mapper`, конструктор от
`@RequiredArgsConstructor`, Spring передаёт туда сгенерированную
реализацию. Без этой настройки `@Component` нет, и маппер достают
вызовом `Mappers.getMapper(LeadResponseMapper.class)` — так в первых
примерах документации MapStruct.

### lombok-mapstruct-binding: два обработчика договариваются

Третий `<path>` в `annotationProcessorPaths` — `lombok-mapstruct-binding`.
Это не обработчик, а дополнение к MapStruct. Зачем он: оба обработчика
работают в одной компиляции. MapStruct смотрит на `Lead`
и `LeadResponse` и ищет геттеры и `builder()` — а их ещё нужно
дописать Lombok. Если MapStruct успел раньше, он видит класс без
этих методов — и сборка падает с ошибками компиляции.

`lombok-mapstruct-binding` — маленький посредник. MapStruct спрашивает
его про каждый класс: «Lombok с ним закончил?». Пока нет — MapStruct
откладывает маппер на следующий круг: компилятор повторяет обработку,
пока обработчики создают новые файлы. Нужен посредник с Lombok
1.18.16; без него, как пишет документация MapStruct, MapStruct
с Lombok перестаёт работать.

---

## Часть 4. Цена — и что Java даёт сама

### Чем платят за код, который пишут за тебя

* **Кода не видно.** Поиск по тексту не найдёт `getFirstName` в `Lead`.
  Чтобы прочитать дописанное, нужны `javap`, delombok или плагин
  в IDE.
* **Ловушки молчат.** Строитель без `@Builder.Default` и пустое поле
  ответа — предупреждения; пропущенное поле сущности — тишина. Сборка
  зелёная.
* **Сборка держится на договорённостях.** Два обработчика согласуются
  через посредника, Lombok — через внутренности `javac`. Новая Java —
  сначала ждёшь новый Lombok.
* **IDE без плагина** видит ошибки там, где их нет.

MapStruct из двух дешевле: его код — обычный файл, его можно открыть
и прочитать. Но правило «по одинаковым именам» неявное: переименовал
поле в сущности — и поле ответа осталось пустым, а MapStruct отметит
это предупреждением, не ошибкой.

### Записи: то, что Java умеет сама

Записи (статьи 0 и 8) дают даром конструктор, методы чтения, `equals`,
`hashCode` и `toString`. Для ответов это почти всё, что даёт
`@Data`. Чего запись не даёт: сеттеров (она неизменяема), строителя,
логгера. И сущностью быть не может (статья 3б).

В рабочих проектах команды — оба диалекта. В проекте без Lombok перевод
в ответ — фабричный метод `of` у записи, как `IncidentResponse.of`
в статье 4; причину правило «без Lombok» не называет. В проекте
с Lombok рядом с `@Data` встречаются и записи — там, где ответ проще
записать записью: проект говорит на двух диалектах, и новый код пишут
так, как написан соседний. Что даёт запись с `of` на деле, видно
на нашей карточке:

```java
public record LeadCardView(UUID id, String name, String status, String source, Instant createdAt) {

    public static LeadCardView of(LeadCard card) {
        return new LeadCardView(card.getId(), card.getFirstName(), card.getStatus(),   // firstName → name
                card.getSource(), card.getCreatedAt());                               // телефона нет
    }
}
```

* Весь перевод — в тексте. Переименование `firstName` → `name` видно
  глазами, без `@Mapping`.
* Что не перечислил — наружу не уйдёт. Телефона в `LeadCardView` нет,
  и никакое правило имён его туда не добавит.
* Добавил в запись поле — компилятор не соберёт `of`, пока ты не решишь,
  откуда его взять. MapStruct в том же случае только предупредит.

Запись и печатает себя сама. Карточка из строителя с именем `"Гость"`
и источником `"site"` снаружи выглядит так:

```
LeadCardView[id=null, name=Гость, status=NEW, source=site, createdAt=null]
```

Квадратные скобки — так печатает запись (статья 8). `toString()` от
Lombok, будь то `@ToString` или `@Data`, ставит круглые:
`LeadCard(id=null, firstName=Гость, phone=null, …)`.
Телефона в записи нет — его не будет ни в ответе, ни в строке лога.
А у нашей `LeadCard` своего `toString()` нет: она печатает имя класса,
`@` и шестнадцатеричное число — `example.crm.LeadCard@` и хвост, у каждого
объекта свой.

🔑 Код, который пишут за тебя, — всё равно твой код. Читай аннотации
как текст, знай, где лежит дописанное, и проверяй его тестом.

### Тест на ловушку

Последнее — проверить ловушку из части 2 на своей карточке.

```java
    @Test
    void builderKeepsDefaultStatus() {                                 // как @Builder.Default
        LeadCard card = LeadCard.builder().firstName("Гость").build();

        assertThat(card.getStatus()).isEqualTo("NEW");
    }

    @Test
    void builderForgetsSourceWithoutDefault() {                        // инициализатор без @Builder.Default
        LeadCard byConstructor = new LeadCard();
        LeadCard byBuilder = LeadCard.builder().firstName("Гость").build();

        assertThat(byConstructor.getSource()).isEqualTo("call");
        assertThat(byBuilder.getSource()).isNull();                    // строитель про "call" не знает
    }
```

Убери из `build()` флажок `statusSet` — и первый тест покраснеет:
`expected: "NEW"`, `but was: null`. Ещё два теста в конце статьи
проверяют `of` и равенство. Две карточки с одинаковыми полями не равны:
своего `equals` нет, как у сущности. А две записи `LeadCardView` равны.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что такое обработчик аннотаций? Чем Lombok отличается от MapStruct
   по тому, что он делает с твоим кодом?
2. Почему в `pom.xml` учебной CRM Lombok указан
   в `annotationProcessorPaths`, а в старых туториалах хватало одной
   зависимости? Что сломается без пути на Java 25 — и где?
3. `LeadCard.builder()` без `.status(…)` и без `.source(…)`: что будет
   в `status` и в `source`? А у `new LeadCard()`? Что меняет
   `@Builder.Default`?
4. Зачем сущностям учебной CRM со строителем три аннотации про
   конструкторы? Что сломается, если убрать `@AllArgsConstructor`?
5. Чем опасна `@Data` на сущности? Объясни на `Lead` и `LeadNote`.
6. Где лежит реализация `LeadResponseMapper` и как она попадает в службу
   лидов?
7. Поле есть в ответе, но нет в сущности. Что сделает MapStruct?
   А наоборот?
8. Что даёт запись с `of` по сравнению с `@Data` и маппером — и чего
   не даёт?

---

## Что дальше

Дальше в серии — второй разговор о самом коде: миграции, которые помнят
решения. Как схема хранит историю того, что передумали, и почему
применённую миграцию не правят, а пишут новую.

## Первоисточники

* [Lombok: @Builder](https://projectlombok.org/features/Builder) —
  что пишет строитель, `@Builder.Default` и мелкий шрифт про конструкторы;
* [Lombok: Maven](https://projectlombok.org/setup/maven) — подключение
  и почему `annotationProcessorPaths` обязателен с JDK 23;
* [MapStruct Reference Guide](https://mapstruct.org/documentation/stable/reference/html/) —
  `@Mapping`, `default`-методы, `componentModel`, раздел о Lombok;
* [A Short Guide to Hibernate 7](https://docs.hibernate.org/orm/7.4/introduction/html_single/#equals-and-hash) —
  раздел «equals() and hashCode()»: какие поля сущности нельзя класть
  в `hashCode` и почему;
* [JEP 395: Records](https://openjdk.org/jeps/395) — что записи дают
  сами.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 16а: журнал
в `example.gameday.journal` со всем, что накопили статьи 1–10, сторожа
статьи 11, модель статей 12–16а в `example.crm` и её тесты, Postgres
в контейнере, охрана, Actuator и стенд — всё остаётся, менять ничего
не нужно. В `pom.xml` ничего не добавляй: ни Lombok, ни MapStruct
коду статьи не нужны — в этом и смысл. `LeadCard` написан руками так, как его написал бы
Lombok по аннотациям `@Getter`, `@Setter`, `@NoArgsConstructor`,
`@AllArgsConstructor` и `@Builder`, а у поля `status` стояло бы
`@Builder.Default`. JUnit и AssertJ — со `spring-boot-starter-test`.

Что добавить: в `src/main/java/example/crm/` — `LeadCard` (карточка
лида руками, со строителем) и `LeadCardView` (что карточка показывает
наружу), в `src/test/java/example/crm/` — `LeadCardTest`. Пакет
`example.crm` — рядом с `example.gameday`, не внутри: сканирование
Spring его не видит, а сторож статьи 11 смотрит только в папку журнала.
Куски учебной CRM — для чтения, в песочницу их не клади: сущности,
службы, мапперы, ответы, `pom.xml`. То же с карточкой на Lombok
из части 2.

Запуск: треугольником у класса в IDE или
`./mvnw test -Dtest=LeadCardTest`; весь `./mvnw verify` гоняет и `*IT` —
нужен запущенный Docker. Путь к файлу — комментарием в первой строке.

```java
// src/main/java/example/crm/LeadCard.java
package example.crm;

import java.time.Instant;
import java.util.UUID;

/**
 * Карточка лида, написанная руками так, как её написал бы Lombok по аннотациям
 * {@code @Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder}; у поля status стояло бы
 * {@code @Builder.Default}, у поля source — нет. Учебная модель.
 */
public class LeadCard {

    private UUID id;
    private String firstName;
    private String phone;
    private String status;                       // было: @Builder.Default private String status = "NEW";
    private String source = "call";              // без @Builder.Default: строитель об этом значении не знает
    private Instant createdAt;

    // @Builder.Default: значение по умолчанию переехало из поля в метод; у Lombok — $default$status()
    private static String defaultStatus() {
        return "NEW";
    }

    // @NoArgsConstructor
    public LeadCard() {
        this.status = defaultStatus();
    }

    // @AllArgsConstructor
    public LeadCard(UUID id, String firstName, String phone,
                    String status, String source, Instant createdAt) {
        this.id = id;
        this.firstName = firstName;
        this.phone = phone;
        this.status = status;
        this.source = source;
        this.createdAt = createdAt;
    }

    // @Getter и @Setter: по паре методов на каждое поле

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public String getFirstName() {
        return firstName;
    }

    public void setFirstName(String firstName) {
        this.firstName = firstName;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    // @Builder

    public static LeadCardBuilder builder() {
        return new LeadCardBuilder();
    }

    public static class LeadCardBuilder {

        private UUID id;
        private String firstName;
        private String phone;
        private String status;
        private boolean statusSet;               // задавали ли status; у Lombok это поле status$set
        private String source;
        private Instant createdAt;

        LeadCardBuilder() {
        }

        public LeadCardBuilder id(UUID id) {
            this.id = id;
            return this;
        }

        public LeadCardBuilder firstName(String firstName) {
            this.firstName = firstName;
            return this;
        }

        public LeadCardBuilder phone(String phone) {
            this.phone = phone;
            return this;
        }

        public LeadCardBuilder status(String status) {
            this.status = status;
            this.statusSet = true;
            return this;
        }

        public LeadCardBuilder source(String source) {
            this.source = source;
            return this;
        }

        public LeadCardBuilder createdAt(Instant createdAt) {
            this.createdAt = createdAt;
            return this;
        }

        public LeadCard build() {
            return new LeadCard(id, firstName, phone,
                    statusSet ? status : LeadCard.defaultStatus(),   // не задали — значение по умолчанию
                    source,                                          // не задали — null
                    createdAt);
        }

        // Lombok добавляет строителю ещё toString(); здесь он опущен
    }
}
```

```java
// src/main/java/example/crm/LeadCardView.java
package example.crm;

import java.time.Instant;
import java.util.UUID;

/** Что карточка показывает наружу. Телефона здесь нет — значит, наружу он не уйдёт. Учебная модель. */
public record LeadCardView(UUID id, String name, String status, String source, Instant createdAt) {

    public static LeadCardView of(LeadCard card) {
        return new LeadCardView(card.getId(), card.getFirstName(), card.getStatus(),   // firstName → name
                card.getSource(), card.getCreatedAt());                               // телефона нет
    }
}
```

```java
// src/test/java/example/crm/LeadCardTest.java
package example.crm;

import java.time.Instant;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class LeadCardTest {

    private static final UUID ID = UUID.fromString("7f3c2a10-0000-4000-8000-000000000017");
    // Понедельник, 5 октября 2026, 12:15 по Москве.
    private static final Instant CREATED = Instant.parse("2026-10-05T09:15:00Z");

    @Test
    void builderKeepsDefaultStatus() {                                 // как @Builder.Default
        LeadCard card = LeadCard.builder().firstName("Гость").build();

        assertThat(card.getStatus()).isEqualTo("NEW");
    }

    @Test
    void builderForgetsSourceWithoutDefault() {                        // инициализатор без @Builder.Default
        LeadCard byConstructor = new LeadCard();
        LeadCard byBuilder = LeadCard.builder().firstName("Гость").build();

        assertThat(byConstructor.getSource()).isEqualTo("call");
        assertThat(byBuilder.getSource()).isNull();                    // строитель про "call" не знает
    }

    @Test
    void viewTakesOnlyListedFields() {
        LeadCard card = LeadCard.builder()
                .id(ID).firstName("Гость").phone("+7 900 000-00-00")
                .source("site").createdAt(CREATED)
                .build();

        assertThat(LeadCardView.of(card))
                .isEqualTo(new LeadCardView(ID, "Гость", "NEW", "site", CREATED));
    }

    @Test
    void cardsAreNotEqualViewsAre() {
        LeadCard one = LeadCard.builder().id(ID).firstName("Гость").build();
        LeadCard two = LeadCard.builder().id(ID).firstName("Гость").build();

        assertThat(one).isNotEqualTo(two);                             // своего equals нет — как у сущности
        assertThat(LeadCardView.of(one)).isEqualTo(LeadCardView.of(two));
    }
}
```

**Порядок проверки** — из папки песочницы:

1. `./mvnw test -Dtest=LeadCardTest` — 4 запуска, все зелёные;
   `./mvnw verify` — зелёный вместе с тестами прошлых статей —
   `TodayListTest`, `FunnelNumbersTest`, `CheckoutTest`, `RublesTest`,
   `ReminderPointTest` и `PaidSweepTest`, у сторожа статьи 11
   по-прежнему 43 запуска: в папку журнала новые классы не попали,
   миграций не прибавилось;
2. `javap -p -cp target/classes example.crm.LeadCard` — поля,
   `defaultStatus()`, оба конструктора, геттеры и сеттеры и `builder()`,
   как в части 2;
3. что будет, если: убрать флажок из `build()` — `status` вместо
   `statusSet ? status : LeadCard.defaultStatus()` — красные
   `builderKeepsDefaultStatus` (`expected: "NEW"`, `but was: null`)
   и `viewTakesOnlyListedFields`; дать строителю `source = "call"`
   в поле — как будто поставили `@Builder.Default` — красный
   `builderForgetsSourceWithoutDefault`; строитель `phone(…)` после
   копипасты пишет в `firstName` — красный `viewTakesOnlyListedFields`,
   в имени телефон; `equals` и `hashCode` у `LeadCard` по всем полям,
   как от `@Data`, — красный `cardsAreNotEqualViewsAre`; новое поле
   `phone` в `LeadCardView`, а `of` не тронут — не собирается, javac
   пишет `constructor LeadCardView in record LeadCardView` и дальше
   `cannot be applied to given types`;
4. 💡 карточка на Lombok из части 2 — не в песочнице, а в отдельном
   проекте с Lombok и путём к обработчику: тот же `LeadCardTest`
   зелёный, `javap` показывает те же методы, а сборка предупреждает
   про `source`.
