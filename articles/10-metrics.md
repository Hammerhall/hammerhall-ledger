# Метрики: счётчик, датчик, таймер, теги — и дежурство в игровой день

> «От Spring к системе» · статья 10 · читать минут 35
>
> **Для кого.** Ты прочитал статьи 0–9, и у тебя есть песочница
> `game-day` после статьи 9: журнал в базе — `Incident`,
> `IncidentRepository`, `IncidentLog` (3б), вход по Basic (5), Actuator
> и стенд (6), а со статьи 9 у происшествия есть серьёзность —
> перечисление `Severity`.
>
> **Что будет.** Три прибора Micrometer — счётчик, датчик, таймер — и
> какой из них для какого вопроса. Почему тег стоит денег и какие теги
> нельзя никогда. Как число из кода доходит до панели, кого пускать
> к ручке метрик и как читать панель на дежурстве в игровой день.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Spring к системе» — следующий шаг
> после «От Java к Spring Boot»: как приложение живёт среди других
> программ. Примеры — учебные: их можно повторить у себя.

---

## Зачем метрики, если есть лог

Игровой день, 10:20. Тимлид атакует стенд уже двадцать минут. Дежурному
у мониторинга нужно понять две вещи: сколько происшествий открыто прямо
сейчас и растёт ли это число.

Лог — помнишь, строки, которые приложение пишет о своей работе, —
ответит, но дорого. В нём каждое событие отдельно: «10:04 заведено
„брокер молчит“», «10:11 закрыто…». Чтобы получить одно число, придётся
пересчитать все строки, а через минуту — снова. Лог похож на запись
с камеры у въезда: видна каждая машина, но чтобы узнать, сколько их
проехало за час, надо пересмотреть час записи.

**Метрика** — число, которое приложение показывает о себе снаружи:
«открыто 3», «заведено 47». Система мониторинга записывает его снова
и снова, и получается линия на графике. Это табло у шлагбаума: число
видно сразу, а по линии — быстро ли оно растёт.

```
IncidentLog → IncidentMetrics → MeterRegistry → ручка /actuator/prometheus
                                                   ▲ раз в интервал сбора её забирает
Prometheus: хранит числа с отметкой времени → Grafana: рисует панели → дежурный
```

Приложение держит текущие числа на своей ручке. **Prometheus** —
программа на сервере мониторинга — раз в интервал сбора сам забирает
их и хранит с отметкой времени. **Grafana** рисует по ним панели —
экраны с графиками. Подробно — в части 3.

🔑 Лог рассказывает о событии, метрика — о состоянии и темпе. Поэтому
дежурный в игровой день смотрит на панель, а не в лог: панель
показывает, что что-то изменилось, а в лог идут потом — узнать, что
именно.

Точное число знает только журнал в базе — Prometheus сам предупреждает,
что для стопроцентной точности не годится.

Сквозной пример — метрики журнала игрового дня: сколько заведено,
сколько открыто, сколько чинили. Журнал — учебный пример, но метрики
есть в каждом рабочем сервисе, и пишут их и джуны: сколько сообщений
обработано, сколько ждёт отправки, сколько длилась обработка. Что
посчитать, сказано в тексте задачи; статья объясняет то, чего там
обычно нет, — какой прибор взять, почему так и что сломается, если
иначе. А в песочнице метрики журнала будут видны вживую (часть 3).

Слова не путай: **журнал игрового дня** — наше учебное приложение;
**журнал дежурного** — записи дежурного у мониторинга: что он видел;
**журнал атаки** — куда тимлид записывает, что и когда ломал (оба —
в части 4); **лог** — строки приложения о своей работе.

В коротких примерах нет строк `import`, полные файлы — в конце статьи.

---

## Часть 1. Micrometer и три прибора

### Micrometer

**Micrometer** — библиотека Java для метрик. Метрику пишешь один раз
его классами, а в каком виде её отдать — для Prometheus или для другой
системы мониторинга, — решает он. Как переходник для розетки: прибор
один, а розетки в разных странах разные.

В учебных проектах приложение никто не наблюдает: запустил и закрыл.
Рабочее живёт неделями, и кто-то должен видеть, что с ним, не читая
код.

Micrometer приезжает вместе со стартером Actuator (статья 2) —
в песочнице он есть со статьи 6, и для него в `pom.xml` ничего
не добавляют. Версию, как и остальным библиотекам, задаёт `<parent>`
(статья 0): в Boot 4.1 это Micrometer 1.17. Запускать Micrometer не нужно, он работает внутри
приложения. Значения видно на ручке для Prometheus (часть 3), а в тесте —
в реестре (часть 2).

### Реестр

**Реестр** (`MeterRegistry`) — место, где живут все метрики приложения.
Метрику создают и сразу **регистрируют** в нём; кто хочет узнать
значения — Prometheus или тест, — спрашивает реестр.

Бин реестра создаёт Boot (автонастройка, статья 2): находит в проекте
библиотеку для Prometheus и заводит реестр под неё. Нет такой
библиотеки — заводит простой реестр в памяти: метрики считаются, но
отдать их наружу некому. Тебе остаётся попросить `MeterRegistry`
в конструкторе, как любую зависимость. Тесту Spring не нужен:
в Micrometer есть `SimpleMeterRegistry` — настоящий реестр в памяти,
который ничего никуда не отправляет.

### Счётчик — «сколько всего»

**Счётчик** (counter) только растёт: «сколько происшествий завели
с запуска». Уменьшить его нельзя.

```java
Counter reported = Counter.builder("gameday.incidents.reported")        // имя — слова через точку
        .description("Происшествия, заведённые в журнал игрового дня")  // подпись для людей
        .tag("severity", "high")                                        // тег — о нём часть 2
        .register(registry);                                            // завести в реестре

reported.increment();                                                   // +1
```

Цепочка `builder(…)…register(…)` — строитель (помнишь, статья 7):
каждый метод добавляет деталь, последний собирает объект. Так обычно заводят
метрики; у реестра есть и короткие методы вроде `registry.gauge(…)` —
с ним ниже связана ловушка.

Само число «47 с запуска» говорит мало — важен темп, сколько в минуту.
Его считает Prometheus (часть 3).

### Датчик — «сколько сейчас»

Число открытых происшествий растёт и падает — счётчик так не может.
Для «сколько сейчас» есть **датчик** (gauge — так он назван в коде):
как стрелка термометра.

Первая мысль — хранить число в памяти и двигать его самим:

```java
AtomicInteger open = registry.gauge("gameday.incidents.open", new AtomicInteger(0));   // вернёт тот же объект
open.incrementAndGet();          // в add: завели
open.decrementAndGet();          // в fixAll: закрыли
```

`AtomicInteger` — число-обёртка, которое безопасно менять из разных
потоков. Работает — до перезапуска. Приложение перезапустилось посреди
игры, число снова 0, а в базе пять открытых происшествий. Панель
говорит «всё закрыто» ровно тогда, когда это опаснее всего.

Правильный датчик ничего не хранит. Ему дают **объект и функцию**,
и при каждом **сборе** — когда значение спрашивает Prometheus или
тест — датчик вызывает функцию заново:

```java
Gauge.builder("gameday.incidents.open", incidents, IncidentRepository::countByFixedAtIsNull)
        .description("Происшествия, открытые прямо сейчас")
        .register(registry);
```

`incidents` — хранилище журнала, а ссылка на метод (статья 3б) здесь
значит «возьми хранилище и вызови у него `countByFixedAtIsNull`».
Метод — новая строка хранилища, подсчёт по имени, как `findBy…`:

```java
long countByFixedAtIsNull();          // select count(…) from … where fixed_at is null
```

Источник правды — база, и после перезапуска датчик покажет то же, что
в ней. Цена — запрос на каждый сбор; для таблицы журнала это копейки.
Так в рабочих проектах считают всё, что «сейчас» лежит в базе: сколько
сообщений ждёт отправки, сколько застряло.

⚠️ Частая ошибка — `registry.gauge("…", incidents.countByFixedAtIsNull())`:
число посчитано один раз, при регистрации. Датчик показывает его, хоть
открытых уже двадцать, а после сборки мусора может показать и `NaN`
(слабая ссылка — ниже).

### ⚠️ Слабая ссылка

Micrometer держит объект датчика **слабой ссылкой** — такой, которая
не мешает сборщику мусора убрать объект. (Сборщик мусора — механизм JVM:
освобождает память от объектов, на которые никто не ссылается.) Если
объект датчика больше никто не держит, его уберут, и датчик начнёт
показывать `NaN` — «значения нет». Документация Micrometer говорит
прямо: держать объект — твоя забота.

Хранилище держит Spring — с ним беды не будет. `AtomicInteger` из
первой попытки держат в поле: без присваивания — `NaN` через какое-то
время. В тесте реестр, заглушки и класс метрик тоже держат в полях.

💡 Посмотри сам: `WeakDemo.java` из конца статьи запускается командой
`java WeakDemo.java` — Java сама скомпилирует один файл. Объект,
который держит переменная, переживёт сборку мусора (`3.0`), а который
не держит никто — нет (`NaN`).

### Таймер — «сколько длилось»

После игры тимлид спросит: сколько в среднем чинили происшествие? Для
длительностей есть **таймер** (timer): каждое `record(…)` добавляет
событие и его длительность.

```java
Timer fixDuration = Timer.builder("gameday.incident.fix.duration")
        .description("От «заметили» до «починили»")
        .register(registry);

fixDuration.record(Duration.ofMinutes(25));          // одно происшествие чинили 25 минут
```

В Prometheus таймер приходит тремя числами: сколько событий, сколько
времени всего и самое долгое за последние минуты. Среднее — сумма,
делённая на число, его посчитает панель. Счётчик «сколько починили»
не нужен: таймер считает события сам — так советует и Micrometer.

Длительность — от `detectedAt` до `fixedAt`, её даёт
`Duration.between(начало, конец)`. Отрицательную длительность таймер
молча пропустит — ни ошибки, ни события. Но `fix` и не даст починить
раньше, чем заметили (статья 3б).

**Сводка** (distribution summary) — то же для величин, которые не
время: скажем, сколько происшествий закрыли одним `fixAll`.

### Имена: точка в коде, подчёркивание в Prometheus

В Micrometer имя — слова маленькими буквами через точку. В Prometheus
точек в имени быть не может, и реестр переводит имя сам: точки меняет
на подчёркивания и добавляет окончания.

| в коде | прибор | в Prometheus |
|---|---|---|
| `gameday.incidents.reported` | счётчик | `gameday_incidents_reported_total` |
| `gameday.incidents.open` | датчик | `gameday_incidents_open` |
| `gameday.incident.fix.duration` | таймер | `gameday_incident_fix_duration_seconds_count`, `…_sum`, `…_max` |

`_total` — так Prometheus метит накопительный счёт. `_seconds` —
единица: время в Prometheus держат в секундах, и таймер из минут
переведётся сам. Поэтому у таймера единицу в имя не пишут. И не
пугайся, открыв панель:
`gameday.incidents.open` в коде и `gameday_incidents_open` на панели —
одна метрика.

---

## Часть 2. Теги, IncidentMetrics и тест без Spring

### Тег — разрез одной метрики

Два критических происшествия и восемь мелких — разные беды. Можно
завести три счётчика с разными именами, но удобнее один с **тегом** —
парой «ключ = значение», которая делит метрику на части:
`severity=critical`, `severity=high`, `severity=low`. В Prometheus
теги называются **метками** (labels) — это одно и то же.

Тег `severity` — серьёзность, перечисление `Severity` из статьи 9;
значение тега — её код: `low`, `high`, `critical`. Код, а не Java-имя
`HIGH`: помнишь правило из статьи 9 — «одно понятие — одно написание
везде», и в базе серьёзность лежит тем же кодом. В рабочем проекте
значения тегов пишут маленькими буквами.

### Ряд и цена тега

Prometheus хранит каждое сочетание «имя + значения тегов» отдельно,
своей линией во времени. Это **ряд** (time series). Новое значение
тега — новый ряд: своя память, своё место на диске.

Рядов у метрики — произведение числа значений всех её тегов.
У `severity` три значения — три ряда. Да и сам Prometheus, забирая
метрики, приписывает каждому ряду, откуда его взял: метку `job` —
какую цель сбора он обходил (о цели — в части 3) — и `instance` —
адрес экземпляра приложения. Приложение отдаёт три ряда; запусти его
в двух экземплярах — у Prometheus их станет 3 × 2 = 6. Это нормально:
значений мало, все известны заранее.

В рабочих проектах к метрикам добавляют и **общие теги** — одинаковые
для всех метрик приложения, например его имя. В Boot их задают бином
`MeterRegistryCustomizer`. В песочнице общих тегов нет, поэтому
на ручке тег будет только у счётчика журнала — `severity`.

А теперь добавь тег `incident` с номером происшествия. Каждое новое
происшествие заведёт свой ряд, в котором навсегда будет одна единица.
Сезон игр — тысячи рядов, которые ничего не говорят. Это **взрыв
кардинальности** (кардинальность — число разных рядов у метрики):
Prometheus тратит память на мусор, а однажды ложится.

🔴 В тегах никогда не бывает:

* номера происшествия, идентификатора человека, номера заказа — их
  значениям нет счёта;
* адреса почты, имени человека — это ещё и личные данные, а метрики
  видит больше людей, чем базу. Имя дежурного в тег не кладут по обеим
  причинам;
* текста «как пришёл»: заголовка происшествия, сообщения об ошибке.

Тег годится, только если его значения можно перечислить заранее и их
немного. «Какое именно происшествие?» — вопрос к журналу, а не
к метрике.

### Ряды с нулём — с первой секунды

Если заводить счётчик `severity=critical` при первом критическом
происшествии, до него ряда нет вовсе. А нет ряда — это не ноль, а «нет
данных»: панель пуста, и **тревога** — сигнал людям, когда число
перешло порог, — не отличит «критических не было» от «метрика
сломалась». Страдает и темп (часть 3): ряд родится сразу с единицей,
точки «ноль» перед ней у Prometheus нет, и первую единицу темп может
не посчитать. Поэтому все ряды заводят сразу, с нулём.

### IncidentMetrics

Все метрики журнала — в одном бине. Он помощник, а не служба: ни логики
журнала, ни транзакций (статья 3б), — поэтому `@Component`, как бины
в статье 1.

```java
@Component
public class IncidentMetrics {

    // серьёзность → её счётчик
    private final Map<Severity, Counter> counters = new EnumMap<>(Severity.class);
    private final Timer fixDuration;

    public IncidentMetrics(MeterRegistry registry, IncidentRepository incidents) {
        // ряд на каждую серьёзность — сразу, с нулём
        for (Severity severity : Severity.values()) {
            counters.put(severity, Counter.builder("gameday.incidents.reported")
                    .description("Происшествия, заведённые в журнал игрового дня")
                    .tag("severity", severity.code())
                    .register(registry));
        }
        Gauge.builder("gameday.incidents.open", incidents, IncidentRepository::countByFixedAtIsNull)
                .description("Происшествия, открытые прямо сейчас")
                .register(registry);
        fixDuration = Timer.builder("gameday.incident.fix.duration")
                .description("От «заметили» до «починили»")
                .register(registry);
    }

    public void reported(Severity severity) {
        // понятная ошибка вместо голого исключения
        Objects.requireNonNull(severity, "метрика журнала: нет серьёзности");
        counters.get(severity).increment();
    }

    public void fixed(Duration timeToFix) {
        fixDuration.record(timeToFix);
    }
}
```

`EnumMap` — карта «ключ → значение», где ключи — значения
перечисления. Без `Objects.requireNonNull` вызов `counters.get(null)`
вернул бы `null`, и `increment()` упал бы с `NullPointerException` без
слова о том, чего не хватило. С ним исключение то же, но с нашим
текстом.

### Журнал считает

`IncidentLog` получает пятую зависимость — `IncidentMetrics metrics`.
Строка встаёт в `add(title, severity)` из статьи 9, сразу после
сохранения; прежний `add(title)` зовёт его с `LOW` и тоже посчитается:

```java
metrics.reported(incident.getSeverity());            // сохранили — посчитали
```

⚠️ Пятый параметр конструктора ломает два теста: `IncidentLogTest`
из статьи 5 и `IncidentLogAgeTest` из статьи 9. Оба создают журнал
с четырьмя, и тесты песочницы перестанут компилироваться. Добавь в каждый
заглушку `@Mock IncidentMetrics metrics` и передай её пятой.
`IncidentLogIT` из статьи 3б править не нужно: `IncidentMetrics` —
`@Component`, и Spring соберёт его сам из `MeterRegistry`, который
заводит Boot, — Actuator в песочнице есть.

С `fixAll` внимательнее. Помнишь откат из статьи 3б: закрыли три
происшествия, на четвёртом ключе ошибка — база откатилась. А метрику
транзакция не откатывает: она живёт в памяти, а не в базе. Вызови
`fixed` внутри цикла — и таймер запомнит три починки, которых не было.
Поэтому метрики — после цикла, когда все ключи прошли:

```java
    @Transactional
    public void fixAll(List<UUID> ids) {
        Instant now = clock.instant();
        List<Incident> fixed = new ArrayList<>();
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("нет происшествия " + id));
            incident.fix(now);
            incidents.save(incident);
            fixed.add(incident);                             // пока только запомнили
        }
        for (Incident incident : fixed) {                    // дошли сюда — все ключи верны
            metrics.fixed(Duration.between(incident.getDetectedAt(), now));
        }
    }
```

💡 Край остался: метод вышел, а фиксация в базе не удалась — таймер
уже посчитал. Для журнала терпимо: метрика про темп. Как записать
метрику строго после фиксации — в рабочем проекте это решает мидл.

### Тест без Spring

Метрику проверяют юнит-тестом: реестр — `SimpleMeterRegistry`,
хранилище — заглушка Mockito `mock(…)` (статья 5), класс метрик —
обычный `new`. Значение спрашивают у реестра — так же, как спросит
Prometheus:

```java
class IncidentMetricsTest {

    // настоящий реестр, в памяти
    private final SimpleMeterRegistry registry = new SimpleMeterRegistry();
    // в поле — слабая ссылка не страшна
    private final IncidentRepository incidents = mock(IncidentRepository.class);
    private final IncidentMetrics metrics = new IncidentMetrics(registry, incidents);

    @Test
    void countsCriticalSeparately() {
        metrics.reported(Severity.CRITICAL);

        assertThat(registry.get("gameday.incidents.reported").tag("severity", "critical").counter().count())
                .isEqualTo(1.0);
    }

    @Test
    void timerCountsAndSums() {
        metrics.fixed(Duration.ofMinutes(10));
        metrics.fixed(Duration.ofMinutes(30));

        Timer timer = registry.get("gameday.incident.fix.duration").timer();
        assertThat(timer.count()).isEqualTo(2);                        // событий
        assertThat(timer.totalTime(TimeUnit.MINUTES)).isEqualTo(40.0); // времени всего, в минутах
    }
}
```

`registry.get(…)` — строгий поиск: метрики нет — исключение, и тест
скажет, что её забыли завести. `find(…)` — мягкий:
`registry.find(…).tag(…).counter()` вернёт `null`, если такого ряда
нет. `TimeUnit.MINUTES` — в каких единицах хотим ответ.

Здесь — приём, а не полный набор. В рабочем проекте случаи для метрик
перечисляет таблица в тексте задачи, и обычно в ней есть такие: «новых
рядов не появилось», «без значения — исключение с понятным текстом»,
«датчик спрашивает заново, а не помнит». ⚠️ Одно запомни уже сейчас:
функция датчика выполняется только при чтении. Тест, который значение
не читает, покроет строки, но не проверит ничего.

---

## Часть 3. От реестра до панели

Схему ты видел в начале.

### Actuator и ручка для Prometheus

Actuator — помнишь, статья 2: служебные адреса приложения; в песочнице
со статьи 6 он отвечает на `/actuator/health`. Адрес каждой его ручки —
`/actuator/` плюс её имя.

Ручку `prometheus` приносит библиотека `micrometer-registry-prometheus`:
найдя её, Boot заводит реестр для Prometheus и ручку
`/actuator/prometheus`. В рабочем проекте зависимости добавляет мидл,
в песочнице — ты сам:

```xml
<dependency>                                   <!-- реестр для Prometheus и ручка /actuator/prometheus -->
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
    <scope>runtime</scope>                     <!-- нужна запущенному приложению -->
</dependency>
```

`groupId` не Boot, а Micrometer, но версию всё равно подставит
`<parent>`: Boot знает и её. `runtime` — помнишь из статьи 3а: в нашем
коде нет ни одного класса Prometheus, библиотека нужна только
при запуске.

Ручку мало завести — её надо открыть: по HTTP Boot по умолчанию
открывает только `health`. Какие открыть — настройка
в `application.yml`:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,prometheus        # какие ручки Actuator открыть по HTTP
```

`health` в списке оставь: список заменяет умолчание, а не дописывается
к нему. Напишешь `include: prometheus` — пропадёт health, а с ним
и проверка здоровья стенда из статьи 6.

⚠️ Забудешь `prometheus` в `include` — ручки не будет, и даже `admin`
получит `404`: охрана пропустила, а отвечать некому.

🔴 Открывай только нужное: ручки Actuator много рассказывают
о приложении. Документация Boot требует убедиться, что в них нет
чувствительного, или спрятать их от чужих.

### 🔴 Метрики — только со входом

Открыть ручку по HTTP и пустить к ней всех — не одно и то же. Пускает
охрана из статьи 5, а `/actuator/prometheus` в её правилах нет:
сработает `denyAll`. Без входа — `401`, под `admin` — `403`.

Почему health в статье 6 открыли без входа, а метрики — нет? Health
отвечает одним словом, `UP` или `DOWN`, а спрашивают его Docker и
скрипт стенда — у них пароля нет. Метрики рассказывают куда больше:
сколько происшествий и какой серьёзности, какие у приложения адреса
и сколько к ним ходят, сколько памяти и подключений к базе. Взломщику
это карта. А Prometheus, в отличие от проверки здоровья в Docker,
входить умеет: в настройке цели сбора ему дают имя и пароль.

Правило — в `SecurityConfig`, выше `denyAll`:

```java
http.authorizeHttpRequests(access -> access
        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
        .requestMatchers(HttpMethod.GET, "/actuator/health").permitAll()
        .requestMatchers(HttpMethod.GET, "/actuator/prometheus").hasRole("admin")   // метрики — со входом
        .requestMatchers(HttpMethod.GET, "/game-day/incidents").hasRole("admin")
        …
```

В песочнице метрики смотрит `admin`: другого пользователя с правами
у нас нет. В настоящем сервисе системе мониторинга обычно заводят свой
вход с одним правом — читать метрики — или выносят ручки Actuator на
отдельный порт, закрытый от внешней сети. Как именно — в рабочем
проекте решает мидл.

Правило — ровно на один адрес, как для health: `/actuator` и остальные
ручки Actuator по-прежнему закрыты.

💡 Тест периметра из статьи 5 этот адрес не видит, как и health: он
сверяет ручки наших контроллеров. Кого пускают к ручкам Actuator,
сверяет ревьюер — по `SecurityConfig`.

⚠️ В интернете для тестов с метриками на всём приложении ты увидишь
`@AutoConfigureObservability`. Это Boot 3; в Boot 4 её нет, вместо неё —
`@AutoConfigureMetrics` из модуля `spring-boot-micrometer-metrics-test`.
Нам не нужна ни одна: метрики проверяем без Spring.

### Что лежит на ручке

Ответ ручки — простой текст, строка на ряд. Так выглядел бы журнал
после игры: три критических происшествия и одно мелкое; два открыты,
а два других чинили 10 и 30 минут. Строки собраны из разных мест
ответа:

```
# HELP gameday_incidents_open Происшествия, открытые прямо сейчас
# TYPE gameday_incidents_open gauge
gameday_incidents_open 2.0
gameday_incidents_reported_total{severity="critical"} 3.0
gameday_incidents_reported_total{severity="high"} 0.0
gameday_incidents_reported_total{severity="low"} 1.0
gameday_incident_fix_duration_seconds_count 2
gameday_incident_fix_duration_seconds_sum 2400.0
gameday_incident_fix_duration_seconds_max 1800.0
```

`# HELP` — описание из `.description(…)`: по нему дежурный понимает,
что перед ним, не открывая код. `# TYPE` — прибор: `gauge` — датчик.

Числа — с точкой, `2.0`: Prometheus все значения держит дробными.
Целое здесь одно — число событий таймера, `2`. Сорок минут таймер
отдал секундами, `2400.0`, а самое долгое — `1800.0`, полчаса. Тег
`severity` — в фигурных скобках; у остальных метрик журнала тегов нет,
и скобок тоже.

### Посмотри вживую

В песочнице ручку видно по-настоящему. Подними базу — `docker run`
из статьи 3а — и запусти песочницу, как в статье 5: три переменные
`SPRING_DATASOURCE_*`, затем `./mvnw package`
и `java -jar target/game-day-0.0.1-SNAPSHOT.jar` (или из IDE). Сначала —
без входа:

```bash
curl -i http://127.0.0.1:8080/actuator/prometheus
```

```
HTTP/1.1 401
WWW-Authenticate: Basic realm="Realm"
…
```

Как у журнала: «войди по Basic». Под `viewer` — `403`. Теперь под
`admin`, и только строки журнала:

```bash
curl -s -u admin:admin-local http://127.0.0.1:8080/actuator/prometheus | grep '^gameday'
```

`-s` — молча, `|` — конвейер (оба — статья 6): ответ `curl` идёт
в `grep`, а тот оставляет строки, которые начинаются (`^`) с `gameday`.

```
gameday_incident_fix_duration_seconds_count 0
gameday_incident_fix_duration_seconds_sum 0.0
gameday_incident_fix_duration_seconds_max 0.0
gameday_incidents_open 1.0
gameday_incidents_reported_total{severity="critical"} 0.0
gameday_incidents_reported_total{severity="high"} 0.0
gameday_incidents_reported_total{severity="low"} 1.0
```

Открыто одно — «Брокер не отвечает»: его записал запуск приложения
через `add(String)`, то есть с `LOW`. Ряды `critical` и `high` — с нулём,
как и обещали. Таймер пуст: в песочнице нет ручки, которая закрывает
происшествия, — чинить нечем.

Теперь заведи происшествие мимо журнала — прямо в базе, `psql`
в контейнере (статья 3а):

```bash
docker exec game-day-db psql -U postgres \
    -c "INSERT INTO game_day.incident (title, detected_at, duty_name) VALUES ('лента стоит', now(), 'duty-2')"
```

Спроси ручку снова: `gameday_incidents_open 2.0` — датчик спросил базу
заново, без перезапуска. А `low` остался `1.0`: строку вставили в обход
`IncidentLog`, и считать было некому. Серьёзность новая строка взяла
из `DEFAULT` миграции (статья 9).

Останови приложение (`Ctrl+C`) и запусти снова. `low` — опять `1.0`:
счётчик живёт в памяти и после перезапуска начал с нуля, а новый запуск
записал ещё одного «Брокера». А открытых — `3.0`: два прежних из базы
и новый. Ровно ради этого датчик спрашивает базу.

Рядом с метриками журнала — те, что Boot заводит сам: память JVM
(`jvm_memory_used_bytes`), запросы к ручкам. Сходи в журнал под
`admin` — `curl -u admin:admin-local http://127.0.0.1:8080/game-day/incidents` —
и найди на ручке метрик таймер Boot:
`http_server_requests_seconds_count{…,uri="/game-day/incidents"} 1`.
Число событий — то же `_seconds_count`, что у нашего таймера.

### Prometheus

Prometheus нужен, потому что приложение знает только «сейчас»,
а дежурному нужны и последние полчаса. Что и откуда забирать, ему
говорит **цель сбора** (scrape target) в его настройках: адрес ручки,
как часто ходить, с каким именем и паролем. В рабочем проекте
Prometheus живёт на сервере мониторинга, цели сбора заводит мидл,
и ставить Prometheus джуну не нужно.

В песочнице Prometheus нет — его работу ты сделал руками, `curl`. На
стенде из статьи 6 его подняли бы ещё одной службой compose: образ
Prometheus и файл настроек, где цель сбора — `game-day:8080`, путь
`/actuator/prometheus`, имя и пароль; приложение он нашёл бы по имени
службы, как приложение находит базу. Рядом — служба Grafana, которой
сказано, где Prometheus. Это отдельная тема, и статья её не строит.

По счётчику Prometheus считает **темп** за **окно** — отрезок времени
в квадратных скобках. `increase(gameday_incidents_reported_total{severity="critical"}[5m])` —
сколько критических завели за последние пять минут; `rate(…[5m])` —
то же в среднем за секунду. Сброс в ноль после перезапуска оба
учитывают сами; у датчика темп не считают.

### Grafana

Grafana метрик не хранит: каждая панель — запрос к Prometheus, ответ
она рисует линией. В рабочем проекте панели и тревоги строят мидлы,
а смотрят их все — на игровом дне особенно. Открыв панель, сначала
проверь **диапазон времени** (последний час, а не «вчера») и
**автообновление** — иначе линия стоит, потому что стоит страница.

---

## Часть 4. Дежурство в игровой день

### Как читать панель

У каждой формы линии свой смысл. На панелях журнала:

| что видишь | что это может значить |
|---|---|
| **рост**: «открытые» ползут вверх | заводят быстрее, чем чинят: атака идёт, мидлы не успевают |
| **скачок темпа**: `critical` с нуля пошёл вверх | атака началась, бьют по важному |
| **плато**: «открытые» двадцать минут стоят на 4 | никто не заводит и не чинит — застряли; или закрытия не доходят до журнала |
| **плато на нуле** у темпа | тихо — или журнал перестал принимать записи |
| **обрыв**: линия кончилась, дальше пусто | Prometheus не может забрать метрики: приложение лежит или до него не достать |
| **провал до нуля** у самого счётчика | приложение перезапустилось; темп это переживёт |

**«Ноль» и «нет данных» — разные вещи.** Ноль: «проверили — ничего
нет». Пусто: «проверить не смогли». Поэтому ряды заводят с нулём. А
датчик, который не смог узнать значение, отдаёт не 0, а `NaN`. На
графике `NaN` обычно рисуется разрывом — как обрыв. Отличить просто:
при обрыве пропадают сразу все метрики приложения, а `NaN` — у одной.

Проверь в песочнице. Останови базу — `docker stop game-day-db` — и
спроси ручку метрик той же командой. Ответ придёт не сразу: датчик
спрашивает базу, а приложение сперва ждёт подключения к ней. Потом
строки таймера — прежние, а остальные такие:

```
gameday_incidents_open NaN
gameday_incidents_reported_total{severity="critical"} 0.0
gameday_incidents_reported_total{severity="high"} 0.0
gameday_incidents_reported_total{severity="low"} 1.0
```

Счётчики живут в памяти и на месте, а «открытые» узнать неоткуда. Ноль
был бы неправдой: «открытых нет». В логе приложения — предупреждение
`Failed to apply the value function for the gauge 'gameday.incidents.open'`:
функция датчика упала, Micrometer поймал исключение и отдал `NaN`.
С `--rm` база ушла вместе с учебными строками; приложение останови.

Помни и про задержку: точка появляется после сбора и обновления панели.
Атака в 10:00, панель дрогнула в 10:02 — это данные, а не поломка;
в журнале дежурного такую задержку записывают как есть.

### Журнал дежурного

В рабочем проекте игровой день устроен так. Тимлид атакует стенд,
мидлы чинят, а дежурный у мониторинга смотрит и записывает — **но
не чинит**, даже если видит причину: пока он чинит, он не смотрит,
и следующую атаку панели покажут пустому стулу. Записи — в журнал
дежурного, строка на событие, а не каждые десять секунд.

Что в строке и зачем:

* **время** — в поясе, о котором до игры договорились с тимлидом,
  иначе сверка с журналом атаки разъедется на три часа;
* **что увидел** — панель и числа: «открытые: с 0 до 3 за 4 минуты»,
  а не «что-то сломалось»;
* **что это значит, по мнению дежурного** — догадка; права ли она,
  покажет сверка;
* **кому сказал** — дежурный будит того, кто чинит.

Для журнала игрового дня строки могли бы выглядеть так:

| время | что увидел | что это значит | кому сказал |
|---|---|---|---|
| 10:04 | «открытые» 0 → 3 за 4 мин; `critical` за 5 мин — 3 | атака началась, бьют по важному | мидлам, в чат игры |
| 10:31 | все панели журнала оборвались в 10:29 | журнал лежит или Prometheus его не видит | тимлиду и мидлам |
| 10:40 | мидлы говорят: письма не уходят; на панелях журнала тихо | атака мимо журнала; что её должно видеть? | тимлиду |

🔑 Третья строка — самая ценная. **Атака была, а панель промолчала** —
это дыра в мониторинге, и найдёт её только тот, кто записывает и
молчание. Мидл, который строил панели, мысленно достраивает
недостающее; свежий глаз — нет. Поэтому «ничего не заметил» в журнале
дежурного — тоже находка, а не провал.

После игры журнал дежурного сверяют с журналом атаки: увидел ли
мониторинг каждую атаку, когда, какой панелью, — и пишут выводы. Если
стенд в игре ещё и нагружают, до игры записывают и условие остановки:
при каком сигнале на панели атаку прекращают.

### Где граница

Какие метрики нужны сервису вообще — подходы RED (темп запросов,
ошибки, длительность) и USE (загрузка, насыщение, ошибки), — какие
тревоги ставить и с каким порогом, чем для очереди возраст самого
старого сообщения отличается от её длины, перцентили таймера («95 из
100 событий уложились в …») — в рабочем проекте это решают мидлы. Джун
пишет метрики по тексту задачи и тест на них, а на игровом дне ведёт
честный журнал дежурного. Здесь эти слова — чтобы ты узнал их, когда
встретишь.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Чем метрика отличается от строки лога? Почему дежурный смотрит на
   панель, а точное число происшествий берут из базы?
2. Какой прибор нужен для «сколько завели», «сколько открыто сейчас»,
   «сколько чинили»? Почему рядом с таймером не заводят счётчик?
3. Почему датчик открытых спрашивает базу, а не хранит `AtomicInteger`,
   и когда датчик показывает `NaN`? Что показали счётчик и датчик
   в песочнице после перезапуска?
4. Сколько рядов у счётчика с тегом `severity`? Что будет с тегом-номером
   происшествия? Почему имени дежурного в теге не место?
5. Зачем ряды с нулём заводят сразу? Чем «ноль» отличается от «нет
   данных» на панели?
6. Почему `metrics.fixed(…)` в `fixAll` вызывается после цикла?
7. Как число из `IncidentMetrics` попадает на панель? Кто кого
   спрашивает, что открывают в Actuator и почему ручка метрик — со
   входом, а health — без?
8. Что дежурный пишет в строку журнала? Почему «панель промолчала» —
   самая ценная строка и почему дежурный не чинит сам?

---

## Что дальше

Дальше в серии — тесты-сторожа: тесты, которые читают код проекта
и следят за его правилами. Скажем, что «сейчас» в журнале берут только
из часов, а не из `Instant.now()`.

## Первоисточники

* [Micrometer: Gauges](https://docs.micrometer.io/micrometer/reference/concepts/gauges.html) —
  датчик опрашивают, а не устанавливают; слабая ссылка и `NaN`;
* [Micrometer: Timers](https://docs.micrometer.io/micrometer/reference/concepts/timers.html) —
  что записывает таймер и чем он лучше счётчика для длительностей;
* [Micrometer: Prometheus](https://docs.micrometer.io/micrometer/reference/implementations/prometheus.html) —
  как Prometheus забирает метрики и какие ряды даёт таймер;
* [Spring Boot: Endpoints](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html) —
  ручки Actuator: какие открыты по умолчанию, как открыть остальные
  и почему их прячут от чужих;
* [Spring Boot: Metrics](https://docs.spring.io/spring-boot/reference/actuator/metrics.html) —
  какой реестр заводит Boot, ручка `/actuator/prometheus`, общие теги
  и метрики, которые Boot считает сам;
* [Prometheus: Metric and label naming](https://prometheus.io/docs/practices/naming/) —
  единицы, `_total` и почему в метках не место номерам и адресам;
* [Prometheus: Jobs and instances](https://prometheus.io/docs/concepts/jobs_instances/) —
  какие метки Prometheus приписывает рядам сам.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 9: Postgres
в контейнере, миграции `V1` и `V2`, журнал в `example.gameday.journal`
с хранилищем, ручками статей 4–5, объектами-значениями статьи 8
и серьёзностью статьи 9, охрана, Actuator и стенд статьи 6 — всё
остаётся. Micrometer и бин `MeterRegistry` уже есть — их принёс
Actuator; JUnit, AssertJ и Mockito — со `spring-boot-starter-test`.

Что добавить: в `pom.xml` — `micrometer-registry-prometheus`;
в `example.gameday.journal` — `IncidentMetrics`, там же под
`src/test/java` — `IncidentMetricsTest`.

Что поменять: в `application.yml` — открытые ручки Actuator;
в `SecurityConfig` — правило для `/actuator/prometheus`;
в `IncidentRepository` — подсчёт открытых; в `IncidentLog` — пятая
зависимость и метрики в `add` и `fixAll`; в `IncidentLogTest` (статья 5)
и `IncidentLogAgeTest` (статья 9) — пятая заглушка, иначе тесты
не скомпилируются. Эти файлы ниже целиком, новые строки помечены
комментарием «статья 10». Остальное — `Incident`, `Severity`, `DutyRoster`,
`Notifier`, `GameDayConfig` с часами, службы, контроллеры, миграции
и тесты прошлых статей — без изменений.

Запуск: один класс — треугольником в IDE или
`./mvnw test -Dtest=IncidentMetricsTest`; весь `./mvnw verify` гоняет
и `*IT` — нужен запущенный Docker. Путь к файлу — комментарием в первой
строке.

```xml
<!-- pom.xml: в <dependencies>, рядом с тем, что уже есть -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
    <scope>runtime</scope>
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
management:                                       # статья 10
  endpoints:
    web:
      exposure:
        include: health,prometheus
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

/** Охрана песочницы: вход по Basic, пользователи в памяти; журнал и метрики — только admin, health — всем. */
@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain security(HttpSecurity http) {
        http.authorizeHttpRequests(access -> access
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        .requestMatchers(HttpMethod.GET, "/actuator/health").permitAll()
                        .requestMatchers(HttpMethod.GET, "/actuator/prometheus").hasRole("admin") // статья 10
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

Хранилище — целиком, с методами статей 3б, 5 и 9:

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

    long countByFixedAtIsNull();                                          // статья 10
}
```

```java
// src/main/java/example/gameday/journal/IncidentMetrics.java
package example.gameday.journal;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.EnumMap;
import java.util.Map;
import java.util.Objects;

@Component
public class IncidentMetrics {

    private final Map<Severity, Counter> counters = new EnumMap<>(Severity.class);
    private final Timer fixDuration;

    public IncidentMetrics(MeterRegistry registry, IncidentRepository incidents) {
        for (Severity severity : Severity.values()) {
            counters.put(severity, Counter.builder("gameday.incidents.reported")
                    .description("Происшествия, заведённые в журнал игрового дня")
                    .tag("severity", severity.code())
                    .register(registry));
        }
        Gauge.builder("gameday.incidents.open", incidents, IncidentRepository::countByFixedAtIsNull)
                .description("Происшествия, открытые прямо сейчас")
                .register(registry);
        fixDuration = Timer.builder("gameday.incident.fix.duration")
                .description("От «заметили» до «починили»")
                .register(registry);
    }

    public void reported(Severity severity) {
        Objects.requireNonNull(severity, "метрика журнала: нет серьёзности");
        counters.get(severity).increment();
    }

    public void fixed(Duration timeToFix) {
        fixDuration.record(timeToFix);
    }
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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class IncidentLog {

    private final DutyRoster roster;
    private final Notifier notifier;
    private final Clock clock;
    private final IncidentRepository incidents;
    private final IncidentMetrics metrics;                                       // статья 10

    public IncidentLog(DutyRoster roster, Notifier notifier, Clock clock,
                       IncidentRepository incidents, IncidentMetrics metrics) {  // статья 10: пятый параметр
        this.roster = roster;
        this.notifier = notifier;
        this.clock = clock;
        this.incidents = incidents;
        this.metrics = metrics;                                                  // статья 10
    }

    public void add(String title) {
        add(title, Severity.LOW);
    }

    public void add(String title, Severity severity) {
        Incident incident = incidents.save(
                new Incident(title, clock.instant(), roster.currentDuty(), severity, Map.of()));
        metrics.reported(incident.getSeverity());                                // статья 10
        notifier.send(incident.getDutyName(), title + " — замечено " + incident.getDetectedAt());
    }

    @Transactional
    public void fixAll(List<UUID> ids) {
        Instant now = clock.instant();
        List<Incident> fixed = new ArrayList<>();                                // статья 10
        for (UUID id : ids) {
            Incident incident = incidents.findById(id)
                    .orElseThrow(() -> new IllegalArgumentException("нет происшествия " + id));
            incident.fix(now);
            incidents.save(incident);
            fixed.add(incident);                                                 // статья 10
        }
        for (Incident incident : fixed) {                                        // статья 10: после цикла
            metrics.fixed(Duration.between(incident.getDetectedAt(), now));
        }
    }

    public List<Incident> openLongerThan(Duration age) {
        Instant border = clock.instant().minus(age);
        return incidents.findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(border);
    }
}
```

Тесты статей 5 и 9 — с пятой заглушкой, иначе не скомпилируются:

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

    @Mock
    private IncidentMetrics metrics;                                             // статья 10

    @Test
    void addNotifiesDutyWithDetectionTime() {
        when(incidents.save(any(Incident.class))).thenAnswer(call -> call.getArgument(0));
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(T0, ZoneOffset.UTC), incidents, metrics);           // статья 10: metrics

        log.add("Брокер не отвечает");

        verify(notifier).send("duty-1", "Брокер не отвечает — замечено 2026-10-05T09:15:00Z");
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

    @Mock
    private IncidentMetrics metrics;                                             // статья 10

    @Test
    void borderIsNowMinusAge() {
        IncidentLog log = new IncidentLog(new DutyRoster("duty-1"), notifier,
                Clock.fixed(Instant.parse("2026-10-05T10:00:00Z"), ZoneOffset.UTC), incidents,
                metrics);                                                        // статья 10

        log.openLongerThan(Duration.ofMinutes(30));

        verify(incidents).findByFixedAtIsNullAndDetectedAtBeforeOrderByDetectedAtAsc(
                Instant.parse("2026-10-05T09:30:00Z"));
    }
}
```

```java
// src/test/java/example/gameday/journal/IncidentMetricsTest.java
package example.gameday.journal;

import io.micrometer.core.instrument.Timer;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

class IncidentMetricsTest {

    private final SimpleMeterRegistry registry = new SimpleMeterRegistry();
    private final IncidentRepository incidents = mock(IncidentRepository.class);
    private final IncidentMetrics metrics = new IncidentMetrics(registry, incidents);

    @Test
    void countsCriticalSeparately() {
        metrics.reported(Severity.CRITICAL);

        assertThat(registry.get("gameday.incidents.reported").tag("severity", "critical").counter().count())
                .isEqualTo(1.0);
    }

    @Test
    void timerCountsAndSums() {
        metrics.fixed(Duration.ofMinutes(10));
        metrics.fixed(Duration.ofMinutes(30));

        Timer timer = registry.get("gameday.incident.fix.duration").timer();
        assertThat(timer.count()).isEqualTo(2);
        assertThat(timer.totalTime(TimeUnit.MINUTES)).isEqualTo(40.0);
    }
}
```

`WeakDemo.java` — обычная Java, без Spring; положи куда угодно — хоть
в корень песочницы — и запусти `java WeakDemo.java`:

```java
// WeakDemo.java
import java.lang.ref.WeakReference;
import java.util.concurrent.atomic.AtomicInteger;

public class WeakDemo {

    public static void main(String[] args) throws InterruptedException {
        AtomicInteger kept = new AtomicInteger(3);                    // его держит переменная
        WeakReference<AtomicInteger> keptRef = new WeakReference<>(kept);
        // а объект AtomicInteger(5) не держит никто
        WeakReference<AtomicInteger> lostRef = new WeakReference<>(new AtomicInteger(5));

        System.gc();                                                  // попросить сборщик мусора поработать
        Thread.sleep(100);

        System.out.println("держим:    " + value(keptRef));          // 3.0
        System.out.println("не держим: " + value(lostRef));          // NaN
        kept.incrementAndGet();                                       // переменная нужна и после сборки
    }

    static double value(WeakReference<AtomicInteger> ref) {
        AtomicInteger number = ref.get();                             // null, если объект уже убран
        if (number == null) {
            // так и датчик: объекта нет — значения нет
            return Double.NaN;
        }
        return number.get();
    }
}
```

`System.gc()` — просьба, а не приказ: на обычной JVM сборка случается
сразу, но обещания нет. Поэтому так проверяют для себя, а не в тестах.

**Порядок проверки** — из папки песочницы:

1. `./mvnw verify` — зелёный, вместе с тестами прошлых статей;
   `IncidentLogIT` из статьи 3б собирает журнал с настоящим
   `IncidentMetrics`;
2. `java WeakDemo.java` — `держим:    3.0` и `не держим: NaN`;
3. база на минуту (статья 3а), `java -jar` с `SPRING_DATASOURCE_*`;
   `curl -i http://127.0.0.1:8080/actuator/prometheus` — `401`; под
   `viewer` — `403`; под `admin` с `grep '^gameday'` — семь строк
   из части 3; `/actuator/health` без входа — по-прежнему `UP`;
4. вставка в `psql` — `gameday_incidents_open 2.0`, `low` — `1.0`;
   перезапуск — `low` снова `1.0`, открытых `3.0`;
5. `curl -u admin:admin-local http://127.0.0.1:8080/game-day/incidents`,
   затем ручка метрик — строка
   `http_server_requests_seconds_count{…,uri="/game-day/incidents"} 1`;
6. `docker stop game-day-db`, ручка метрик — не сразу,
   `gameday_incidents_open NaN`, в логе — `Failed to apply the value
   function`; приложение останови;
7. что будет, если: убери `prometheus` из `include` — под `admin`
   ручка ответит `404`; убери правило из `SecurityConfig` — `403`.
