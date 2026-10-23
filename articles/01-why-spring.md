# Зачем Spring

> «От Java к Spring Boot» · статья 1 · читать минут 30
>
> **Для кого.** Ты прочитал статью 0: записи, Maven, тесты на JUnit
> и AssertJ. Spring по-прежнему не видел — и это нормально: статья
> начинается с обычной Java.
>
> **Что будет.** Три вещи: почему объект получает то, что ему нужно,
> через конструктор, а не создаёт сам; как проверить такой класс тестом
> без Spring; что делает контейнер Spring — бины, `@Component`,
> `@Configuration` и `@Bean` — и почему бин один на всё приложение.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Java к Spring Boot» — то, что
> нужно новичку до первой задачи на Spring Boot 4. Примеры — учебные:
> их можно повторить у себя.

---

## Зачем Spring

В курсах все объекты программы создаёт `main`: пара строк с `new` —
и готово. В рабочем проекте классов сотни, и многие нужны друг другу.
Например, часы — объект, у которого спрашивают время (о нём ниже).
Они понадобятся повторным попыткам, расписанию, метрикам, и всем нужны
одни и те же.

Кто создаёт все эти объекты и в каком порядке? Как подменить один
из них в тесте? Эту работу берёт на себя Spring. Чтобы понимать, что
он делает и почему иногда падает при запуске, проделаем его работу
один раз руками, а потом отдадим сборку Spring. После статьи тебе будет понятно каждое слово
во фразе «часы приложения — бин `Clock`».

**Сквозной пример серии — журнал игрового дня.** Игровой день — учения
команды: тимлид атакует **стенд**, копию сервиса для проверок
и учений. Дежурные замечают происшествия, мидлы чинят. Журнал
принимает происшествие, например «брокер не отвечает», и оповещает
того, кто сейчас дежурит. Пример учебный, и дальше журнал научится
хранить происшествия в базе и отдавать их по сети.

---

## Часть 1. Собираем руками

### Три помощника журнала

Журналу нужны три вещи: узнать, кто сейчас дежурит, оповестить
дежурного и знать, который час, — чтобы записать, когда заметили
происшествие. Первое умеет `DutyRoster`, второе — `ConsoleNotifier`,
он пока просто печатает в консоль.

```java
public class DutyRoster {

    private final String dutyName;      // final — поле заполняется один раз, в конструкторе, и потом не меняется

    public DutyRoster(String dutyName) {
        this.dutyName = dutyName;       // в учебном примере дежурный один на всю игру
    }

    public String currentDuty() {
        return dutyName;
    }
}
```

```java
public class ConsoleNotifier {

    public void send(String dutyName, String text) {
        System.out.println("[оповещение] " + dutyName + ": " + text);   // пока — просто в консоль
    }
}
```

Для времени нам хватит двух классов из пакета `java.time`.
**`Instant`** — момент времени: точка на оси времени без часового пояса.
Печатается так: `2026-10-05T09:15:00Z`, где `Z` значит UTC — всемирное
время, без поясов и перехода на летнее. **`Clock`** — часы: объект,
у которого спрашивают «который час»; `clock.instant()` вернёт `Instant`.

Есть ещё `Instant.now()` — «сейчас» прямо из системы. Зачем тогда
отдельный объект, станет ясно в части 2.

Теперь сам журнал:

```java
public class IncidentLog {

    private final DutyRoster roster;
    private final ConsoleNotifier notifier;
    private final Clock clock;

    public IncidentLog(DutyRoster roster, ConsoleNotifier notifier, Clock clock) {
        this.roster = roster;                         // всё, что нужно для работы, пришло снаружи
        this.notifier = notifier;
        this.clock = clock;
    }

    public void add(String title) {
        Instant detectedAt = clock.instant();         // «сейчас» спрашиваем у часов
        String dutyName = roster.currentDuty();       // кто дежурит
        notifier.send(dutyName, title + " — замечено " + detectedAt);
    }
}
```

Хранить происшествия журнал пока не умеет, только оповещает.

Как и в статье 0, в коротких примерах нет `import`, а `…` в коде —
пропущенный кусок, который не изменился. Полные файлы — в конце статьи.
Где запускать код — в части 3: там у журнала появится свой проект.

### Сборка в main

Всё, без чего объект не может работать, называют его **зависимостями**
(dependencies). У журнала их три: дежурные, оповещение и часы. Слово
знакомо по `pom.xml`, но там это библиотека, нужная проекту, а здесь —
объект, нужный другому объекту.

Соберём журнал:

```java
public class HandMadeApp {

    public static void main(String[] args) {
        DutyRoster roster = new DutyRoster("duty-1");                 // 1. сначала те, кто ни от кого не зависит
        ConsoleNotifier notifier = new ConsoleNotifier();
        Clock clock = Clock.systemUTC();                              //    настоящие часы, время в UTC
        IncidentLog log = new IncidentLog(roster, notifier, clock);   // 2. потом тот, кому они нужны

        log.add("Брокер не отвечает");
    }
}
```

В консоли (время будет твоё):

```
[оповещение] duty-1: Брокер не отвечает — замечено 2026-10-05T09:15:03.512704831Z
```

Работает. Но в этом `main` четыре проблемы, которые с ростом приложения
станут большими.

### Где больно

**1. Порядок создания.** Здесь четыре строки, и порядок очевиден.
В рабочем проекте объектов сотни, и следить за порядком придётся тебе.
Появилась у журнала четвёртая зависимость — правь `main` и каждое место,
где журнал создают через `new`.

**2. Одна копия на всех.** Настоящее оповещение держит подключение
к чату или почте: его создают один раз, и пользуются им все. В `main`
это значит — вручную протащить один объект в каждый конструктор. А если
где-то в глубине кто-то напишет свой `new ConsoleNotifier()`, копий
станет две — и никто этого не заметит.

**3. Подмена.** Журнал принимает именно `ConsoleNotifier`. Как проверить
тестом, что дежурный получил оповещение, — читать консоль? А на стенде
хочется оповещать в чат, локально — в консоль. Сейчас для этого пришлось
бы переписать сам журнал.

**4. Кто знает настройки.** Имя дежурного, куда оповещать, какие
часы — всё решает `main`. Появятся у оповещения адрес чата и ключ,
а у игры длительность и стоп-слово — всё это тоже ляжет в `main`,
рядом с `new`.

---

## Часть 2. Зависимости — снаружи

### Внедрение через конструктор

Посмотри ещё раз на конструктор журнала: он не создаёт ни дежурных,
ни оповещение, ни часы — получает готовыми. Можно было бы иначе:

```java
public class IncidentLog {

    private final DutyRoster roster = new DutyRoster("duty-1");       // сам решает, кто дежурит,
    private final ConsoleNotifier notifier = new ConsoleNotifier();   // и сам выбирает, куда оповещать

    public void add(String title) {
        Instant detectedAt = Instant.now();                           // «сейчас» — прямо из системы
        notifier.send(roster.currentDuty(), title + " — замечено " + detectedAt);
    }
}
```

`main` стал бы проще, но журнал теперь намертво приварен к консоли
и к системным часам. В тесте оповещение уйдёт в консоль, а время
в тексте каждый раз новое — строку целиком не проверить.

Приём, когда объект не создаёт свои зависимости, а получает их
в конструкторе, называется **внедрением через конструктор** (constructor
injection). Как в первый день в команде: ноутбук, доступы и ключ
от стенда тебе выдают, а не ты сам их покупаешь. Кто выдаёт, тот
и решает, учебный стенд или настоящий, — работать ты будешь одинаково.

Почему именно конструктор, а не поле (о нём — в конце статьи):

* поля `final`: конструктор обязан их заполнить, и подменить их потом
  нельзя. А контейнер Spring, не найдя часов, журнал вовсе не создаст —
  упадёт при запуске (часть 3);
* все зависимости видны в одном месте — в параметрах конструктора;
* в тесте объект создаётся обычным `new` — с теми зависимостями, какие
  нужны тесту.

### Интерфейс — точка подмены

Журнал всё ещё просит именно `ConsoleNotifier`. Нужен **интерфейс** — список методов без реализации:
«что умеет», но не «как». Интерфейс — как розетка: журнал знает только
её форму, а включить в неё можно любой прибор.

```java
public interface Notifier {

    void send(String dutyName, String text);         // оповестить дежурного; как именно — решает реализация
}
```

```java
public class ConsoleNotifier implements Notifier {

    @Override
    public void send(String dutyName, String text) {
        System.out.println("[оповещение] " + dutyName + ": " + text);
    }
}
```

Методы интерфейса всегда открытые, поэтому `public` в нём не пишут,
а тела нет — сразу точка с запятой. В классе-реализации `public`
обязателен. `implements Notifier` — «этот класс выполняет то, что
обещает интерфейс». `@Override` — аннотация «этот метод из
интерфейса»: ошибёшься в имени, и компилятор скажет.

В журнале меняется одно слово в двух местах — тип поля и параметра:

```java
    private final Notifier notifier;                  // было ConsoleNotifier

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock) { … }
```

Теперь на стенде можно написать свой `ChatNotifier implements Notifier`,
а в тесте — свою реализацию, и журнал этого не заметит.

С часами то же самое уже сделано в JDK: `Clock` — общий тип, а часов
за ним несколько. `Clock.systemUTC()` — настоящие часы в UTC.
`Clock.fixed(…)` — остановленные: они всегда показывают одно и то же время.

### Тест без Spring

Для теста напишем **заглушку** — объект, который в тесте стоит вместо
настоящего. Наша заглушка никуда не шлёт, а запоминает. Позже такие
заглушки за тебя будет делать библиотека Mockito, о ней в продолжении
серии. А пока напишем руками:

```java
class RememberingNotifier implements Notifier {

    final List<String> messages = new ArrayList<>();     // всё, что журнал «отправил»

    @Override
    public void send(String dutyName, String text) {
        messages.add(dutyName + ": " + text);            // никуда не шлём — запоминаем
    }
}
```

`List<String>` — список строк: в угловых скобках пишут, что лежит
в списке. Справа скобки пустые — Java сама возьмёт `String` из левой
части. `List` — тоже интерфейс, а `ArrayList` — одна из его реализаций:
тот же приём, что с `Notifier`.

Поле без `private` видно классам того же пакета. Тест лежит в том же
пакете и читает `messages` напрямую. В коде продукта так не делают,
в заглушке для теста — можно. Сама заглушка живёт рядом с тестами,
в `src/test/java`, и в приложение не попадёт.

Тест — на JUnit и AssertJ из статьи 0:

```java
class IncidentLogTest {

    @Test
    void notifiesDutyWithDetectionTime() {
        RememberingNotifier notifier = new RememberingNotifier();                            // заглушка вместо консоли
        Clock clock = Clock.fixed(Instant.parse("2026-10-05T09:15:00Z"), ZoneOffset.UTC);   // часы стоят
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier, clock);

        log.add("Брокер не отвечает");

        assertThat(notifier.messages)
                .containsExactly("duty-1: Брокер не отвечает — замечено 2026-10-05T09:15:00Z");
    }
}
```

Как читать:

* `Instant.parse(…)` превращает строку в момент времени, `ZoneOffset.UTC` —
  часовой пояс UTC. Пояс нужен часам для местного времени, на `instant()`
  он не влияет. Такие часы всегда показывают 09:15 пятого октября;
* журнал создаётся обычным `new` — с заглушкой и остановленными часами;
* `containsExactly` — «в списке ровно эти элементы, в этом порядке».

🔑 Тест не запускает Spring (о нём — в части 3), ничего не печатает
и не зависит от того, когда его запустили. Это и есть главная сила
внедрения через конструктор: любую зависимость можно подменить простым
`new`. Большинство тестов рабочего проекта устроены именно так — без
Spring и без базы.

💡 Вот и ответ, зачем часы — отдельный объект: с `Instant.now()` внутри
строку целиком не проверить. В рабочем проекте «сейчас» берут только
из `Clock` — это правило команды.

Подмену решили, а порядок создания, одна копия и настройки по-прежнему
на `main`. Это работа для Spring.

---

## Часть 3. Контейнер Spring

### Spring Framework — кто собирает объекты

**Spring Framework** (обычно говорят просто Spring) — библиотека,
которая создаёт объекты приложения и связывает их между собой: ты
описываешь, какие объекты нужны и что им требуется, а порядок создания
и передачу зависимостей Spring берёт на себя. В учебных проектах объекты
собирают в `main` руками — их там несколько. В рабочих их сотни, и `main`
на сотни строк никто не пишет.

Отдельной программы у Spring нет: это библиотека внутри приложения.
Ставить её руками не нужно — её притягивает стартер `spring-boot-starter`.
Spring — его зависимость, то есть зависимость зависимости (помнишь,
у библиотек есть свои зависимости). В рабочем проекте Spring приезжает
так же, со стартерами Boot. Запускает Spring твой `main`; что пошло не так,
видно сразу в консоли.

### Песочница: проект со start.spring.io

Журналу нужен свой проект: в настоящем сервисе пример упёрся бы в чужой
код, базу и пороги покрытия, а в песочнице всё запускается сразу.

**Spring Initializr** — сайт start.spring.io, который за минуту собирает
заготовку проекта со Spring Boot: `pom.xml` со стартерами, обёртку
`mvnw`, папки `src/main/java` и `src/test/java`. На работе заготовку
не пишут с нуля, а генерируют. Ставить ничего не нужно. Заполни поля:

| поле | значение |
|---|---|
| Project | Maven |
| Language | Java |
| Spring Boot | 4.1.x — последняя 4.1 |
| Group | `example` |
| Artifact | `game-day` |
| Package name | `example.gameday` — проверь и при необходимости впиши руками |
| Java | 25 |

На машине нужен JDK 25 — тот же, на котором собирается рабочий проект.
С JDK 17 или 21 из курса сборка упадёт с `release version 25 not supported`;
проверь, что IDE взяла для проекта именно его.

Зависимости (Dependencies) не добавляй: `spring-boot-starter`
и `spring-boot-starter-test` Initializr кладёт всегда. Первый принесёт
Spring, второй — JUnit и AssertJ.

Кнопка Generate скачает архив. Распакуй его и открой в IDE папку
с `pom.xml`; в первый раз Maven будет долго качать библиотеки в `~/.m2`.

Initializr создаст ещё класс `GameDayApplication` и тест
`GameDayApplicationTests`. Это Boot, о нём статья 2. Пока не трогай их
и запускай свой `GameDayApp`.

Классы журнала клади в подпакет `src/main/java/example/gameday/journal`,
заглушку и тест — в `src/test/java/example/gameday/journal`. Подпакет
нужен, чтобы наш контейнер не подхватил класс Boot от Initializr.
Запуск — зелёным треугольником рядом с `main` или с тестом. Все тесты
разом — `./mvnw test`.

### Контейнер и бин

Сердце Spring — **контейнер**: объект внутри приложения, который по
твоему описанию создаёт другие объекты, передаёт им зависимости и
держит у себя. Контейнер — как сборщик мебели: ты отдаёшь детали
и схему, что к чему крепится, а в каком порядке крутить, он решает сам.
В Spring контейнер описан интерфейсом **`ApplicationContext`** —
«контекст приложения»; в документации и в тексте ошибок встретишь оба
слова.

⚠️ Не путай с контейнером Docker на стенде — совпало только слово.
Поэтому в Spring чаще говорят «контекст».

**Бин** (bean) — объект, который контейнер создал сам или получил
из метода с `@Bean` (о нём ниже) и держит у себя. Бинами делают
«работников» приложения: журнал, оповещение, часы. Строка с заголовком,
момент времени — обычные объекты, их создаёт твой код по ходу работы.

Описать бины можно двумя способами. Первый — для своих классов.

### @Component — «создай меня сам»

```java
@Component                                           // «контейнер, создай объект этого класса»
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock) {   // конструктор один
        this.roster = roster;
        this.notifier = notifier;
        this.clock = clock;
    }
    …
}
```

**`@Component`** — аннотация над классом: «контейнер, создай объект
этого класса и сделай его бином». Ту же пометку ставим на
`ConsoleNotifier`. На интерфейс `Notifier` — нет: объект интерфейса
создать нельзя. Когда журнал попросит `Notifier`, контейнер найдёт бин,
который его реализует, — `ConsoleNotifier`.

Будь таких бинов два, контейнер не понял бы, какой передать, и упал бы
при запуске. Как держать две реализации и выбирать одну, в серии
не разбираем; встретишь в рабочем коде — ищи `@Primary` и `@Qualifier`.

В рабочем коде встретишь ещё `@Service`. Это та же `@Component`, только имя
подсказывает читателю: здесь логика.

Как контейнер найдёт эти классы? Он умеет просматривать пакет и
собирать всё, что помечено `@Component`. Это называется **сканированием
компонентов**; как его включить — ниже.

**Почему нет `@Autowired`.** **`@Autowired`** — аннотация «внедри сюда».
Если конструктор у класса один, контейнер вызывает его сам и передаёт
бины нужных типов. Пометка нужна, только когда конструкторов несколько:
ею отмечают тот, которым контейнер должен пользоваться. Так с Spring 4.3;
в старых примерах `@Autowired` висит над каждым конструктором — это
лишнее.

### @Configuration и @Bean — когда @Component не подходит

`@Component` годится, когда контейнер может собрать объект сам: все
параметры конструктора — бины. Так бывает не всегда.

**Нужны данные, которых у контейнера нет.** `DutyRoster` просит имя
дежурного — строку `"duty-1"`. Откуда контейнеру её знать?

**Класс чужой.** `Clock` — класс JDK. Поставить на него `@Component`
нельзя: его код не твой. То же — с классами любых библиотек.

Для таких случаев есть **класс настройки** — класс с аннотацией
**`@Configuration`**, а в нём методы с аннотацией **`@Bean`**. Контейнер
вызовет такой метод один раз, и то, что метод вернул, станет бином:

```java
@Configuration                                  // «в этом классе описаны бины»
@ComponentScan                                  // «и найди классы с @Component» — о ней ниже
public class GameDayConfig {

    @Bean                                       // «то, что вернёт метод, — бин»
    public DutyRoster dutyRoster() {
        return new DutyRoster("duty-1");        // кто дежурит, знает настройка, а не main
    }
}
```

На `DutyRoster` `@Component` не ставим: бин из него делает метод.
Значение `"duty-1"` переехало из `main` в класс настройки. Четвёртая
боль закрыта наполовину: значения пока в коде, зато собраны в одном
месте, отдельно от сборки объектов. Как вынести значения в файл
настроек — статья 2.

Часы объявляются тем же способом — методом с `@Bean`, который
возвращает `Clock`. Но сначала забудем про них и посмотрим, что сделает
контейнер.

### Запуск контейнера без Boot

```java
public class GameDayApp {

    public static void main(String[] args) {
        AnnotationConfigApplicationContext context =
                new AnnotationConfigApplicationContext(GameDayConfig.class);   // поднять контейнер
        IncidentLog log = context.getBean(IncidentLog.class);                  // заглянуть: дай журнал

        log.add("Брокер не отвечает");

        context.close();                                                       // погасить контейнер
    }
}
```

Как читать:

* **`AnnotationConfigApplicationContext`** — контейнер, который берёт
  описание бинов из аннотаций: Annotation Config — «настройка
  аннотациями». Это одна из реализаций интерфейса `ApplicationContext`.
  В конструктор ему передаём класс настройки;
* `@ComponentScan` на классе настройки включает сканирование. Без
  параметров контейнер просматривает пакет, где лежит `GameDayConfig`,
  и все вложенные. Наши классы лежат в том же пакете
  `example.gameday.journal`, и он их найдёт. А `GameDayApplication`
  из пакета выше — нет;
* `getBean(IncidentLog.class)` — «дай бин такого типа».

⚠️ В рабочем коде `getBean` не пишут: бины получают только через
конструктор. Здесь он один раз — чтобы заглянуть внутрь контейнера.

### Первый запуск — ошибка

Запусти `GameDayApp`. Контейнер упадёт сразу, ещё до `getBean`,
с длинным текстом ошибки. Читать его целиком не нужно — ищи знакомые
имена:

```
Error creating bean with name 'incidentLog' … Unsatisfied dependency expressed
through constructor parameter 2: No qualifying bean of type 'java.time.Clock' available
```

`incidentLog` — имя бина журнала. У бина с `@Component` это имя класса
с маленькой буквы, у метода с `@Bean` — имя метода (`dutyRoster`).
`parameter 2` — третий параметр конструктора, счёт с нуля: журнал
просит часы, а бина часов нет. По той же причине упадёт и тест
`GameDayApplicationTests` от Initializr, если запустишь все тесты.

Это хорошая ошибка: контейнер проверяет связи при запуске, и забытую
зависимость ты увидишь у себя, а не на игровом дне.

Добавим часы в `GameDayConfig`:

```java
    @Bean                                       // Clock — чужой класс из JDK
    public Clock clock() {
        return Clock.systemUTC();               // настоящие часы, время в UTC
    }
```

Запусти снова. Перед нашей строкой контейнер может напечатать служебные
строки со словом `DEBUG` — сейчас их можно не читать. Последней будет
(время — твоё):

```
[оповещение] duty-1: Брокер не отвечает — замечено 2026-10-05T09:15:03.512704831Z
```

То же, что напечатал `main` из части 1. Контейнер собрал те же четыре
объекта, журнал и трёх его помощников, и связал их так же. Только
порядок нашёл сам.

### Одна копия на всё приложение

По умолчанию контейнер создаёт каждый бин **один раз** и отдаёт этот
же объект всем, кто его попросит. Такой бин называют **одиночкой**
(singleton). Как кофемашина в офисе: одна на всех, и никто не ставит
себе свою. Это закрывает вторую боль: одну копию даёт контейнер,
протаскивать её через `main` не нужно.

💡 В книгах «одиночка» — ещё и шаблон, где класс сам не даёт создать
вторую копию. Бин не такой: `new ConsoleNotifier()` создаст вторую.
Правило «бины — только через конструктор» держит ревью.

У одиночки есть обратная сторона. Сервис обслуживает запросы параллельно:
у каждого запроса свой **поток** (thread) — отдельный исполнитель,
который идёт по коду. Два потока могут оказаться в одном методе одной
копии бина в один и тот же момент. Поэтому хранить в полях бина данные
одного вызова нельзя:

```java
@Component
public class IncidentLog {

    private String title;                           // 🔴 данные одного вызова — в поле общей копии

    public void add(String title) {
        this.title = title;
        String dutyName = roster.currentDuty();
        notifier.send(dutyName, this.title);        // к этой строке поле мог переписать другой вызов
    }
    …
}
```

Первый вызов положил в поле «Брокер не отвечает» — и пока он узнавал,
кто дежурит, второй переписал поле на «Почта молчит». Оба оповещения —
про почту, а брокер потерян. 🔴 В сервисе, который рассылает письма,
тот же промах — это письмо не тому человеку: служба запомнит «текущего получателя»
в поле, а соседний запрос его перепишет.

🔑 В полях бина — только зависимости и настройки, все `final`. Всё, что
относится к одному вызову, живёт в параметрах метода и локальных
переменных: происшествие, человек, запрос. Заглушке
`RememberingNotifier` копить вызовы в поле можно: она не бин и живёт
один тест.

### Где интернет учит старому

⚠️ **`@Autowired` на поле.** В интернете ты увидишь так:

```java
@Component
public class IncidentLog {

    @Autowired
    private Notifier notifier;                      // контейнер положит бин прямо в поле
    …
}
```

Это **внедрение в поле** — старый стиль. Spring его по-прежнему
понимает, но в рабочем проекте — только конструктор. Такое поле не может
быть `final`. `new IncidentLog()` даст журнал с `null` вместо оповещения,
а тест без Spring в такое поле ничего не положит. Пропадает всё, чем
был хорош тест из части 2.

⚠️ **`javax` вместо `jakarta`.** Иногда бину нужно что-то сделать сразу
после создания, когда зависимости уже переданы. Для этого метод
помечают аннотацией **`@PostConstruct`** — контейнер вызовет его сам.
В интернете ты увидишь `javax.annotation.PostConstruct`: так писали
во времена Boot 2. В серии — Spring Framework 7 (его приносит Boot 4),
и аннотации из `javax` он больше не поддерживает. Правильно —
`jakarta.annotation.PostConstruct`.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что такое зависимость объекта? Назови зависимости `IncidentLog`.
   Чем это слово отличается от зависимости в `pom.xml`?
2. Что значит «внедрение через конструктор»? Что станет хуже, если
   журнал будет сам создавать оповещение и брать время из `Instant.now()`?
3. Зачем `Notifier` сделан интерфейсом, если в приложении реализация
   пока одна — `ConsoleNotifier`?
4. Как тест из части 2 проверил время в тексте оповещения, не зная,
   когда его запустят?
5. Чем бин отличается от обычного объекта? Как контейнер узнаёт, какие
   классы создавать?
6. Когда нужен `@Bean`, а не `@Component`? Почему на `Clock` нельзя
   поставить `@Component`?
7. Контейнер упал при запуске, и в тексте ошибки есть `java.time.Clock`.
   Что случилось и почему хорошо, что это случилось именно при запуске?
8. Почему в поле бина нельзя хранить данные одного вызова? Чем это
   грозит сервису, который рассылает уведомления?

---

## Что дальше

Boot делает ещё больше: сам создаёт контейнер и сотни бинов, а настройки
игры, например длительность и стоп-слово, читает из файла. Это статья 2,
в той же песочнице: место `GameDayApp` займёт `GameDayApplication`.

## Первоисточники

* [Spring Framework: Using @Autowired](https://docs.spring.io/spring-framework/reference/core/beans/annotation-config/autowired.html) —
  когда `@Autowired` не нужен: врезка про единственный конструктор;
* [Spring Framework: Java-based Container Configuration](https://docs.spring.io/spring-framework/reference/core/beans/java.html) —
  как описывать бины классом настройки, запускать
  `AnnotationConfigApplicationContext` и включать сканирование;
* [Spring Boot: Spring Beans and Dependency Injection](https://docs.spring.io/spring-boot/reference/using/spring-beans-and-dependency-injection.html) —
  то же глазами Boot: сканирование компонентов, `@Service`;
* [Java 25: java.time.Clock](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/time/Clock.html) —
  `systemUTC`, `fixed`, `instant`;
* [Spring Framework 7.0 Release Notes](https://github.com/spring-projects/spring-framework/wiki/Spring-Framework-7.0-Release-Notes) —
  раздел Removed APIs: почему `javax` больше не работает.

---

## Пример целиком — с импортами

Учебный пример. Запускай его в песочнице
`game-day` со start.spring.io — как её завести и куда класть файлы,
сказано в части 3. `GameDayApplication` и `GameDayApplicationTests`
от Initializr не трогай.

```java
// src/main/java/example/gameday/journal/DutyRoster.java
package example.gameday.journal;

public class DutyRoster {

    private final String dutyName;

    public DutyRoster(String dutyName) {
        this.dutyName = dutyName;
    }

    public String currentDuty() {
        return dutyName;
    }
}
```

```java
// src/main/java/example/gameday/journal/Notifier.java
package example.gameday.journal;

public interface Notifier {

    void send(String dutyName, String text);
}
```

```java
// src/main/java/example/gameday/journal/ConsoleNotifier.java
package example.gameday.journal;

import org.springframework.stereotype.Component;

@Component
public class ConsoleNotifier implements Notifier {

    @Override
    public void send(String dutyName, String text) {
        System.out.println("[оповещение] " + dutyName + ": " + text);
    }
}
```

```java
// src/main/java/example/gameday/journal/IncidentLog.java
package example.gameday.journal;

import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Instant;

@Component
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock) {
        this.roster = roster;
        this.notifier = notifier;
        this.clock = clock;
    }

    public void add(String title) {
        Instant detectedAt = clock.instant();
        String dutyName = roster.currentDuty();
        notifier.send(dutyName, title + " — замечено " + detectedAt);
    }
}
```

```java
// src/main/java/example/gameday/journal/GameDayConfig.java
package example.gameday.journal;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
@ComponentScan
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
// src/main/java/example/gameday/journal/HandMadeApp.java
package example.gameday.journal;

import java.time.Clock;

public class HandMadeApp {

    public static void main(String[] args) {
        DutyRoster roster = new DutyRoster("duty-1");
        Notifier notifier = new ConsoleNotifier();
        Clock clock = Clock.systemUTC();
        IncidentLog log = new IncidentLog(roster, notifier, clock);

        log.add("Брокер не отвечает");
    }
}
```

```java
// src/main/java/example/gameday/journal/GameDayApp.java
package example.gameday.journal;

import org.springframework.context.annotation.AnnotationConfigApplicationContext;

public class GameDayApp {

    public static void main(String[] args) {
        AnnotationConfigApplicationContext context =
                new AnnotationConfigApplicationContext(GameDayConfig.class);
        IncidentLog log = context.getBean(IncidentLog.class);

        log.add("Брокер не отвечает");

        context.close();
    }
}
```

```java
// src/test/java/example/gameday/journal/RememberingNotifier.java
package example.gameday.journal;

import java.util.ArrayList;
import java.util.List;

class RememberingNotifier implements Notifier {

    final List<String> messages = new ArrayList<>();

    @Override
    public void send(String dutyName, String text) {
        messages.add(dutyName + ": " + text);
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentLogTest.java
package example.gameday.journal;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.assertj.core.api.Assertions.assertThat;

class IncidentLogTest {

    @Test
    void notifiesDutyWithDetectionTime() {
        RememberingNotifier notifier = new RememberingNotifier();
        Clock clock = Clock.fixed(Instant.parse("2026-10-05T09:15:00Z"), ZoneOffset.UTC);
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier, clock);

        log.add("Брокер не отвечает");

        assertThat(notifier.messages)
                .containsExactly("duty-1: Брокер не отвечает — замечено 2026-10-05T09:15:00Z");
    }
}
```
