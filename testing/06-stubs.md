# Когда вокруг твоего кода другой код

> «От красного к зелёному» · статья 6 · читать минут 30
>
> **Для кого.** Ты прочитал статьи 1–5 этой серии: у тебя есть песочница
> `testy` с зачётом по сроку, ты выбираешь случаи и ломаешь код руками,
> чтобы проверить тест. Серия «От Java к Spring Boot» не нужна.
>
> **Что будет.** Как проверить службу, которой нужны база, чужой сервис
> и часы, — заглушками руками и Mockito; как подменить «сейчас»; что
> подменять, а что нет.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От красного к зелёному» — как
> работать с тестами на проекте: писать их, читать красную сборку
> и верить зелёному тесту, только если видел его красным. Примеры —
> учебные: их можно повторить у себя.

---

## Зачем заглушки

Всё, что мы проверяли до сих пор, — `DeadlineScore`: на входе два
момента времени, на выходе число. Ни базы, ни сети, ни часов. Такой код
называют **чистой логикой**: результат зависит только от входа, и тест
вызывает его напрямую.

На проекте такого кода меньше, чем хочется. Правило зачёта само по себе
никому не нужно: кто-то должен узнать, когда задачу сдали, взять её срок,
посчитать балл и записать его. Это работа **службы** — класса, который
соединяет логику с соседями. Соседи у службы почти всегда есть:
хранилище, часы, клиент другого сервиса.

Как проверить службу, которая в работе ходит в базу? Можно поднять базу,
положить строку, вызвать службу и заглянуть в таблицу. Тест станет
медленным, будет зависеть от чужих данных и упадёт, когда база
недоступна, хотя твой код ни при чём. А случай «прошли сутки» пришлось
бы ждать сутки.

Выход — заглушка. Она уже мелькнула в тесте доли из
[статьи 5 «Тест, который ничего не проверяет»](https://hammerhall.io/ledger/testing/5-test-that-checks-nothing):
объект, который в тесте стоит на месте настоящего соседа и отвечает то,
что ему велели. Как дублёр на репетиции: подаёт нужную реплику в нужный момент,
а всю роль сыграть не умеет. В книгах встретишь «стаб», «мок», «фейк»,
«тестовый двойник» с тонкими различиями. В серии, как и в рабочем
проекте, одно слово — заглушка.

С заглушками тест службы остаётся модульным (статья 1): один класс,
без базы, сети и Spring. В задачах рабочего проекта встречаются пометки
«без Spring», «хранилище — заглушка Mockito», `Clock.fixed`. После этой
статьи понятно каждое слово.

**Сквозной пример — служба зачёта `ScoreService`.** Сначала заглушки
напишем руками, без библиотек, чтобы увидеть, что у них внутри. Потом
то же самое сделает Mockito: так тесты служб обычно и пишут на работе.

---

## Часть 1. Служба и её соседи

### Соседи — интерфейсы

У службы три соседа: журнал сдачи, сроки и доска зачётов. И ещё часы.
В работе за журналом и доской стоит база, за сроками — чужой сервис.
Каждый сосед описан **интерфейсом** — списком методов без реализации.
Интерфейс говорит «что», а «как» решает класс, который его реализует
(`implements`): в работе настоящий, в тесте — заглушка.

Три интерфейса — три файла. В коротких примерах нет строк `package`
и `import`, полные файлы — в конце статьи.

```java
public interface SubmissionLog {

    /** Когда студент сдал задачу; не сдавал — пусто. */
    Optional<Instant> submittedAt(String studentId, String taskKey);
}

public interface Deadlines {

    Instant deadlineOf(String taskKey);
}

public interface ScoreBoard {

    void record(String studentId, String taskKey, int score);
}
```

`Optional<Instant>` — «может быть, момент времени»: коробка, в которой
значение либо есть, либо пусто. В угловых скобках — что может лежать
в коробке. Так метод честно говорит «студент мог и не сдать» и вместо
`null` возвращает пустую коробку: `Optional.empty()`. Коробка со
значением — `Optional.of(…)`; пуста ли — `isEmpty()`; достать
значение — `get()`.

### Служба

```java
public class ScoreService {

    private final SubmissionLog log;
    private final Deadlines deadlines;
    private final ScoreBoard board;
    private final Clock clock;                                  // «сейчас» — только отсюда

    public ScoreService(SubmissionLog log, Deadlines deadlines, ScoreBoard board, Clock clock) {
        // … запоминает соседей в поля
    }

    public Optional<Integer> grade(String studentId, String taskKey) {
        Instant deadline = deadlines.deadlineOf(taskKey);
        Optional<Instant> submittedAt = log.submittedAt(studentId, taskKey);

        if (submittedAt.isEmpty()) {
            Instant lastChance = deadline.plus(DeadlineScore.GRACE);
            if (clock.instant().isAfter(lastChance)) {          // сдать на половину уже нельзя
                board.record(studentId, taskKey, DeadlineScore.NONE);
                return Optional.of(DeadlineScore.NONE);
            }
            return Optional.empty();                            // ещё не поздно — не трогаем
        }

        int score = DeadlineScore.score(deadline, submittedAt.get());
        board.record(studentId, taskKey, score);
        return Optional.of(score);
    }
}
```

Три пути. Сдал — балл по правилу, запись на доску. Не сдал, а сутки
после срока прошли — ноль, тоже на доску. Не сдал, но ещё не поздно —
пусто, доску не трогаем. `GRACE` — те самые сутки из `DeadlineScore`:
служба лежит в том же пакете и видит их.

Посчитать балл служба не умеет, это делает `DeadlineScore`, и его
проверяют тесты статей 2–5. У теста службы свои вопросы: выбран ли
верный путь, что служба вернула и что записала на доску.

Главное здесь — конструктор. Служба не создаёт ни соседей, ни часы сама
и не знает, кто на том конце: база или заглушка. Их передают снаружи,
значит, тест может передать свои.

---

## Часть 2. Заглушки руками

### Лямбда: заглушка в одну строку

Заглушку для `Deadlines` можно написать классом: `implements Deadlines`,
метод, который возвращает срок. Пять строк ради одного ответа. Есть
запись короче. Интерфейс, у которого ровно один метод без реализации,
называют **функциональным**, и его объект можно записать лямбдой, как
в `assertThatThrownBy` из статьи 4.

```java
private final Deadlines deadlines = taskKey -> DEADLINE;                     // у всех задач один срок
```

Читается так: «на вопрос о сроке любой задачи отвечай `DEADLINE`».
`DEADLINE` — константа срока, как в статье 2. Параметры лямбды — это
параметры того единственного метода, а её результат и есть его ответ. Какой
интерфейс имеется в виду, Java понимает по типу переменной. Два
параметра пишут в скобках:

```java
SubmissionLog log = (studentId, taskKey) -> Optional.of(DEADLINE.plus(Duration.ofHours(2)));
```

«Кого бы ни спросили, сдал через два часа после срока».

### Заглушка, которая запоминает

С доской так не выйдет. `record` ничего не возвращает (`void`). Лямбда
могла бы принять вызов, но тест не узнает, что записали. Нужна заглушка
с памятью:

```java
/** Доска, которая запоминает, что на неё записали. */
static class RememberingBoard implements ScoreBoard {

    final List<String> records = new ArrayList<>();

    @Override
    public void record(String studentId, String taskKey, int score) {
        records.add(studentId + " " + taskKey + " " + score);
    }
}
```

Это класс внутри класса теста; `static` — ему не нужен объект теста.
`@Override` говорит: «метод из интерфейса». Ошибёшься в имени —
компилятор подскажет. Каждый вызов кладёт в список строку вроде
`student-1 T-7 50`: строкой — чтобы в красном отчёте её было легко
прочитать.

### Часы: «сейчас» приходит снаружи

Третий путь, «не сдал, а сутки прошли», зависит от «сейчас». Если бы
служба брала его из `Instant.now()`, тест получил бы настоящий момент
запуска. Чтобы проверить «через 25 часов после срока», пришлось бы
ждать 25 часов. Или считать срок от «сейчас», и тогда тест каждый день
значил бы немного другое. Та же беда, что с часовым поясом в статье 3:
итог зависит от того, где и когда запустили.

**`Clock`** — класс из `java.time`: объект, который отвечает «который
час» (`clock.instant()`). Его документация прямо говорит, зачем он:
чтобы можно было подставить другие часы, и это упрощает тесты. В работе
часы настоящие, системные. В тесте — **`Clock.fixed(момент, пояс)`**:
остановленные часы, которые всегда показывают одно и то же. Пояс
`ZoneOffset.UTC` здесь формальность: мы спрашиваем только `Instant`,
а у него пояса нет.

В рабочем проекте это правило: «сейчас» код берёт только из `Clock`,
а часы получает через конструктор. На другом примере часы и заглушку
руками разбирает [статья 1 «Зачем Spring»](https://hammerhall.io/ledger/articles/1-why-spring)
цикла «От Java к Spring Boot».

### Тесты

Вспомогательный метод собирает службу из заглушек и остановленных часов
на нужный момент; `deadlines` — та самая лямбда выше:

```java
private final RememberingBoard board = new RememberingBoard();

private ScoreService serviceAt(Instant now, SubmissionLog log) {
    return new ScoreService(log, deadlines, board, Clock.fixed(now, ZoneOffset.UTC));
}

@Test
void notSubmittedYetIsNotGraded() {
    SubmissionLog log = (studentId, taskKey) -> Optional.empty();
    ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(3)), log);   // сутки ещё не прошли

    Optional<Integer> score = service.grade("student-1", "T-7");

    assertThat(score).isEmpty();
    assertThat(board.records).isEmpty();
}

@Test
void notSubmittedAfterGraceGetsNothing() {
    SubmissionLog log = (studentId, taskKey) -> Optional.empty();
    ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(25)), log);  // сутки прошли

    Optional<Integer> score = service.grade("student-1", "T-7");

    assertThat(score).contains(0);
    assertThat(board.records).containsExactly("student-1 T-7 0");
}
```

Доска — поле класса теста, но тесты не мешают друг другу. JUnit создаёт
новый объект теста перед каждым тестовым методом (статья 2), и каждый
начинает с пустой доской. Проверки AssertJ здесь такие:

* `contains(0)` — «в коробке ноль»;
* `isEmpty()` — «пусто»;
* `containsExactly(…)` — «в списке ровно это, и больше ничего».

Три часа и двадцать пять — две стороны границы, как в статье 4.

Третий тест, `submittedLateWithinDayGetsHalf`, проверяет путь «сдал»:
балл 50, и на доске `student-1 T-7 50`. Зачем проверять и ответ, и доску?
Вычеркни из службы строку `board.record(studentId, taskKey, score);`
после подсчёта балла. Ответ останется верным — 50, а тест покраснеет
на второй проверке: на доску ничего не попало. Без неё ошибку не увидел
бы никто.

А теперь замени в службе `clock.instant()` на `Instant.now()`. Один из
двух тестов выше покраснеет, но какой — решает календарь. До 13.10.2026
21:00 UTC (срок плюс сутки) красный `notSubmittedAfterGraceGetsNothing`:
настоящие сутки ещё не прошли. После — `notSubmittedYetIsNotGraded`:
они уже прошли. Проверить код с `Instant.now()` на оба случая нельзя
вовсе.

Верни службу как было. Тесты покраснели на настоящих ошибках, и их
зелёному теперь можно верить: **зелёному тесту верят, только если
видели его красным.**

🔑 **Всё, что код берёт снаружи, он должен получать через конструктор:
базу, сеть, часы.** Тогда тест подставит заглушку, и ему не нужно
ни ждать, ни поднимать базу.

---

## Часть 3. Mockito

### Что это и откуда

Заглушки руками хороши, пока соседей мало. У службы на работе их бывает
пять и больше. Каждому нужен свой класс вроде `RememberingBoard`,
а каждому тесту — свои ответы.

**Mockito** — библиотека, которая делает заглушку любого интерфейса или
класса одной строкой. Заглушке велят, что отвечать, а потом проверяют,
как её звали. Позвали не так — тест красный. В курсах Mockito обычно
нет, а на работе он почти в каждом тесте службы.

Статья 1 обещала рассказать о нём: Mockito приходит в песочницу вместе
со `spring-boot-starter-test`, ставить ничего не нужно. Его тесты
запускаются как любые другие, `./mvnw test`, итог — в том же отчёте.
На другом примере, в тесте ручки, он есть в
[статье 4 «Первая ручка: как приложение отвечает по HTTP»](https://hammerhall.io/ledger/articles/4-web)
цикла «От Java к Spring Boot».

### Строки WARNING в журнале

Рядом с тестами Mockito в журнале сборки, скорее всего, появятся строки
`WARNING` от самой Java: «A Java agent has been loaded dynamically…».
С ними — строка Mockito «Mockito is currently self-attaching…». Тесты
от них не падают.

Чтобы делать заглушки из любых классов, Mockito 5 переписывает классы
прямо во время прогона. Для этого он подключает к Java агента —
помощника, как у JaCoCo в статье 5. JaCoCo подключают при запуске,
а Mockito подключает себя сам, на ходу. С версии 21 Java о таком
предупреждает: когда-нибудь подключение на ходу запретят по умолчанию.

На Java 25 это пока только предупреждение. Убрать его можно, если
подключить Mockito агентом явно, флагом `-javaagent` для Surefire. Как
это записать в `pom.xml`, показано в разделе 0.3 документации Mockito.
Boot 4.1 этого сам не делает: ни start.spring.io, ни родительский
`pom.xml` Boot. Мы в песочнице тоже не делаем: статья `pom.xml`
не меняет.

### @Mock и MockitoExtension

Те же заглушки — Mockito:

```java
@ExtendWith(MockitoExtension.class)
class ScoreServiceMockitoTest {

    @Mock
    private SubmissionLog log;

    @Mock
    private Deadlines deadlines;

    @Mock
    private ScoreBoard board;

    private ScoreService service;

    @BeforeEach
    void setUp() {
        Clock fiveDaysLater = Clock.fixed(DEADLINE.plus(Duration.ofDays(5)), ZoneOffset.UTC);
        service = new ScoreService(log, deadlines, board, fiveDaysLater);
        when(deadlines.deadlineOf("T-7")).thenReturn(DEADLINE);
    }
```

Как читать:

* `@ExtendWith(MockitoExtension.class)` — «подключи к классу Mockito».
  `@ExtendWith` — пометка JUnit: она подключает **расширение**, код,
  который JUnit зовёт до и после каждого теста. Расширение Mockito перед
  тестом кладёт в поля `@Mock` свежие заглушки. После теста оно
  проверяет, не осталось ли лишнего, об этом ниже.
* `@Mock` — «сделай здесь заглушку этого типа».
* `@BeforeEach` — метод, который JUnit выполняет перед каждым тестом:
  общая подготовка в одном месте. `DEADLINE` — та же константа срока.

Без пометки заглушку делает метод `mock(…)`: `mock(SubmissionLog.class)`
вернёт то же самое. Встретишь оба способа.

⚠️ В интернете ты увидишь тесты с `@SpringBootTest`, где поля `@Mock`
работают без всякого `@ExtendWith`. `@SpringBootTest` помечает тест,
который поднимает приложение Spring целиком. Это Boot 2–3: там поля
`@Mock` заполнял сам Spring. В песочнице Boot 4, и этого больше нет:
без `MockitoExtension` поле останется `null`, и тест упадёт на первом
обращении к заглушке.

### when … thenReturn: задать ответ

`when(deadlines.deadlineOf("T-7")).thenReturn(DEADLINE)` читай как «пусть»:
«когда спросят срок задачи `T-7`, ответь `DEADLINE`». Внутри `when(…)`
метод заглушки вызывается понарошку: Mockito запоминает, какой вызов
настраивают. `when`, `verify` и их соседи — статические методы Mockito.
В тест их подключают `import static`, как `assertThat` (статья 2).

На вопрос, ответ на который не задан, заглушка отвечает «пустым»: `null`,
нулём, `false`, пустым списком, пустым `Optional`.

Последнее коварнее всего. Забудь `when` для `log`, и служба получит
пустую коробку и молча пойдёт путём «не сдал». Исключения не будет:
тест покраснеет на проверке, и причину придётся искать.

Та же запись по-другому — `given(…).willReturn(…)` из `BDDMockito`:
так пишет документация Spring Boot. В серии — `when`.

### verify: проверить вызов

```java
@Test
void lateWithinDayIsRecordedAsHalf() {
    when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE.plus(Duration.ofHours(2))));

    service.grade("student-1", "T-7");

    verify(board).record("student-1", "T-7", 50);
}
```

`verify(board).record("student-1", "T-7", 50)` значит «убедись, что
у доски вызвали `record` с этими аргументами, ровно один раз». Один
раз — по умолчанию; другое число пишут вторым аргументом:
`verify(board, times(2))`. Заглушка Mockito запоминает вызовы сама, как
наша `RememberingBoard`, только для любого интерфейса. Не было вызова
или аргументы другие — тест красный.

### ArgumentCaptor: перехватить аргумент

```java
@Test
void onTimeIsRecordedAsFull() {
    when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE));
    ArgumentCaptor<Integer> recorded = ArgumentCaptor.forClass(Integer.class);

    service.grade("student-1", "T-7");

    verify(board).record(anyString(), anyString(), recorded.capture());
    assertThat(recorded.getValue()).isEqualTo(100);
}
```

**`ArgumentCaptor`** — перехватчик аргумента. В `verify` вместо значения
стоит `recorded.capture()`: Mockito сохраняет то, что передали, а
`getValue()` отдаёт сохранённое, и дальше проверяешь его AssertJ.
В угловых скобках — только классы, поэтому перехватчик для `int`
объявлен как `Integer`. `anyString()` — **сопоставитель**: «любая строка».

⚠️ Если хоть один аргумент — сопоставитель, сопоставителями должны быть
все. `record(anyString(), anyString(), 100)` Mockito не примет и бросит
ошибку. Пиши `eq(100)` — сопоставитель «ровно это значение».

Честно: здесь перехватчик для показа, число можно проверить прямо
в `verify`. Нужен он, когда аргумент — объект, который служба собрала
сама: его проверяют по полям.

### verifyNoInteractions и never()

```java
@Test
void earlyCheckTouchesNothing() {
    Clock threeHoursLater = Clock.fixed(DEADLINE.plus(Duration.ofHours(3)), ZoneOffset.UTC);
    service = new ScoreService(log, deadlines, board, threeHoursLater);
    when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.empty());

    Optional<Integer> score = service.grade("student-1", "T-7");

    assertThat(score).isEmpty();
    verifyNoInteractions(board);                            // доску не трогали вовсе
}
```

`verifyNoInteractions(board)` — «с доской не делали ничего». Вариант
того же:

```java
verify(board, never()).record(anyString(), anyString(), anyInt());
```

«`record` не вызывали ни с какими аргументами». Здесь `anyInt()` —
сопоставитель «любое `int`», а `never()` значит «ноль раз». Разница
в том, что `verifyNoInteractions` запрещает любой метод, а `never()` —
один названный. У доски метод один, так что здесь они значат одно и то же.

### Почему служба собрана руками

В `earlyCheckTouchesNothing` службу пересобрали с другими часами. Часы —
настоящий объект, не заглушка: чтобы сменить время, нужны другие часы.

Пометка Mockito `@InjectMocks` над полем службы значит «создай службу
и подставь в неё заглушки из теста». Здесь она не годится, и причины две.

Первая: `@InjectMocks` берёт самый длинный конструктор и заполняет его
только заглушками из теста. Чего не нашёл, туда передаёт `null`
и молчит. Часы стали бы `null`. Тест «сдал» на такой службе прошёл бы:
до часов дело не доходит. А любой тест «не сдал» упал бы
с `NullPointerException`.

Вторая: явный `new ScoreService(…)` показывает зависимости. Появится
у службы ещё один сосед — тест не скомпилируется, и ты узнаешь сразу,
а не по `null`. `@InjectMocks` хорош, когда все соседи — заглушки.

### Строгие заглушки

`MockitoExtension` по умолчанию строг: **строгие заглушки** (strict
stubs). Если `when` в тесте так и не пригодился, тест падает
с `UnnecessaryStubbingException`, даже когда все проверки сошлись.

Лишний `when` значит, что тест думает, будто код идёт одной дорогой,
а тот идёт другой. Или это остаток после переделки, который путает
читателя. Лечится удалением лишнего `when`. Строгий режим ловит и вызов
заданного метода с другими аргументами.

Считается это для каждого теста отдельно, вместе с `@BeforeEach`.
Поэтому в `setUp` только то, что нужно всем: срок `T-7` спрашивают все
три теста. Если ответ нужен не всем, перенеси `when` в те тесты, где он
нужен. У Mockito есть и `lenient()` — «этой заглушке можно
не пригодиться». Но сначала спроси себя, зачем тогда она в тесте.

Чего строгий режим не ловит, так это вопроса, ответ на который ты
не задал вовсе. Заглушка молча ответит «пустым», как `log` выше. Такое
видно только по проверке результата.

### Тесты служб в рабочем проекте

Тесты служб в рабочем проекте устроены так же. У одной службы там пять
соседей, среди них хранилище, преобразователь ответа и оповещение.
В тесте все пять — заглушки, и служба собрана через `@InjectMocks`:
часов среди соседей нет. Ответ службы приходит от заглушки
преобразователя: его проверка показывает лишь, что ответ не потерян.

Главное видно через перехватчик: запись, которую служба собрала сама
и отдала хранилищу. Тест достаёт её и проверяет статус и другие поля.
Оповещение наружу ничего не возвращает, поэтому для него `verify`.

Там же есть планировщик, который обходит записи по одной. Метод
обработки записи — `void`, а `when(…)` вокруг такого вызова
не пропустит компилятор. Запись для него обратная:
`doThrow(исключение).when(заглушка).метод(…)`. Тест учит заглушку падать
на первой записи и проверяет, что вторая всё равно обработана. Соседний
тест прерывает обход, и `never()` подтверждает, что до второй записи
дело не дошло.

---

## Часть 4. Что подменять, а что нет

### Состояние или вызовы

Ручная доска проверяла **состояние**: что служба вернула и что
оказалось на доске. `verify` проверяет **взаимодействие**: какой метод
вызвали и с чем. Состоянию всё равно, каким путём служба к нему пришла,
поэтому такой тест переживает переделки. Взаимодействие нужно, когда
результат уходит из службы и смотреть больше не на что: оповещение,
запись в чужую систему. Правило простое: есть результат — проверяй
результат; `verify` — для того, что уходит наружу.

На нашей доске видны оба подхода. Руками мы смотрели, что на ней лежит,
а Mockito проверял, что её позвали. Для доски верно и то и другое:
запись на неё и есть результат службы. А `verify(deadlines).deadlineOf("T-7")`
был бы лишним: спросить срок — не результат, а способ его получить.

### Чего не подменять

**`DeadlineScore`.** Чистая логика, быстрая и без соседей. Подмени её,
и тест службы проверит правило, которое ты сам продиктовал заглушке.
Ошибку в настоящем правиле он не заметит. Настоящая ничего не стоит.

**Значения**: `Instant`, `Duration`, `Optional`, строки, списки. Их
создают настоящими.

**И не повторяй реализацию.** Тест, который пересказывает код, ставит
`verify` на каждый вызов: `verify(deadlines).deadlineOf(…)`,
`verify(log).submittedAt(…)`, `verify(board).record(…)`. Такой тест
ломается при переделке, которая поведения не меняет. Служба стала
спрашивать срок дважды, а `verify` по умолчанию ждёт ровно один вызов —
тест красный. Сроки всех задач стали брать одним общим запросом,
`deadlineOf` не зовут вовсе, и тест снова красный, хотя балл тот же.

А доказывает такой тест мало: что код написан так, как написан. Это
тест, согласный сам с собой, из статьи 5, только собранный из `verify`.

Подменяй **границы**: то, что уходит в базу, в сеть, к часам, в чужой
сервис. Всё, что внутри, — настоящее.

Тест доли из статьи 5 попался именно так: заглушка хранилища ответила
«дошли трое», и тест проверил только арифметику.

🔑 **Заглушка отвечает то, что ты ей велел, а того, что за ней, тест
не видит.** Поэтому подменяй только то, что не можешь взять настоящим.

### Проверка, которая проверяла заглушку

В команде был экран, который должен был особым образом отозваться
на один ответ сервера. Проверку написали в тестовом файле, который
поднимает всё приложение: казалось, правильное место. Но в начале того
же файла весь слой запросов к серверу был заменён заглушкой. А отклик
жил как раз внутри этого слоя: в тесте он не исполнялся вовсе.

Тест упал, и это была удача. Будь ожидание сформулировано чуть иначе,
он был бы зелёным даже при полностью выключенном отклике. Починили
разнесением по слоям, где проверяемое всегда настоящее. Один тест
подменяет только сеть браузера и проверяет, что слой запросов зовёт
обработчик. Другой подменяет слой запросов и проверяет, что экран
отвечает на вызов.

Правило оттуда: прежде чем писать проверку, спроси, **исполняется ли
проверяемый код в этом тесте**. Если его слой подменён, ты проверяешь
заглушку.

### Заглушка, которая отвечала на всё

В другом тесте там же заглушка сервера отвечала по адресу запроса,
а на незнакомый молча возвращала «ничего». Экран показывал своё
«не удалось получить данные» и всё равно отрисовывался: тест проверял
его в аварийном состоянии вместо обычного. Вырезали из заглушки один
адрес, и одиннадцать тестов остались зелёными и с ним, и без него.

Бросать исключение на незнакомый адрес не стали: экран поймал бы его,
показал ту же ошибку и остался бы зелёным. Заглушка стала **запоминать**
незнакомые запросы, а после каждого теста проверка требовала, чтобы
список был пуст. Теперь забытый адрес называет себя в красном отчёте
по имени. Это наша `RememberingBoard`, повёрнутая другой стороной:
заглушка, которая громко говорит о неожиданном.

### Заглушка в Spring: @MockitoBean

Объекты, которые создаёт и связывает Spring, называют **бинами**, а всё
поднятое приложение с ними — **контекстом**. В тесте, который поднимает
контекст, соседа служба получает от Spring, а не из твоего `new`. Там
`@MockitoBean` над полем заменяет бин заглушкой Mockito.

Готовые контексты Spring держит в кеше, но набор подменённых бинов
входит в ключ кеша. Каждый новый набор — новый контекст и лишние секунды.
Поэтому где можно, пиши модульный тест без Spring, как всё в этой статье.

⚠️ В интернете ты увидишь `@MockBean`. Это Boot 2–3; в Boot 4 его
удалили. В Boot 4 — `@MockitoBean` из пакета
`org.springframework.test.context.bean.override.mockito`.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему `ScoreService` нельзя проверить так же, как `DeadlineScore`,
   и что в тесте делает заглушка?
2. Когда заглушку можно записать лямбдой, а когда нужен класс вроде
   `RememberingBoard`?
3. Почему служба берёт «сейчас» из `Clock`? Что станет с тестами, если
   заменить `clock.instant()` на `Instant.now()`?
4. Тест «сдал через два часа» проверяет и ответ службы, и доску. Какую
   ошибку видит только проверка доски?
5. Чем проверка `board.records` отличается от `verify(board).record(…)`?
   Когда что выбрать?
6. Почему в `ScoreServiceMockitoTest` служба собрана в `@BeforeEach`
   руками, а не через `@InjectMocks`? Что `@InjectMocks` сделал бы
   с часами?
7. Все проверки сошлись, а тест упал с `UnnecessaryStubbingException`.
   Что это значит и что делать?
8. Почему не надо подменять `DeadlineScore`? И чем плох тест, который
   ставит `verify` на каждый вызов реализации?

---

## Что дальше

Следующая статья серии — тест с настоящей базой. `ScoreBoard`, которую
сегодня подменяли, получит настоящую реализацию. И мы увидим, что ловит
только база: повторный зачёт, балл вне правил, ошибку в SQL.

## Первоисточники

* [Mockito — javadoc класса Mockito](https://www.javadoc.io/static/org.mockito/mockito-core/5.24.0/org.mockito/org/mockito/Mockito.html) —
  разделы 0.3 (агент на Java 21+), 1–4 (заглушка, `when`,
  сопоставители, `verify`, `never`), 12 (`doThrow`), 15 (`ArgumentCaptor`).
* [Mockito — UnnecessaryStubbingException](https://www.javadoc.io/static/org.mockito/mockito-core/5.24.0/org.mockito/org/mockito/exceptions/misusing/UnnecessaryStubbingException.html) —
  что такое лишняя заглушка и почему её лучше удалить.
* [Java 25 — java.time.Clock](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html) —
  зачем часы объектом и что такое `Clock.fixed`.
* [Spring Framework — @MockitoBean и @MockitoSpyBean](https://docs.spring.io/spring/reference/testing/annotations/integration-spring/annotation-mockitobean.html) —
  заглушка вместо объекта в тесте со Spring.
* [Spring Framework — Context Caching](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/ctx-management/caching.html) —
  из чего складывается ключ кеша, и почему новый набор заглушек — новый
  контекст.

---

## Пример целиком — с импортами

Учебный пример живёт в песочнице `testy` из статьи 1. К этой статье
в ней всё из статей 1–5: `DeadlineScore` и `Attempts`, их тесты
и плагин JaCoCo в `pom.xml`. Новые файлы — в пакете
`example.testy.score`, рядом с `DeadlineScore`, который не меняется.
Зависимостей статья не добавляет: Mockito приходит
со `spring-boot-starter-test`.

```java
// src/main/java/example/testy/score/SubmissionLog.java
package example.testy.score;

import java.time.Instant;
import java.util.Optional;

/** Где записано, когда задачу сдали. */
public interface SubmissionLog {

    /** Когда студент сдал задачу; не сдавал — пусто. */
    Optional<Instant> submittedAt(String studentId, String taskKey);
}
```

```java
// src/main/java/example/testy/score/Deadlines.java
package example.testy.score;

import java.time.Instant;

/** Сроки задач. */
public interface Deadlines {

    Instant deadlineOf(String taskKey);
}
```

```java
// src/main/java/example/testy/score/ScoreBoard.java
package example.testy.score;

/** Куда записывают зачёт. */
public interface ScoreBoard {

    void record(String studentId, String taskKey, int score);
}
```

```java
// src/main/java/example/testy/score/ScoreService.java
package example.testy.score;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;

/** Ставит зачёт по задаче: берёт время сдачи и срок, считает балл, записывает. */
public class ScoreService {

    private final SubmissionLog log;
    private final Deadlines deadlines;
    private final ScoreBoard board;
    private final Clock clock;                                  // «сейчас» — только отсюда

    public ScoreService(SubmissionLog log, Deadlines deadlines, ScoreBoard board, Clock clock) {
        this.log = log;
        this.deadlines = deadlines;
        this.board = board;
        this.clock = clock;
    }

    /**
     * Поставить зачёт. Пусто — ставить рано: задачу ещё не сдали,
     * а время на половину балла не вышло.
     */
    public Optional<Integer> grade(String studentId, String taskKey) {
        Instant deadline = deadlines.deadlineOf(taskKey);
        Optional<Instant> submittedAt = log.submittedAt(studentId, taskKey);

        if (submittedAt.isEmpty()) {
            Instant lastChance = deadline.plus(DeadlineScore.GRACE);
            if (clock.instant().isAfter(lastChance)) {          // сдать на половину уже нельзя
                board.record(studentId, taskKey, DeadlineScore.NONE);
                return Optional.of(DeadlineScore.NONE);
            }
            return Optional.empty();                            // ещё не поздно — не трогаем
        }

        int score = DeadlineScore.score(deadline, submittedAt.get());
        board.record(studentId, taskKey, score);
        return Optional.of(score);
    }
}
```

```java
// src/test/java/example/testy/score/ScoreServiceTest.java
package example.testy.score;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/** Заглушки — руками, без библиотек. */
class ScoreServiceTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    /** Доска, которая запоминает, что на неё записали. */
    static class RememberingBoard implements ScoreBoard {

        final List<String> records = new ArrayList<>();

        @Override
        public void record(String studentId, String taskKey, int score) {
            records.add(studentId + " " + taskKey + " " + score);
        }
    }

    private final RememberingBoard board = new RememberingBoard();
    private final Deadlines deadlines = taskKey -> DEADLINE;                     // у всех задач один срок

    private ScoreService serviceAt(Instant now, SubmissionLog log) {
        return new ScoreService(log, deadlines, board, Clock.fixed(now, ZoneOffset.UTC));
    }

    @Test
    void submittedLateWithinDayGetsHalf() {
        SubmissionLog log = (studentId, taskKey) -> Optional.of(DEADLINE.plus(Duration.ofHours(2)));
        ScoreService service = serviceAt(DEADLINE.plus(Duration.ofDays(5)), log);

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).contains(50);
        assertThat(board.records).containsExactly("student-1 T-7 50");
    }

    @Test
    void notSubmittedYetIsNotGraded() {
        SubmissionLog log = (studentId, taskKey) -> Optional.empty();
        ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(3)), log);   // сутки ещё не прошли

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).isEmpty();
        assertThat(board.records).isEmpty();
    }

    @Test
    void notSubmittedAfterGraceGetsNothing() {
        SubmissionLog log = (studentId, taskKey) -> Optional.empty();
        ScoreService service = serviceAt(DEADLINE.plus(Duration.ofHours(25)), log);  // сутки прошли

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).contains(0);
        assertThat(board.records).containsExactly("student-1 T-7 0");
    }
}
```

```java
// src/test/java/example/testy/score/ScoreServiceMockitoTest.java
package example.testy.score;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** Те же заглушки — Mockito. */
@ExtendWith(MockitoExtension.class)
class ScoreServiceMockitoTest {

    private static final Instant DEADLINE = Instant.parse("2026-10-12T21:00:00Z");

    @Mock
    private SubmissionLog log;

    @Mock
    private Deadlines deadlines;

    @Mock
    private ScoreBoard board;

    private ScoreService service;

    @BeforeEach
    void setUp() {
        Clock fiveDaysLater = Clock.fixed(DEADLINE.plus(Duration.ofDays(5)), ZoneOffset.UTC);
        service = new ScoreService(log, deadlines, board, fiveDaysLater);
        when(deadlines.deadlineOf("T-7")).thenReturn(DEADLINE);
    }

    @Test
    void lateWithinDayIsRecordedAsHalf() {
        when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE.plus(Duration.ofHours(2))));

        service.grade("student-1", "T-7");

        verify(board).record("student-1", "T-7", 50);
    }

    @Test
    void onTimeIsRecordedAsFull() {
        when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.of(DEADLINE));
        ArgumentCaptor<Integer> recorded = ArgumentCaptor.forClass(Integer.class);

        service.grade("student-1", "T-7");

        verify(board).record(anyString(), anyString(), recorded.capture());
        assertThat(recorded.getValue()).isEqualTo(100);
    }

    @Test
    void earlyCheckTouchesNothing() {
        Clock threeHoursLater = Clock.fixed(DEADLINE.plus(Duration.ofHours(3)), ZoneOffset.UTC);
        service = new ScoreService(log, deadlines, board, threeHoursLater);
        when(log.submittedAt("student-1", "T-7")).thenReturn(Optional.empty());

        Optional<Integer> score = service.grade("student-1", "T-7");

        assertThat(score).isEmpty();
        verifyNoInteractions(board);                            // доску не трогали вовсе
    }
}
```

Сделай руками:

1. `./mvnw test` — всё зелёное, `Tests run: 24`: 18 тестов статей 1–5
   и шесть новых. Строки `WARNING` про агента из части 3 сборку
   не роняют.
2. Вычеркни в `ScoreService` строку `board.record(studentId, taskKey, score);`
   после подсчёта балла. Красные: `submittedLateWithinDayGetsHalf` —
   на проверке доски, ответ при этом верный; `lateWithinDayIsRecordedAsHalf`
   и `onTimeIsRecordedAsFull` — вызова не было. Верни строку.
3. Вычеркни строку `board.record(studentId, taskKey, DeadlineScore.NONE);`
   в ветке «сутки прошли». Красный `notSubmittedAfterGraceGetsNothing`:
   ноль в ответе верный, а на доске пусто. Верни строку.
4. Замени `clock.instant()` на `Instant.now()`. Сейчас уже позже
   13.10.2026 21:00 UTC, поэтому красные `notSubmittedYetIsNotGraded`
   и `earlyCheckTouchesNothing`. До этого момента красным был бы
   `notSubmittedAfterGraceGetsNothing`. Верни как было.
5. Допиши в `lateWithinDayIsRecordedAsHalf` лишний `when` — например,
   ответ для `"student-2"`. Проверка сойдётся, а тест упадёт
   с `UnnecessaryStubbingException`. Убери.

Каждый из шести тестов хоть раз был красным на настоящей ошибке. Такому
зелёному можно верить.
