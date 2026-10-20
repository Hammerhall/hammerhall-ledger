# События: JSON всерьёз — Jackson 3, `sealed`, `switch` по образцу, эталоны

> «От Spring к системе» · статья 7 · читать минут 30
>
> **Для кого.** Ты прочитал статьи 0–2 и 6: записи, перечисления с кодом
> и тесты по таблице (статья 0), песочница `game-day` на Boot (статьи 1–2)
> и стартер веба в ней (статья 6). Jackson ты пока видел издали:
> библиотека для JSON и бин `JsonMapper`, который делает Boot (статья 2).
>
> **Что будет.** Как Jackson читает чужой JSON — в запись и в дерево — и
> когда что брать. Как закрытый интерфейс и `switch` по образцу заставляют
> компилятор помнить все виды событий. Как незнакомое событие пропустить,
> битое — назвать без утечек, а договор формата положить в файл-эталон.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Spring к системе» — следующий шаг
> после «От Java к Spring Boot»: как приложение живёт среди других
> программ. Примеры — учебные: их можно повторить у себя.

---

## Зачем: события пишет чужая программа

Когда JSON пишет твоя программа, формат в твоих руках: переименовал
поле — поправил и того, кто его читает.

С событиями иначе. **Событие** — короткое сообщение «вот что случилось»:
атака началась, происшествие замечено. В рабочих системах события
приходят двумя дорогами. Список событий отдаёт по запросу соседний
сервис: его пишет чужая программа, твой сервис только читает. Или
события идут через **брокер** — программу-посредник, через которую части
системы передают друг другу сообщения. Бывает, одна половина сервиса
кладёт сообщения, другая забирает, а после выкатки половины оказываются
разных версий. В обоих случаях читающий не управляет тем, что ему пишут,
и формат живёт: новый вид события, новое поле, однажды — новая версия.
Сервис, который падает на каждой такой новости, встанет от любого
изменения.

Поэтому в рабочем проекте у задач про события общие правила: лишние поля
не мешают; незнакомый вид события — не ошибка; незнакомая версия
и битое — ошибка с точным текстом. А договор формата записан в файлах-эталонах —
о них часть 4.

Сквозной пример — журнал игрового дня. Тимлид атакует стенд, и его скрипт
сообщает журналу о каждом шаге атаки:

```json
{"version":1,"kind":"attack_started","at":"2026-10-14T10:00:00Z","target":"feed"}
```

После игры по этим событиям можно сравнить: атака на `feed` началась
в 10:00, дежурный заметил происшествие в 10:07 — семь минут. Журнал
игрового дня — учебный пример. Как событие доезжает до журнала, через
брокер или запросом к веб-серверу, здесь неважно: на входе разбора —
строка JSON.

Пример живёт в песочнице `game-day` — там, где её оставила статья 6.
Строим в пакете `example.gameday.events`: закрытый интерфейс
`GameEvent` и записи `AttackStarted`, `AttackStopped`, `UnknownGameEvent`;
перечисление `GameEventKind` с кодами `attack_started`, `attack_stopped`;
разбор `GameEventParser` с ошибкой `GameEventParseException`; эталоны
в `src/test/resources/game-day/events/`.

В коротких примерах нет строк `import` — полные файлы в конце статьи.

---

## Часть 1. Jackson глубже: запись и дерево

### JsonMapper — кто читает JSON

До сих пор JSON за тебя писали другие: ответ `/actuator/health`
в статье 6 собирал Actuator. Теперь разбор пишешь ты и зовёшь Jackson
сам. Главный объект Jackson для JSON — **`JsonMapper`** (помнишь бин
из статьи 2): читает текст в объекты Java и пишет обратно.

```java
JsonMapper mapper = JsonMapper.builder().build();   // настроить и собрать — один раз
```

`builder()` — **строитель**: сначала настройки, потом `build()` собирает
маппер. Готовый маппер в Jackson 3 изменить нельзя, поэтому его спокойно
зовут из многих потоков сразу (статья 1: поток — исполнитель, который идёт
по коду). Заводят его один раз полем, а не на каждый вызов.

⚠️ В интернете ты увидишь `com.fasterxml.jackson.databind.ObjectMapper`,
`mapper.configure(…)` и `registerModule(new JavaTimeModule())`. Это
Jackson 2. В Jackson 3 класс `ObjectMapper` тоже есть (статья 2), но
`configure` и `registerModule` у него нет: настройки — только через
строитель, а `java.time` встроен. Для JSON у нас `JsonMapper`
из `tools.jackson.databind.json` — как в Boot и в рабочем проекте.

У Boot свой бин `JsonMapper` с настройками `spring.jackson.*` на всё
приложение — в песочнице после статьи 6 он уже есть. Разбор событий
заводит собственный: формат события — договор с атакующим, и чужая
правка общей настройки не должна его менять. В рабочем проекте так же
поступают с сообщениями брокера.

### Способ 1: сразу в запись

```java
AttackStarted started = mapper.readValue(json, AttackStarted.class);
```

Это **привязка** (binding): Jackson сам раскладывает JSON по
**компонентам** записи — так называют то, что перечислено в её заголовке:
у `AttackStarted(Instant at, String target)` их два. Внутри так:

```
{"at":"2026-10-14T10:00:00Z", "target":"feed", "note":"…"}
  "at"     → компонент at: Instant    — строку ISO 8601 переводит в Instant
  "target" → компонент target: String
  "note"   → такого компонента нет    — пропустить
  → new AttackStarted(at, target)     — компактный конструктор проверяет
```

Jackson зовёт конструктор записи, поэтому проверки компактного
конструктора (статья 0) работают и при разборе: неверная запись не родится
и из JSON.

Что бывает, когда JSON не тот (проверено на Jackson 3.1):

| в JSON | что сделает Jackson |
|---|---|
| нет `target` | передаст `null`; проверка записи бросит `IllegalArgumentException`, Jackson завернёт его в `ValueInstantiationException` |
| `"at": "вчера"` | `InvalidFormatException`: это не время |
| `"at": "2026-10-14T13:00:00"` | то же: без зоны это не `Instant` — 13:00 по Москве или по UTC? |
| лишнее поле `note` | пропустит — но смотри ⚠️ ниже |
| не JSON вовсе | `StreamReadException` |

Все они наследуют `JacksonException` — непроверяемое исключение (статья 0).

💡 Привязка снисходительна: `"target": 5` она молча сделает строкой
`"5"`, а `"at": 1760436000` — секундами от 1970 года. Если договор строже,
тип проверяют сами, по дереву — как, покажет часть 3.

⚠️ В интернете ты увидишь, что Jackson падает на незнакомом поле
(`UnrecognizedPropertyException`). Это умолчание Jackson 2. В Jackson 3
умолчание обратное, и Boot 4.1 его не меняет. Но настройку
`FAIL_ON_UNKNOWN_PROPERTIES` включают одной строкой в строителе или ключом
`spring.jackson.deserialization.fail-on-unknown-properties`. Поэтому
в рабочем проекте на записях событий стоит
`@JsonIgnoreProperties(ignoreUnknown = true)` — «лишнее пропусти» прямо
на классе, с любым маппером. Она, как и `@JsonProperty`, которой задают
имя поля в JSON, осталась в `com.fasterxml.jackson.annotation`; в пакетах
`tools.jackson…` её не ищи.

### Способ 2: дерево

```java
JsonNode root = mapper.readTree(json);     // весь JSON — деревом узлов
JsonNode kind = root.get("kind");          // поле kind — или null, если его нет
```

**Дерево** (`JsonNode`) — JSON, разобранный на узлы без привязки к классу:
объект — узел с именованными вложенными узлами, строка — узел-строка.
Привязка — анкета с напечатанными графами: что не влезло, пропало. Дерево —
письмо целиком: читаешь сам, что и в каком порядке.

Самое нужное у `JsonNode`:

* `get("kind")` — вложенный узел по имени или `null`, если поля нет. Если поле
  есть, но в нём `null`, придёт узел, у которого `isNull()` истинно;
* `path("kind")` — то же, но вместо `null` — «отсутствующий узел»
  (`MissingNode`);
* `isObject()`, `isString()`, `isInt()` — что это за узел;
* `stringValue()`, `intValue()` — значение, если узел такого типа; у
  числа просить строку — исключение `JsonNodeException`;
* `asString()`, `asInt()` — «приведи как сможешь».

⚠️ В интернете ты увидишь `asText()`, `textValue()`, `isTextual()`,
`fields()`. Это Jackson 2. В Jackson 3 — `asString()`, `stringValue()`,
`isString()`, `properties()`; первые три старых имени пока работают, но
устарели, `fields()` удалён.

⚠️ «Приведи как сможешь» коварно: на отсутствующем поле `asInt()` вернёт
`0`, а `asString()` — пустую строку. `root.path("version").asInt()` на
событии без версии скажет «версия 0» вместо «версии нет». Сначала тип
(`isInt()`), потом значение.

### Когда что

| | запись (`readValue`) | дерево (`readTree`) |
|---|---|---|
| форма | одна, известна заранее | зависит от поля внутри: `kind`, `version` |
| проверки | типы — Jackson, правила — конструктор записи | всё сам |
| текст ошибки | Jackson | свой |
| лишние поля | Jackson 3 пропустит сам; надёжно — `@JsonIgnoreProperties` на записи | не мешают: читаешь, что нужно |

Событие игры — как раз смесь: пока не прочитал `kind`, не знаешь, в какую
запись разбирать. **Сначала дерево — понять, что пришло; потом запись —
разобрать по договору этого вида.** Дерево в запись переводит
`mapper.treeToValue(root, AttackStarted.class)` — по тем же правилам,
что `readValue`.

Так же в рабочем проекте читают события соседних сервисов.

---

## Часть 2. Закрытый набор видов: `sealed` и `switch` по образцу

### Беда: «одно из нескольких»

После разбора событие — одно из трёх: начало атаки, конец атаки,
незнакомое. Пусть `GameEvent` — обычный интерфейс, а код ветвится
проверками типа:

```java
if (event instanceof AttackStarted started) {      // «если это AttackStarted — назови его started»
    …
} else if (event instanceof AttackStopped stopped) {
    …
}                                                  // незнакомое забыли — компилятор молчит
```

`instanceof AttackStarted started` сразу даёт переменную нужного типа —
без приведения `(AttackStarted) event`.

Через месяц появится `AttackPaused` — цепочка скомпилируется, а новый вид
молча пройдёт мимо всех веток. Обычный интерфейс реализует кто угодно,
полного списка видов у компилятора нет.

### Закрытый интерфейс

```java
public sealed interface GameEvent permits AttackStarted, AttackStopped, UnknownGameEvent {
}
```

**Закрытый интерфейс** (`sealed`) — интерфейс с полным списком
реализаций в `permits`. Больше никто его реализовать не может. На
`record AttackPaused(…) implements GameEvent`, пока её нет в `permits`,
компилятор ответит:

```
error: class is not allowed to extend sealed class: GameEvent (as it is not listed in its 'permits' clause)
```

Правила — в JEP 409 (**JEP** — документ, которым в Java описывают и вводят
новую возможность языка). Модулей Java — файла `module-info.java`, которым
большие проекты делят код на части, — в песочнице нет. Поэтому правило
простое: все виды из `permits` лежат в том же пакете, что интерфейс. Каждый
вид объявляют `final` (наследников нет), `sealed` (свой список) или
`non-sealed` (дальше открыт всем); запись всегда `final`, ей ничего
дописывать не надо.

Виды — записи (статья 0):

```java
@JsonIgnoreProperties(ignoreUnknown = true)                        // лишнее в JSON — пропустить
public record AttackStarted(Instant at, String target) implements GameEvent {
    // компактный конструктор: at не null, target не пустая — иначе IllegalArgumentException
}

public record UnknownGameEvent(String kind) implements GameEvent {  // её собирает разбор, не Jackson
    // kind не пустой
}
```

`AttackStopped` — как `AttackStarted`. Методов в `GameEvent` нет: здесь
интерфейс — не обещание методов, а список видов. Бывает и закрытый
интерфейс с методами — тогда их реализует каждый вид.

### `switch` по образцу

После игры журнал печатает разбор полётов — строку на событие. Это делает
класс `GameEventText`:

```java
public static String describe(GameEvent event) {
    return switch (event) {
        case AttackStarted(Instant at, String target) -> at + " — атака на " + target + " началась";
        case AttackStopped(Instant at, String target) -> at + " — атака на " + target + " кончилась";
        case UnknownGameEvent(String kind) -> "незнакомое событие " + kind + " — пропущено";
    };
}
```

Три новые вещи:

* **`switch`-выражение** — `switch`, который возвращает значение:
  `return switch (…) {…};`. Стрелка `->` — «в этом случае результат
  такой», `break` не нужен;
* **`switch` по образцу** (pattern matching): `case AttackStarted started ->` —
  «если событие — `AttackStarted`, дай его под именем `started`»;
* **разбор записи по образцу** (record pattern, Java 21):
  `case AttackStarted(Instant at, String target) ->` — то же, но запись
  сразу разложена на компоненты. Типы можно заменить на `var`.

### Почему без `default`

`switch`-выражение обязано вернуть что-то на любой вход. По закрытому
типу компилятор знает все виды из `permits` и проверяет, что разобран
каждый. Три ветки — три вида, `default` не нужен.

Теперь создай запись `AttackPaused(Instant at, String target) implements
GameEvent` и впиши её в `permits`. `describe` перестанет компилироваться:

```
GameEventText.java:12: error: the switch expression does not cover all possible input values
        return switch (event) {
               ^
```

Так — с каждым `switch` по `GameEvent`: сборка покажет все места, где
новый вид забыли.

А замени последнюю ветку на `default -> "что-то другое"` — и всё
скомпилируется молча: `AttackPaused` уйдёт в `default` вместе
с незнакомыми. 🔑 **`default` в `switch` по закрытому типу выключает ту
самую проверку, ради которой тип закрыли.** Поэтому в рабочем проекте его
там не пишут.

⚠️ На полноту проверяется не всякий `switch`. Старый `switch`-оператор
по перечислению — без образцов, без возврата значения — компилятор
пропустит и с забытым значением, даже со стрелками: так оставили ради
старого кода (JEP 441). Нужна проверка — пиши выражение: `return switch …`.

### Перечисление и закрытый интерфейс — два списка

Есть ещё `GameEventKind` — перечисление с кодом, как `Area` в статье 0:

```java
ATTACK_STARTED("attack_started"), ATTACK_STOPPED("attack_stopped");
public static Optional<GameEventKind> fromCode(String code) { … }   // незнакомый код — Optional.empty()
```

В отличие от `Area.fromCode`, незнакомый код — не исключение, а пустой
**`Optional`** — коробка, где значение есть или нет: `Optional.of(kind)` —
со значением, `Optional.empty()` — пустая. По типу сразу видно, что
значения может не быть, — не то что `null`, о котором легко забыть.
Области задач задаёт команда, и чужая область — наша ошибка; атаки задаёт
атакующий, и новая — обычная жизнь. В рабочем проекте так же: незнакомое
из своего списка — исключение, незнакомое из чужого — пустая коробка.
Тело `fromCode` — цикл по `values()`, как в статье 0; способ
не единственный, это выбор журнала.

Зачем два списка. Перечисление — словарь **кодов**: какие строки в `kind`
журнал знает. Закрытый интерфейс — набор **форм**: что бывает на руках
у кода после разбора. Новую атаку начинай с перечисления: новый код
сломает `switch` разбора (часть 3), новая ветка потребует запись, запись
в `permits` сломает `describe`. Обратно цепочка не работает: запись без
кода в перечислении компилятор пропустит, и такие события тихо станут
незнакомыми.

---

## Часть 3. Разбор: незнакомое пропустить, битое назвать

### Что может прийти

| пришло | итог |
|---|---|
| знакомый вид, поля по договору | запись вида |
| незнакомый вид, версия 1 | `UnknownGameEvent(kind)` — не ошибка |
| версия не 1 | `GameEventParseException`: «версия 2 не поддерживается» |
| нет версии или вида, не объект, не JSON | `GameEventParseException`, причина словами |
| знакомый вид с битыми полями | `GameEventParseException`: «поле at не по договору» |

**Незнакомый вид — не ошибка.** Договор версии 1 обещает: виды будут
добавляться. Тимлид пустил в игру атаку `broker_paused` раньше, чем журнал
о ней узнал, — журнал её пропустит, остальное примет. В рабочем проекте
ставка выше: события там читают по порядку, и одно непонятое остановило бы
чтение всех следующих, а с ним и оповещения.

**Незнакомая версия — ошибка.** Версия 2 — другая форма: поля могут
называться и лежать иначе, даже `kind` может переехать. Читать её
правилами версии 1 — гадать.

**Версию проверяют первой.** Вот эталон версии 2 — вид уехал внутрь
`attack`:

```json
{"version": 2, "attack": {"kind": "attack_started", "at": "2026-10-14T12:00:00Z", "target": "feed"}}
```

Проверь сначала вид — получишь «нет вида (kind)», и тимлид станет искать
в скрипте ошибку, которой нет. Проверь сначала версию — «версия 2
не поддерживается, понимаю 1»: атакующий обновился раньше журнала,
лечится выкаткой журнала. Две беды — два текста. Бывает, для незнакомой
версии заводят даже свой тип исключения: кто забирает сообщения
из брокера, по типу решает, что с ними делать. Как устроен брокер —
отдельная тема; в рабочем проекте её ведёт мидл.

### Разбор целиком

```java
public GameEvent parse(String json) {
    JsonNode root = readRoot(json);                 // null, не JSON, не объект — ошибка
    checkVersion(root);                             // версия — первой
    String code = kindCode(root);                   // kind — непустая строка, иначе ошибка
    Optional<GameEventKind> known = GameEventKind.fromCode(code);
    if (known.isEmpty()) {                          // коробка пуста — вид незнакомый
        return new UnknownGameEvent(code);          // и это не ошибка
    }
    try {
        return switch (known.get()) {               // get() — достать; здесь коробка точно не пуста
                                                    // выражение без default — проверено на полноту
            case ATTACK_STARTED -> mapper.treeToValue(root, AttackStarted.class);
            case ATTACK_STOPPED -> mapper.treeToValue(root, AttackStopped.class);
        };
    } catch (JacksonException e) {
        throw new GameEventParseException("Событие " + known.get().code() + ": " + problem(e));  // без e!
    }
}
```

Версия — по дереву, с проверкой типа узла:

```java
JsonNode version = root.get("version");
if (version == null || !version.isInt()) {
    throw new GameEventParseException("Событие игры: нет версии (version) или она не целое число");
}
if (version.intValue() != SUPPORTED_VERSION) {     // SUPPORTED_VERSION = 1
    throw new GameEventParseException("Событие игры: версия " + version.intValue()
            + " не поддерживается, понимаю " + SUPPORTED_VERSION);
}
```

`"version": "1"` строкой не пройдёт: договор обещает число. `readRoot`
и `kindCode` устроены так же — они в «Примере целиком».

Теперь видно, зачем `@JsonIgnoreProperties` на записях: для `AttackStarted`
поля `version` и `kind` тоже лишние. Маппер разбора пока свой, строгость
в нём выключена. Но завтра его заменят общим бином Boot, где кто-то включит
`fail-on-unknown-properties` ради другого JSON, — и без аннотации упадёт
каждое событие, даже правильное: `Unrecognized property "version"`.
Аннотация держит правило при любом маппере.

### Своё исключение — и что в его тексте

`GameEventParseException extends RuntimeException` — непроверяемое, как
ошибки рабочего проекта (статья 0) и Jackson 3; конструктор один, с текстом.
Свой тип нужен тому, кто зовёт разбор: «событие не по договору» отличается
и от ошибки в нашем коде, и от внутренностей Jackson.

🔴 В тексте ошибки нет присланного: ни JSON целиком, ни значений полей.
Событие пишет чужая программа, и в нём может оказаться что угодно —
заметка атакующего с разгадкой атаки, а в рабочих событиях — чьё-то имя
и адрес. Текст исключения уходит в лог (помнишь, лог — не журнал), а лог
читают, хранят и пересылают.

⚠️ А Jackson присланное цитирует: ``Cannot deserialize value of type
`java.time.Instant` from String "вчера"``. Значит, ни `e.getMessage()` в своём
тексте, ни `e` вторым аргументом — **причиной** (`cause`, исключение,
из-за которого случилось наше). Причина не прячет текст: лог печатает
исключение вместе с причинами, строками `Caused by: …`, и «вчера» туда
доедет (проверено прогоном). Бывает, причину всё же кладут — когда
сообщение пишет свой же сервис и в нём одни номера.

Что не так, разбор говорит своими словами — `problem(e)` берёт из
исключения Jackson только безопасное:

```java
private static String problem(JacksonException e) {
    if (e instanceof ValueInstantiationException && e.getCause() instanceof IllegalArgumentException check) {
        return check.getMessage();                  // упала проверка записи: текст наш, без значений
    }
    List<JacksonException.Reference> path = e.getPath();   // путь к полю: имена, без значений
    if (path.isEmpty()) {
        return "поля не по договору";
    }
    return "поле " + path.get(path.size() - 1).getPropertyName() + " не по договору";
}
```

Выходит «Событие attack_started: поле at не по договору»: событие, вид
и поле — ровно столько, чтобы найти беду, — и ни одного присланного
значения. Текст `getMessage()` берём только у исключения из нашего
конструктора (`ValueInstantiationException`), а не у любого чужого.

---

## Часть 4. Эталоны: договор формата в файле

### Зачем

Формат события сейчас живёт в коде: имена компонентов, коды в перечислении,
проверка версии. Переименуй компонент `target` в `component` — в
пул-реквесте одна строка среди сотни, ревьюер не заметит, а события
атакующего перестанут разбираться.

**Эталон** — файл-образец, который записывает договор формата, плюс тест,
который прогоняет файл через разбор. Договор утверждает владелец формата,
и в эталоны идут не только годные сообщения, но и негодные, если договор
говорит, как на них отвечать: в рабочем проекте, где сервис задаёт формат
сам себе, эталонами записаны даже мусор и сообщение без версии. Файл,
который ты сочинил для удобства теста и никто не утверждал, — тестовые
данные. Эталоны чужого формата берут у его владельца, а не сочиняют.

🔑 **Поменял формат — покраснел тест на эталоне, и правка договора видна
в пул-реквесте файлом, а не строкой кода.** В рабочем проекте это говорят
одной фразой: «эталон — договор в файле». Покраснел тест — сначала спроси,
кто прав. Журнал только читает, поэтому почти всегда неправ код: верни имя
компонента. Эталон меняют, только когда поменялся источник, и новый файл
берут у него же. Под код эталон не подгоняют — так договор ломается молча.

У журнала формат задаёт атакующий. Эталоны тимлид прислал вместе
со скриптом: два годных события, событие незнакомого вида и черновик
второй версии. По договору незнакомый вид журнал пропускает, вторую
версию отвергает. Битых событий в договоре нет: их придумали мы, и это
тестовые данные в коде (`GameEventParserTest` в конце статьи).

```
src/test/resources/game-day/events/
    attack-started.json    начало атаки, с лишним полем note
    attack-stopped.json    конец атаки
    unknown-kind.json      вид broker_paused, журналу незнакомый
    version-2.json         черновик версии 2 от тимлида
```

`attack-started.json`:

```json
{
  "version": 1,
  "kind": "attack_started",
  "at": "2026-10-14T10:00:00Z",
  "target": "feed",
  "note": "кладу двойника на пять минут"
}
```

Поле `note` журнал не знает — эталон заодно сторожит правило «лишнее не
мешает».

### Как тест находит файл

Всё из `src/test/resources` Maven при сборке копирует в
`target/test-classes`. Пока идут тесты, эта папка лежит на **пути
классов** (classpath) — в списке папок и `.jar`, где Java ищет классы
и файлы. Поэтому файл берут по имени от корня этого пути — одинаково
у тебя, у соседа, в IDE и в Maven:

```java
private static String etalon(String name) throws IOException {
    try (InputStream in = GameEventEtalonTest.class.getResourceAsStream("/game-day/events/" + name)) {
        if (in == null) {                                         // файла нет — понятная ошибка
            throw new IllegalArgumentException("нет эталона " + name);
        }
        return new String(in.readAllBytes(), StandardCharsets.UTF_8);
    }
}
```

* `getResourceAsStream` отдаёт `InputStream` — байты файла, которые читают
  по порядку; `readAllBytes()` забирает их разом. По-русски его тоже зовут
  «поток» — это не поток-исполнитель из статьи 1, совпало только слово;
* `/` в начале — «от корня пути классов». Без неё путь считается от пакета
  класса: Java станет искать `example/gameday/events/game-day/events/…`,
  а файла там нет;
* нет файла — `getResourceAsStream` не бросает исключение, а возвращает
  `null`. Без проверки получишь `NullPointerException` строкой ниже,
  без имени файла;
* `try (…)` — «попробуй с ресурсом»: то, что открыто в скобках, закроется
  само в конце блока, даже если чтение упадёт;
* `IOException` проверяемое, отсюда `throws`. В тесте так можно; общий
  помощник для многих тестов обычно заворачивает его в непроверяемое;
* кодировка — явно UTF-8: в эталонах русские буквы.

### Тест на эталонах

```java
static Stream<Arguments> etalons() {                     // строки таблицы для теста ниже
    return Stream.of(
            Arguments.of("attack-started.json",
                    new AttackStarted(Instant.parse("2026-10-14T10:00:00Z"), "feed")),
            Arguments.of("attack-stopped.json",
                    new AttackStopped(Instant.parse("2026-10-14T10:05:00Z"), "feed")),
            Arguments.of("unknown-kind.json", new UnknownGameEvent("broker_paused")));
}

@ParameterizedTest(name = "{0}")
@MethodSource("etalons")                                 // данные — из метода etalons()
void parsesEtalon(String file, GameEvent expected) throws IOException {
    assertThat(parser.parse(etalon(file))).isEqualTo(expected);    // запись — целиком
}

@Test
void refusesNewerVersion() throws IOException {
    String json = etalon("version-2.json");                // прочитать до лямбды

    assertThatThrownBy(() -> parser.parse(json))
            .isInstanceOf(GameEventParseException.class)
            .hasMessage("Событие игры: версия 2 не поддерживается, понимаю 1");
}
```

**`@MethodSource("etalons")`** — данные для параметризованного теста берутся
из статического метода с этим именем. В `@CsvSource` (статья 0) — строки
и числа, а здесь в таблице записи, поэтому таблица — код. Метод отдаёт
**`Stream`** — последовательность значений; в Java его тоже зовут «поток» —
не путай с потоком-исполнителем из статьи 1 и с потоком байтов
`InputStream` выше. Здесь это просто «вот строки таблицы по одной»:
каждая — `Arguments.of(…)` со значениями в том же порядке, что параметры
метода-теста.

`parser` — поле теста, просто `new GameEventParser()`: разбору Spring
не нужен. `isEqualTo` на записи сравнивает все
компоненты (статья 0). Файл читаем до лямбды: пропал файл — тест упадёт
с «нет эталона», а не с невнятным «ждали другое исключение».

💡 Кто формат и пишет, сверяет эталон и обратно: то, что пишет код, против
файла — деревьями, `readTree(…).equals(…)`, ведь порядок полей и отступы
не часть договора.

### Где кончается эталон

Эталон проверяет, что **журнал** понимает договор. Что **источник** пишет
по договору — другая проверка, контрактный тест с источником; в рабочем
проекте его делает мидл. Как события ездят через брокер, подтверждения
и повторы — тоже работа мидла.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Чем чтение в запись отличается от чтения в дерево? Почему разбор события
   начинают с дерева, а заканчивают записью?
2. Что Jackson 3 делает с полем, которого нет в записи? Зачем тогда
   `@JsonIgnoreProperties(ignoreUnknown = true)` — и что сломается без неё
   в разборе события?
3. Что вернёт `root.path("version").asInt()` на событии без версии и чем
   это опасно?
4. Что даёт `sealed` в `GameEvent`? Что случится со сборкой, когда появится
   запись `AttackPaused` и её впишут в `permits`, — и что, если в `switch`
   стоял `default`?
5. Незнакомый вид — `UnknownGameEvent`, а незнакомая версия — исключение.
   Почему по-разному и почему версию проверяют раньше вида?
6. Почему в тексте `GameEventParseException` нет присланного JSON? Почему
   разбор не кладёт исключение Jackson даже причиной — и откуда тогда
   в тексте имя поля?
7. Как тест находит файл эталона? Что будет, если убрать `/` в начале пути?
8. Чем эталон отличается от тестовых данных? Тест на эталоне покраснел —
   что чинить, код или файл?

---

## Что дальше

Дальше в серии — объекты-значения: имя дежурного и стоп-слово. Как
проверить и привести значение в одном месте и как не дать секрету утечь
через `toString()`.

## Первоисточники

* [Jackson Release 3.0](https://github.com/FasterXML/jackson/wiki/Jackson-Release-3.0) —
  что поменялось в Jackson 3: пакеты, умолчания, исключения, имена методов
  `JsonNode`;
* [Spring Boot: JSON](https://docs.spring.io/spring-boot/reference/features/json.html) —
  Jackson 3 в Boot 4 и бин `JsonMapper`;
* [JEP 409: Sealed Classes](https://openjdk.org/jeps/409) — `sealed`,
  `permits` и где могут лежать виды;
* [JEP 441: Pattern Matching for switch](https://openjdk.org/jeps/441) —
  `switch` по образцу и проверка полноты;
* [JEP 440: Record Patterns](https://openjdk.org/jeps/440) — разбор записи
  по образцу, `var` в образце.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 6:
Jackson 3 приехал в неё со стартером веба, JUnit и AssertJ —
со `spring-boot-starter-test` от Initializr, так что `pom.xml`
не меняется. Добавь восемь классов в `src/main/java/example/gameday/events/`,
четыре эталона в `src/test/resources/game-day/events/` и два теста
в `src/test/java/example/gameday/events/`. Один класс — треугольником
в IDE или `./mvnw test -Dtest=Имя`, все — `./mvnw test`.

Путь к файлу — комментарием в первой строке.

```java
// src/main/java/example/gameday/events/GameEvent.java
package example.gameday.events;

public sealed interface GameEvent permits AttackStarted, AttackStopped, UnknownGameEvent {
}
```

```java
// src/main/java/example/gameday/events/AttackStarted.java
package example.gameday.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.time.Instant;

@JsonIgnoreProperties(ignoreUnknown = true)
public record AttackStarted(Instant at, String target) implements GameEvent {

    public AttackStarted {
        if (at == null) {
            throw new IllegalArgumentException("начало атаки: нет времени (at)");
        }
        if (target == null || target.isBlank()) {
            throw new IllegalArgumentException("начало атаки: нет цели (target)");
        }
    }
}
```

```java
// src/main/java/example/gameday/events/AttackStopped.java
package example.gameday.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.time.Instant;

@JsonIgnoreProperties(ignoreUnknown = true)
public record AttackStopped(Instant at, String target) implements GameEvent {

    public AttackStopped {
        if (at == null) {
            throw new IllegalArgumentException("конец атаки: нет времени (at)");
        }
        if (target == null || target.isBlank()) {
            throw new IllegalArgumentException("конец атаки: нет цели (target)");
        }
    }
}
```

```java
// src/main/java/example/gameday/events/UnknownGameEvent.java
package example.gameday.events;

public record UnknownGameEvent(String kind) implements GameEvent {

    public UnknownGameEvent {
        if (kind == null || kind.isBlank()) {
            throw new IllegalArgumentException("незнакомое событие: нет вида (kind)");
        }
    }
}
```

```java
// src/main/java/example/gameday/events/GameEventKind.java
package example.gameday.events;

import java.util.Optional;

public enum GameEventKind {
    ATTACK_STARTED("attack_started"),
    ATTACK_STOPPED("attack_stopped");

    private final String code;

    GameEventKind(String code) {
        this.code = code;
    }

    public String code() {
        return code;
    }

    public static Optional<GameEventKind> fromCode(String code) {
        for (GameEventKind kind : values()) {
            if (kind.code.equals(code)) {
                return Optional.of(kind);
            }
        }
        return Optional.empty();
    }
}
```

```java
// src/main/java/example/gameday/events/GameEventParseException.java
package example.gameday.events;

public class GameEventParseException extends RuntimeException {

    public GameEventParseException(String message) {
        super(message);
    }
}
```

```java
// src/main/java/example/gameday/events/GameEventParser.java
package example.gameday.events;

import java.util.List;
import java.util.Optional;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.exc.ValueInstantiationException;
import tools.jackson.databind.json.JsonMapper;

public class GameEventParser {

    static final int SUPPORTED_VERSION = 1;

    private final JsonMapper mapper = JsonMapper.builder().build();

    public GameEvent parse(String json) {
        JsonNode root = readRoot(json);
        checkVersion(root);
        String code = kindCode(root);
        Optional<GameEventKind> known = GameEventKind.fromCode(code);
        if (known.isEmpty()) {
            return new UnknownGameEvent(code);
        }
        try {
            return switch (known.get()) {
                case ATTACK_STARTED -> mapper.treeToValue(root, AttackStarted.class);
                case ATTACK_STOPPED -> mapper.treeToValue(root, AttackStopped.class);
            };
        } catch (JacksonException e) {
            throw new GameEventParseException("Событие " + known.get().code() + ": " + problem(e));
        }
    }

    private static String problem(JacksonException e) {
        if (e instanceof ValueInstantiationException && e.getCause() instanceof IllegalArgumentException check) {
            return check.getMessage();
        }
        List<JacksonException.Reference> path = e.getPath();
        if (path.isEmpty()) {
            return "поля не по договору";
        }
        return "поле " + path.get(path.size() - 1).getPropertyName() + " не по договору";
    }

    private JsonNode readRoot(String json) {
        if (json == null) {
            throw new GameEventParseException("Событие игры: тела нет");
        }
        JsonNode root;
        try {
            root = mapper.readTree(json);
        } catch (JacksonException e) {
            throw new GameEventParseException("Событие игры: не JSON");
        }
        if (!root.isObject()) {
            throw new GameEventParseException("Событие игры: ждали объект JSON");
        }
        return root;
    }

    private void checkVersion(JsonNode root) {
        JsonNode version = root.get("version");
        if (version == null || !version.isInt()) {
            throw new GameEventParseException("Событие игры: нет версии (version) или она не целое число");
        }
        if (version.intValue() != SUPPORTED_VERSION) {
            throw new GameEventParseException("Событие игры: версия " + version.intValue()
                    + " не поддерживается, понимаю " + SUPPORTED_VERSION);
        }
    }

    private String kindCode(JsonNode root) {
        JsonNode kind = root.get("kind");
        if (kind == null || !kind.isString() || kind.stringValue().isBlank()) {
            throw new GameEventParseException("Событие игры: нет вида (kind)");
        }
        return kind.stringValue();
    }
}
```

`readTree(null)` бросил бы не `JacksonException`, а `IllegalArgumentException`
— поэтому `null` проверяется до него. «Не JSON» — тоже без причины: текст
Jackson цитирует кусок присланного (`Unrecognized token 'не'`).

```java
// src/main/java/example/gameday/events/GameEventText.java
package example.gameday.events;

import java.time.Instant;

public final class GameEventText {

    private GameEventText() {   // только статические методы — экземпляры не нужны
    }

    public static String describe(GameEvent event) {
        return switch (event) {
            case AttackStarted(Instant at, String target) -> at + " — атака на " + target + " началась";
            case AttackStopped(Instant at, String target) -> at + " — атака на " + target + " кончилась";
            case UnknownGameEvent(String kind) -> "незнакомое событие " + kind + " — пропущено";
        };
    }
}
```

Эталоны — в `src/test/resources/game-day/events/`, в UTF-8. Комментариев
в JSON нет, поэтому путь к каждому — строкой над блоком.

`src/test/resources/game-day/events/attack-started.json`:

```json
{
  "version": 1,
  "kind": "attack_started",
  "at": "2026-10-14T10:00:00Z",
  "target": "feed",
  "note": "кладу двойника на пять минут"
}
```

`src/test/resources/game-day/events/attack-stopped.json`:

```json
{
  "version": 1,
  "kind": "attack_stopped",
  "at": "2026-10-14T10:05:00Z",
  "target": "feed"
}
```

`src/test/resources/game-day/events/unknown-kind.json`:

```json
{
  "version": 1,
  "kind": "broker_paused",
  "at": "2026-10-14T11:00:00Z",
  "target": "broker"
}
```

`src/test/resources/game-day/events/version-2.json`:

```json
{
  "version": 2,
  "attack": { "kind": "attack_started", "at": "2026-10-14T12:00:00Z", "target": "feed" }
}
```

```java
// src/test/java/example/gameday/events/GameEventEtalonTest.java
package example.gameday.events;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class GameEventEtalonTest {

    private final GameEventParser parser = new GameEventParser();

    static Stream<Arguments> etalons() {
        return Stream.of(
                Arguments.of("attack-started.json",
                        new AttackStarted(Instant.parse("2026-10-14T10:00:00Z"), "feed")),
                Arguments.of("attack-stopped.json",
                        new AttackStopped(Instant.parse("2026-10-14T10:05:00Z"), "feed")),
                Arguments.of("unknown-kind.json", new UnknownGameEvent("broker_paused")));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("etalons")
    void parsesEtalon(String file, GameEvent expected) throws IOException {
        assertThat(parser.parse(etalon(file))).isEqualTo(expected);
    }

    @Test
    void refusesNewerVersion() throws IOException {
        String json = etalon("version-2.json");

        assertThatThrownBy(() -> parser.parse(json))
                .isInstanceOf(GameEventParseException.class)
                .hasMessage("Событие игры: версия 2 не поддерживается, понимаю 1");
    }

    private static String etalon(String name) throws IOException {
        try (InputStream in = GameEventEtalonTest.class.getResourceAsStream("/game-day/events/" + name)) {
            if (in == null) {
                throw new IllegalArgumentException("нет эталона " + name);
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
```

Битые события — тестовые данные в коде: в договор с атакующим они
не входят. JSON — текстовыми блоками (статья 0); закрывающие `"""` на той же
строке, чтобы в строку не попал перевод строки.

```java
// src/test/java/example/gameday/events/GameEventParserTest.java
package example.gameday.events;

import java.time.Instant;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class GameEventParserTest {

    private final GameEventParser parser = new GameEventParser();

    static Stream<Arguments> broken() {
        return Stream.of(
                Arguments.of("не json", "Событие игры: не JSON"),
                Arguments.of("[]", "Событие игры: ждали объект JSON"),
                Arguments.of("""
                        {"kind":"attack_started"}""",
                        "Событие игры: нет версии (version) или она не целое число"),
                Arguments.of("""
                        {"version":"1","kind":"attack_started"}""",
                        "Событие игры: нет версии (version) или она не целое число"),
                Arguments.of("""
                        {"version":1}""",
                        "Событие игры: нет вида (kind)"),
                Arguments.of("""
                        {"version":1,"kind":"attack_started","at":"2026-10-14T10:00:00Z"}""",
                        "Событие attack_started: начало атаки: нет цели (target)"),
                Arguments.of("""
                        {"version":1,"kind":"attack_started","at":"2026-10-14T13:00:00","target":"feed"}""",
                        "Событие attack_started: поле at не по договору"));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("broken")
    void refusesBrokenEvent(String json, String message) {
        assertThatThrownBy(() -> parser.parse(json))
                .isInstanceOf(GameEventParseException.class)
                .hasMessage(message);
    }

    @Test
    void refusesMissingBody() {
        assertThatThrownBy(() -> parser.parse(null))
                .isInstanceOf(GameEventParseException.class)
                .hasMessage("Событие игры: тела нет");
    }

    @Test
    void errorDoesNotCarryInput() {
        String json = """
                {"version":1,"kind":"attack_started","at":"вчера","target":"feed","note":"кладу двойника"}""";

        assertThatThrownBy(() -> parser.parse(json))
                .hasMessage("Событие attack_started: поле at не по договору")
                .hasMessageNotContaining("вчера")
                .hasMessageNotContaining("двойника")
                .hasNoCause();                           // и в Caused by: лога ничего не доедет
    }

    @Test
    void unknownKindIsNotAnError() {
        GameEvent event = parser.parse("""
                {"version":1,"kind":"dns_poisoned"}""");

        assertThat(event).isEqualTo(new UnknownGameEvent("dns_poisoned"));
    }

    @Test
    void describesEveryKind() {
        Instant at = Instant.parse("2026-10-14T10:00:00Z");

        assertThat(GameEventText.describe(new AttackStarted(at, "feed")))
                .isEqualTo("2026-10-14T10:00:00Z — атака на feed началась");
        assertThat(GameEventText.describe(new AttackStopped(at, "feed")))
                .isEqualTo("2026-10-14T10:00:00Z — атака на feed кончилась");
        assertThat(GameEventText.describe(new UnknownGameEvent("dns_poisoned")))
                .isEqualTo("незнакомое событие dns_poisoned — пропущено");
    }
}
```
