# Тесты-сторожа: тесты, которые проверяют правила проекта

> «От Spring к системе» · статья 11 · читать минут 25
>
> **Для кого.** Ты прочитал статьи 0–10, и у тебя есть песочница
> `game-day` после статьи 10. Особенно пригодятся параметризованные
> тесты, регулярное выражение и JaCoCo (статья 0), тест периметра
> (статья 5), `@MethodSource` и `try (…)` (статья 7).
>
> **Что будет.** Как тест читает файлы проекта и почему поток файлов
> надо закрывать; как записать правило регулярным выражением и где оно
> врёт; как убедиться, что тест-сторож умеет краснеть.
>
> **Откуда статья.** Раздел «Буткемп / Лаборатория» — о том, как пишут
> код команды Hammerhall: буткемп работает в открытых репозиториях,
> лаборатория — в закрытых. Серия «От Spring к системе» — следующий шаг
> после «От Java к Spring Boot»: как приложение живёт среди других
> программ. Примеры — учебные: их можно повторить у себя.

---

## Зачем тест, который читает проект

В рабочем проекте есть правило: «сейчас» берут только из часов `Clock`,
а не из `Instant.now()` (статья 1). Держит его замечание на ревью — то
есть память ревьюера.

Память подводит: пятничный пул-реквест на сорок файлов, новый человек
на ревью — и `Instant.now()` проходит. Код работает, тесты зелёные, а
время в классе уже не подменить остановленными часами (статья 1).

Машина не устаёт: тест проверяет правило при каждой сборке, во всех
файлах, а ревьюер тратит внимание на то, что машине не по силам.

**Тест поведения и тест правила.** Все твои тесты до сих пор — тесты
поведения: вызвать код с известными данными, сравнить результат.
Тест правила проверяет не что код делает, а **как** проект устроен:
«нигде нет…», «в каждом файле…», «каждое имя…». Обычно он читает
проект как текст: исходники, миграции, настройки. А иногда
спрашивает собранное приложение — так устроен тест периметра из
статьи 5. Такой тест мы будем звать **сторожем**.

🔑 Тест поведения проверяет код, который уже есть. Сторож — и тот,
которого ещё нет: новый файл попадает под правило в ту минуту, когда
появляется.

В рабочем проекте сторожей задумано несколько: на правила пакетов, на
секреты без значений по умолчанию, на правила миграций, на правила
стенда — и тест периметра, который сверяет ручки с таблицей `DECLARED`;
его ты завёл в песочнице в статье 5. Пишут сторожей и джуны. Статья —
о том, как сторож устроен и как он может соврать.

Пример — снова журнал игрового дня в песочнице `game-day`. Ставим ему
двух сторожей:

* в пакете журнала `journal` нет `Instant.now()`;
* в миграциях журнала время — только `TIMESTAMPTZ` (правило из
  статьи 3а).

Схему в миграциях тоже сторожат, но в рабочем проекте это дело общего
сторожа миграций, а второй на то же правило не нужен. Код лежит
в песочнице, в `src/test/java/example/gameday/journal/`: правила
в `GameDayRules`, тесты в `GameDayRulesTest`.

---

## Часть 1. Как тест читает проект

### Рабочая папка: откуда считается путь

Папку журнала тест находит так:

```java
Path journal = Path.of("src/main/java/example/gameday/journal");
```

**`Path`** — путь к файлу или папке, только не строкой, а объектом: он
знает, из каких частей состоит, и сам разбирается с разделителями —
`/` на Linux и macOS, `\` на Windows. Строк `import` в коротких
примерах нет — они в «Примере целиком».

Путь без `/` в начале — **относительный**: «отсюда — в `src/main/…`».
«Отсюда» — это **рабочая папка**, в которой запущена программа.

Тесты запускает Surefire из статьи 3а, в песочнице он настроен
в `pom.xml`. Его рабочая
папка по умолчанию — папка проекта, где лежит `pom.xml`, поэтому
`./mvnw test` находит `src/main/…`. IntelliJ IDEA по умолчанию берёт
ту же папку. Если в IDE тест файлов не находит, а в `./mvnw test`
находит, смотри поле Working directory в настройках запуска.

### Обойти папку: Files.walk

`Files.walk(папка)` обходит папку целиком, со всеми вложенными, и отдаёт
пути потоком `Stream` из статьи 7. Новое — шаги над ним:
`filter` оставляет подходящие элементы, `map` превращает каждый в
другой, `sorted` сортирует, `toList()` собирает в список. Поток можно
получить и из готового списка — `список.stream()`.

```java
static List<Path> filesIn(Path root, String suffix) throws IOException {
    try (Stream<Path> paths = Files.walk(root)) {              // поток держит папки открытыми — закроет try
        return paths
                .filter(p -> p.toString().endsWith(suffix))    // только «.java» или «.sql»
                .sorted()                                      // один порядок от прогона к прогону
                .toList();
    }
}
```

`p -> …` — лямбда из статьи 0 с параметром: «для каждого пути `p`…».
`sorted` — чтобы отчёт не «прыгал» от прогона к прогону: в каком порядке
`walk` отдаёт файлы, не обещано.

⚠️ У `Path` есть свой `endsWith`, и он сравнивает не буквы, а части
пути целиком: `journal/Incident.java` оканчивается на `Incident.java`,
но не на `.java`. Напиши `p.endsWith(".java")` — код скомпилируется,
фильтр не пропустит ни одного файла, и сторож будет старательно
проверять пустоту. Сравнивают строкой: `p.toString().endsWith(…)`.

### Поток надо закрыть: try-with-resources

Поток `Files.walk` — не готовый список: пока он жив, он держит открытыми
папки, по которым идёт. Документация `Files.walk` прямо говорит: закрой
поток. Закрывают тем же `try (…)`, которым статья 7 читала эталон.
Полное имя приёма — **try-with-resources**. То, что в скобках, называют
**ресурсом**: это объект с методом `close`, класс которого
реализует `AutoCloseable`.

Кто ещё держит файл открытым: `Files.lines(файл)` — тоже поток, тоже
в `try`. А `Files.readString(файл)` читает файл целиком в строку и
закрывает его сам — `try` ему не нужен, поэтому в примере он. Читает
в UTF-8 — в этой кодировке исходники песочницы.

### Начинай с самой узкой папки

Обойди проект от корня, `Path.of(".")`, — и миграция журнала найдётся
дважды: в `src/main/resources/db/migration` и в
`target/classes/db/migration`: туда Maven при сборке копирует ресурсы.
Сторож доложит каждое нарушение дважды, а правило вроде «номера не
повторяются» покраснело бы на ровном месте. Поэтому сторож миграций
смотрит прямо в папку миграций. Вложенные папки не нужны вовсе — есть
`Files.list(папка)`: то же, что `walk`, но без вложенных папок и тоже
только в `try`.

И смотрит сторож только `src/main`: правило — про код продукта.
В тестах `Instant.now()` бывает законно — скажем, тест бина часов
сверяет с ним настоящие часы. А из `src/main` — только папка журнала,
`journal`: правило ставим журналу, и начинают с самой узкой папки, где
оно должно действовать. Понадобится шире — поменяешь одну строку.

---

## Часть 2. Правило — регулярным выражением

### Наивно: «строка содержит»

Первая мысль — `source.contains("Instant.now()")`. Проверим:

| код | на самом деле | `contains` |
|---|---|---|
| `Object t = Instant.now();` | нарушение | нашёл |
| `Object t = Instant . now ( );` | нарушение | пропустил |
| `Supplier<Instant> s = Instant::now;` | нарушение: ссылка на метод (статья 3б) | пропустил |
| `// не Instant.now(), а часы` | не нарушение | нашёл, а зря |

Сторож ошибается двумя способами, и они не равны. **Ложная тревога**
видна сразу: тест красный, человек смотрит, правило поправляют.
**Пропуск** не виден никак: тест зелёный, нарушение живёт. Пропуск
хуже, поэтому каждое уточнение, которое убирает ложные тревоги,
проверяют: не начало ли оно пропускать.

### Выражение точнее: Pattern и Matcher

В статье 0 выражение проверял `String.matches`. Сторожу нужны два класса
из `java.util.regex`. **`Pattern`** — выражение, разобранное один раз:
`Pattern.compile("…")`; разбор не бесплатный, поэтому его держат в поле
`static final`. `pattern.matcher(текст)` даёт **`Matcher`** — «искателя»
по тексту: `find()` ищет следующее совпадение и отвечает `true` или
`false`, `group()` отдаёт найденный кусок, `start()` — с какого знака он
начался. `matches` проверяет строку целиком, а `find` ищет кусок
внутри, в цикле — все по очереди.

```java
// Instant.now() и Instant::now; Instant.now(clock) — можно.
private static final Pattern INSTANT_NOW = Pattern.compile(
        "\\bInstant\\s*(?:\\.|::)\\s*now\\b(?!\\s*\\(\\s*\\w)");
```

Без удвоенных косых (о них ниже) выражение читается так:
`\bInstant\s*(?:\.|::)\s*now\b(?!\s*\(\s*\w)`. В статье 0 были `[…]`
и `*`; вот новое:

* `\b` — **граница слова**: с одной стороны буква, цифра или `_`,
  с другой — нет. `FrozenInstant.now()` не заденет,
  `java.time.Instant.now()` — заденет;
* `\s*` — пробелы, табуляции и переводы строки, сколько угодно, хоть
  ни одного;
* `(?:\.|::)` — одно из двух: `|` значит «или», а скобки `(?:…)` держат
  «или» внутри, чтобы оно не расползлось на всё выражение. `\.` — сама
  точка: без `\` точка значит «любой знак»;
* `now\b` — `now` целым словом;
* `(?!…)` — «дальше **не** идёт …». Внутри `\(` значит саму скобку (без `\`
  скобки группируют), а `\w` — один знак слова: буква, цифра или `_`.
  Вместе: не идёт скобка с аргументом. `Instant.now(clock)` берёт время
  из тех же часов — правило его разрешает.

⚠️ «Любой знак» у точки — не теория. Выражение `Instant.now` без `\`
находит `public void fix(Instant now)` в сущности журнала из статьи 3б:
точка согласна и на пробел.

⚠️ В строке Java каждую `\` пишут дважды: `"\\bInstant"`. Забудешь
у `\.` — компилятор откажется. Забудешь у `\b` или `\s` — промолчит.
`"\b"` в строке Java — символ backspace (так и написано в документации
`Pattern`): выражение не найдёт ничего, сторож навсегда зелёный.
`"\s"` с Java 15 — просто пробел: `Instant` и `.now()` на разных строках
выражение пропустит, и таблица без строки с переносом этого не заметит.

### Комментарии, строки и символы — не код

Комментарий `// не Instant.now(), а часы` и строку `"Instant.now()"`
правило видеть не должно. Поэтому их **забеливают**: заменяют
пробелами, а переводы строк оставляют — номера строк совпадут с файлом.
Всё не-код находит одно выражение из четырёх частей:

* `"(?:\\.|[^"\\\n])*"` — строка `"…"`. `[^…]` — любой знак, **кроме**
  перечисленных; `\n` — перевод строки. Внутри строки идут либо `\\.` —
  косая и любой знак после неё (так `\"` не считается концом), либо
  любой знак, кроме `"`, косой и перевода строки;
* `'(?:\\.|[^'\\\n])'` — символ `'…'`: один знак или косая со знаком.
  Без этой части `'"'` выражение приняло бы за начало строки и забелило
  бы всё до следующей `"` — вместе с нарушением;
* `//[^\n]*` — комментарий до конца строки;
* `/\*[\s\S]*?\*/` — комментарий `/* … */`, хоть на десять строк;
  `\*` — сама звёздочка.

Откуда в коде шесть косых подряд. В выражении `\\` — одна настоящая
косая. В строке Java каждую косую удваиваем ещё раз: `\\` → `\\\\`,
`\n` → `\\n`, а кавычка — `\"`. Отсюда `[^\"\\\\\\n]`: в нём кавычка `\"`,
косая `\\\\` и перевод строки `\\n`.

```java
// Не код Java: строки, символы и комментарии — их правило видеть не должно.
private static final Pattern JAVA_NOT_CODE = Pattern.compile(
        "\"(?:\\\\.|[^\"\\\\\\n])*\""      // строка "…"; \" внутри — не конец строки
        + "|'(?:\\\\.|[^'\\\\\\n])'"        // символ '…': '"' — не начало строки
        + "|//[^\\n]*"                      // комментарий до конца строки
        + "|/\\*[\\s\\S]*?\\*/");           // комментарий /* … */, хоть на много строк

static String blank(String text, Pattern notCode) {
    // всё найденное — в пробелы, кроме переводов строки
    return notCode.matcher(text)
            .replaceAll(m -> m.group().replaceAll("[^\\n]", " "));
}
```

`replaceAll` у `Matcher` ставит на место каждого найденного куска то,
что вернула лямбда; внутри — обычный `String.replaceAll(выражение,
замена)`: всё, кроме `\n`, — в пробел.

**Почему одно выражение, а не замены по очереди.** Выражение идёт
слева направо и в каждом месте берёт то, что начинается раньше. В
`String url = "http://x"; Object t = Instant.now();` раньше начинается
строка `"http://x"` — она и забелится, а нарушение останется на виду.
Убери сначала все `//` отдельной заменой — она съест хвост строки
вместе с `Instant.now()`. Пропуск.

`[\s\S]` — любой знак, включая перевод строки: пробельный или нет,
третьего не дано. `*?` — **нежадное** повторение: как можно меньше, до
первого `*/`. Обычное `*` — **жадное**: до последнего `*/` в файле — и
забелит весь код между первым и последним комментарием, с нарушениями.

Осталось найти нарушения и назвать строку:

```java
static List<String> instantNowCalls(String javaSource) {
    return find(INSTANT_NOW, blank(javaSource, JAVA_NOT_CODE),
            "«сейчас» в журнале берут из часов: clock.instant()");
}

private static List<String> find(Pattern rule, String code, String fix) {
    List<String> problems = new ArrayList<>();
    Matcher m = rule.matcher(code);
    while (m.find()) {                                                  // все совпадения по очереди
        // номер строки: сколько переводов строки до находки, плюс один
        int line = 1 + (int) code.substring(0, m.start()).chars().filter(c -> c == '\n').count();
        String found = m.group().replaceAll("\\s+", "");                // «Instant\n  .now» → «Instant.now»
        problems.add("строка " + line + ": " + found + " — " + fix);   // где, что нашли, как чинить
    }
    return problems;
}
```

Номер строки считают по забеленному тексту — переводы строк в нём
на своих местах. `substring(0, m.start())` берёт текст до находки,
`chars()` отдаёт его знаки потоком, `filter` оставляет переводы строки,
`count()` их считает; первая строка — та, перед которой переводов нет,
отсюда `1 +`.

Честно о границах. Символ `'"'` выражение учитывает — без второй части
он спрятал бы нарушение: пропуск. А текстовый блок `"""…"""` оно видит
как код: `Instant.now()` в нём — ложная тревога. `import static
java.time.Instant.*` с голым `now()` пропустит.

`LocalDateTime.now()`,
`System.currentTimeMillis()` и родню правило не ищет вовсе, хотя
«сейчас — только из часов» запрещает и их. Расширь выражение сам.
`Instant.now(Clock.systemUTC())` пройдёт: сторож ловит ошибки, а
нарочный обход разбирают на ревью.

### Второе правило — SQL

Время без пояса в миграции журнала ищем выражением `\bTIMESTAMP\b`.
Вторым аргументом `Pattern.compile` передаём флаг `Pattern.CASE_INSENSITIVE`.
Флаг — настройка выражения, а этот значит, что регистр не важен:
`timestamp` тоже поймается. Здесь граница слова показывает себя на настоящих именах:

* `TIMESTAMPTZ` — после `TIMESTAMP` идёт буква, границы нет: не нарушение;
* `CURRENT_TIMESTAMP` — `_` считается частью слова: не нарушение;
* `TIMESTAMP(3)` — нарушение, и правильно;
* `TIMESTAMP WITH TIME ZONE` — тоже нарушение, хотя это длинная запись
  того же `TIMESTAMPTZ`. Ложная тревога по договорённости: в рабочем
  проекте пишут короткую форму, и сообщение так и скажет.

Комментарии SQL, `--` до конца строки и `/* … */`, забеливаем тем же
`blank`.

### Когда регулярного выражения мало

Выражение видит буквы, а не смысл: не знает ни типов, ни импортов.
Каждый новый случай — новая ветка, и однажды ты пишешь разбор Java.
Дальше три дороги:

* формат со структурой — разборщиком: в рабочем проекте настройки
  в YAML сторожа читают библиотекой SnakeYAML;
* спросить само приложение: тест периметра из статьи 5 спрашивает
  у Spring, какие ручки есть;
* готовый инструмент. ArchUnit — библиотека для тестов, которая
  проверяет устройство кода по скомпилированным классам и увидит
  `Instant.now()`, как его ни запиши. **Линтер** — программа, которая
  проверяет исходники по правилам оформления, например Checkstyle.

В рабочем проекте их нет: новую зависимость добавляет мидл, а задача
на сторожа пакетов нарочно просит написать проверку самому.

---

## Часть 3. Тест по файлам

### @MethodSource: каждый файл — отдельный запуск

Список файлов считают при запуске, поэтому данные дают через
`@MethodSource` — ты видел его в статье 7. Здесь метод-источник отдаёт
`List`, а `arguments(…)` — то же, что `Arguments.of(…)`, через
статический импорт.

```java
// JOURNAL = Path.of("src/main/java/example/gameday/journal")
static List<Arguments> journalSources() throws IOException {
    return GameDayRules.filesIn(JOURNAL, ".java").stream()
            .map(file -> arguments(named(JOURNAL.relativize(file).toString(), file)))
            .toList();
}

@ParameterizedTest(name = "{0}")                    // подпись запуска — имя файла
@MethodSource("journalSources")                     // откуда брать данные
void timeComesFromClock(Path file) throws IOException {
    List<String> problems = GameDayRules.instantNowCalls(Files.readString(file));
    if (!problems.isEmpty()) {
        fail(String.join("\n", problems));          // все нарушения файла разом
    }
}
```

Как читать:

* `named(имя, значение)` — **Named**, значение с именем для отчёта.
  В тест приходит `Path`, а в отчёте — `IncidentLog.java`: `relativize`
  отрезает начало пути до папки журнала;
* `name = "{0}"` — подпись запуска: первый аргумент, у `Named` — его имя;
* `fail(текст)` — из AssertJ: упасть с этим текстом.

В отчёте каждый файл — своя строка (схематично):

```
timeComesFromClock(Path)
├─ AttackOutcome.java ✔
├─ …
├─ IncidentLog.java ✘   строка 39: Instant.now — «сейчас» в журнале берут из часов: clock.instant()
├─ …
└─ SeverityConverter.java ✔
```

Так выглядит дерево запусков. Maven в консоли перечисляет только
упавшие запуски, и текст нарушения там тот же. Номер строки зависит
от твоей версии `IncidentLog`. Здесь это песочница после статьи 10, где первая
строка каждого файла — путь комментарием, как в «Примере целиком».

Сразу видно, какие файлы плохи, и починка в одном не прячет другой.
Миграции устроены так же: источник `journalMigrations` берёт `.sql`
с `__game_day_` в имени. А правила про весь проект сразу, вроде «номера
не повторяются» или «нет цикла пакетов», по файлам не разложишь: там один
тест и общий список нарушений. Так устроены сторожа пакетов и миграций
в рабочем проекте.

### Ноль файлов — красный

Ошибся в фильтре или папка пуста — запусков ноль. (Папки, которой нет,
`Files.walk` не простит — `NoSuchFileException`.) Параметризованный тест
без запусков в JUnit 6 падает, если не поставить ему
`allowZeroInvocations = true`. Сторожу его не ставь: ноль файлов —
значит, не проверено ничего. В тесте-одиночке со списком нарушений
«файлов больше нуля» проверяешь сам — так делают сторожа пакетов
и миграций в рабочем проекте.

### Сообщение, которое говорит, что исправить

Сравни: `assertThat(problems.isEmpty()).isTrue()` скажет только: ждали
`true`, пришло `false`. Наш красный тест (в схеме выше) говорит всё: где
нарушение (файл виден в подписи, строка — в тексте), что найдено и как чинить.
В рабочем проекте сообщение называет ещё и откуда правило — ключ
задачи. `assertThat(problems).isEmpty()` тоже годится — AssertJ
напечатает сам список; `fail` с `String.join("\n", …)` даёт каждому
нарушению свою строку.

Красный сторож часто видит не автор, а джун через полгода — без «как
чинить» он пойдёт искать автора.

🔴 И печатает сторож только безопасное: правило про секреты называет
ключ, но никогда не значение, иначе тест разнесёт пароль по логам
сборки. Так устроены сторожа секретов и правил стенда в рабочем
проекте.

---

## Часть 4. Сторож, который не может покраснеть

### Как сторож врёт

Помнишь из статьи 0: покрытие — не доказательство. Со сторожами строже:
JaCoCo меряет только `src/main`, а сторож живёт в `src/test` — в отчёте
его нет вовсе. Доказательство одно: увидеть сторожа красным. Тест,
который не краснел, ничего не доказал.

Кто какую
ложь ловит — в таблице; последняя строка — **отрицательный контроль**:
нарочно нарушить правило в настоящем коде и убедиться, что сторож
покраснел.

| как врёт | что поймает |
|---|---|
| выражение не находит ничего (`"\b"` вместо `"\\b"`) | таблица «ловит / не ловит» |
| выражение не видит переносов (`"\s"` вместо `"\\s"`) | таблица: строка с переносом |
| `'"'` в коде прячет нарушение | таблица: строка с символом `'"'` |
| жадный `*` забелил код между комментариями | таблица: строка «комментарий, нарушение, комментарий» |
| `Path.endsWith(".java")` — ни одного файла | временная папка с подложенным нарушителем; ноль запусков в JUnit |
| смотрит не в ту папку или не те миграции | отрицательный контроль руками |

### Таблица на функцию правила

Правило — функция «текст → список нарушений», без файлов и JUnit. Её
проверяют таблицей, как `TaskKey.parse` в статье 0: что правило обязано
поймать и чего не должно.

```java
@ParameterizedTest(name = "ловит: {0}")
@ValueSource(strings = {
        "Supplier<Instant> s = Instant::now;",
        "Object t = Instant\n        .now();",
        "String url = \"http://x\"; Object t = Instant.now();",
        "char q = '\"'; Object t = Instant.now(); String s = \"x\";",
        "/* раз */ Object t = Instant.now(); /* два */"})
void catchesInstantNow(String code) {
    assertThat(GameDayRules.instantNowCalls(code)).hasSize(1);
}
```

Каждая строка — чья-то возможная ошибка:

* перенос ловит `"\s"` без второй косой;
* `"http://x"` — раннее выбрасывание `//`;
* `'"'` — символ без своей части выражения;
* два комментария вокруг вызова — жадное `*`;
* `fix(Instant now)` в таблице «не ловит» — точку без `\`.

Сломаешь выражение — покраснеет строка. Полная таблица — в «Примере целиком».

### Подложить нарушителя: @TempDir

Таблица проверяет выражение, но не обход: `Path.endsWith` она
пропустит. Нужен весь путь на настоящих файлах, а в файлы проекта писать
нельзя. Для этого **`@TempDir`**: JUnit перед тестом создаёт пустую
временную папку, передаёт её параметром `Path`, а после теста удаляет.

```java
@Test
void findsPlantedViolator(@TempDir Path dir) throws IOException {
    // resolve — приставить к пути: dir/inner; createDirectories — создать папку
    Files.createDirectories(dir.resolve("inner"));
    // writeString — записать строку в файл (UTF-8); нарушитель — во вложенной папке, строка 2
    Files.writeString(dir.resolve("inner/Bad.java"),
            "class Bad {\n    Object t = Instant.now();\n}\n");
    Files.writeString(dir.resolve("notes.txt"), "Instant.now()");   // не .java — читать не должны

    List<Path> files = GameDayRules.filesIn(dir, ".java");

    assertThat(files).containsExactly(dir.resolve("inner/Bad.java"));
    List<String> problems = GameDayRules.instantNowCalls(Files.readString(files.get(0)));
    assertThat(problems).hasSize(1);
    assertThat(problems.get(0)).startsWith("строка 2:");
}
```

Поэтому `filesIn` получает папку параметром: как часы в статье 1, она
приходит снаружи, и тест подставляет свою.

### Отрицательный контроль — руками

Таблица и временная папка проверяют функции. Что тест смотрит
в настоящую папку и берёт нужные миграции, видно только на настоящем
прогоне — руками:

1. в `IncidentLog`, в методе `add`, который создаёт `Incident`, замени
   `clock.instant()` на `Instant.now()`;
2. `./mvnw test -Dtest=GameDayRulesTest` — `-Dtest=` говорит Surefire
   запустить только этот класс тестов, а не все. `IncidentLog.java`
   красный, с номером строки — `строка 39`;
3. верни `clock.instant()` руками или отменой правки в IDE — снова
   зелёный. `git checkout -- <файл>` здесь не годится: он вернёт файл
   к последнему коммиту и заберёт всё незакоммиченное, а песочницу
   ты мог и не коммитить;
4. то же с миграцией: в `V1__game_day_incident.sql` поменяй у
   `detected_at` `TIMESTAMPTZ` на `TIMESTAMP` — красный
   `V1__game_day_incident.sql`, `строка 6`. Верни сразу: применённую
   миграцию не правят (статья 3а), а `./mvnw test -Dtest=…` до базы
   не дойдёт.

В рабочем проекте каждая задача на сторожа требует в пул-реквесте
вывод красного прогона: это доказательство, что сторож умеет кусаться.

💡 Третье правило напиши сам: имена метрик журнала начинаются с
`gameday.` (статья 10). Где выражение их не увидит — имя в константе,
склеенное из кусков? Может, честнее спросить приложение, какие метрики
оно завело, как тест периметра спрашивает о ручках?

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Чем тест правила отличается от теста поведения? Почему сторож
   проверяет и код, которого ещё нет?
2. От какой папки считается `Path.of("src/main/…")` в `./mvnw test`?
   Что проверить, если в IDE файлов нет?
3. Почему `Files.walk` пишут в `try (…)`, а `Files.readString` — нет?
4. Сторож доложил каждое нарушение в миграциях дважды. Что, скорее
   всего, не так с обходом?
5. Разбери `\bInstant\s*(?:\.|::)\s*now\b(?!\s*\(\s*\w)` по кускам.
   Почему `fix(Instant now)` и `Instant.now(clock)` не нарушения,
   а `Instant::now` — нарушение?
6. Почему строки, символы и комментарии забеливают одним выражением,
   а не заменами по очереди? Чем опасно жадное `*`?
7. Ложная тревога или пропуск — что хуже для сторожа и почему?
8. Сторож ни разу не краснел. Какими тремя способами проверить, что он
   умеет? Какой из них не заменят два других?

---

## Что дальше

Это последняя статья серии «От Spring к системе». Сторожа теперь можно
писать, понимая, как они устроены, а на вопрос ревью «как твой сторож
может соврать?» ответ у тебя есть. И на игровом дне открой журнал
дежурного (статья 10): какие из записанных происшествий не случились бы,
стой у правила сторож?

Следующая серия, «От системы к делу», учит читать живую систему: какое
правило дела записано в коде и что сломалось бы, будь оно записано иначе.

## Первоисточники

* [Java SE 25: Files](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/nio/file/Files.html) —
  `walk`, `lines`, `readString`: что держит файлы открытыми;
* [The Java Tutorials: The try-with-resources Statement](https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html) —
  что такое ресурс и когда его закрывают;
* [Java SE 25: Pattern](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/regex/Pattern.html) —
  `\b`, `\s`, нежадные повторы, удвоенные `\` в строках Java;
* [JUnit 6: Parameterized Classes and Tests](https://docs.junit.org/6.0.3/writing-tests/parameterized-classes-and-tests.html) —
  `@MethodSource`, `Named`, подписи запусков;
* [JUnit 6: Built-in Extensions](https://docs.junit.org/6.0.3/writing-tests/built-in-extensions.html) —
  `@TempDir`: когда папку создают и удаляют.

---

## Пример целиком — с импортами

Учебный пример. Запускай в песочнице `game-day` после статьи 10: Postgres
в контейнере, миграции `V1` и `V2`, журнал в `example.gameday.journal`
с хранилищем, ручками статей 4–5, объектами-значениями статьи 8,
серьёзностью статьи 9 и метриками статьи 10, тест периметра, охрана,
Actuator и стенд статьи 6 — всё остаётся. В `pom.xml` ничего добавлять
не нужно: сторожам Spring не нужен, JUnit и AssertJ — со
`spring-boot-starter-test`.

Что добавить: в `src/test/java/example/gameday/journal/` — `GameDayRules`
(правила — функции без JUnit) и `GameDayRulesTest` (сторожа и проверка
самих сторожей). Что поменять: ничего — сторож читает файлы песочницы
как есть.

Запуск: один класс — треугольником в IDE или
`./mvnw test -Dtest=GameDayRulesTest`; весь `./mvnw verify` гоняет
и `*IT` — нужен запущенный Docker. Путь к файлу — комментарием в первой
строке.

```java
// src/test/java/example/gameday/journal/GameDayRules.java
package example.gameday.journal;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * Правила журнала игрового дня — функции без JUnit: текст на входе,
 * список нарушений на выходе. Учебный пример.
 */
final class GameDayRules {

    // Не код Java: строки, символы и комментарии — их правило видеть не должно.
    private static final Pattern JAVA_NOT_CODE = Pattern.compile(
            "\"(?:\\\\.|[^\"\\\\\\n])*\""      // строка "…"; \" внутри — не конец строки
            + "|'(?:\\\\.|[^'\\\\\\n])'"        // символ '…': '"' — не начало строки
            + "|//[^\\n]*"                      // комментарий до конца строки
            + "|/\\*[\\s\\S]*?\\*/");           // комментарий /* … */, хоть на много строк

    // Instant.now() и Instant::now; Instant.now(clock) — можно.
    private static final Pattern INSTANT_NOW = Pattern.compile(
            "\\bInstant\\s*(?:\\.|::)\\s*now\\b(?!\\s*\\(\\s*\\w)");

    // Не код SQL: комментарии -- до конца строки и /* … */.
    private static final Pattern SQL_COMMENT = Pattern.compile("--[^\\n]*|/\\*[\\s\\S]*?\\*/");

    // TIMESTAMP — но не TIMESTAMPTZ и не CURRENT_TIMESTAMP; регистр не важен.
    private static final Pattern TIMESTAMP_WITHOUT_ZONE =
            Pattern.compile("\\bTIMESTAMP\\b", Pattern.CASE_INSENSITIVE);

    private GameDayRules() {
    }

    /** Все файлы под root, чьё имя оканчивается на suffix, по алфавиту. */
    static List<Path> filesIn(Path root, String suffix) throws IOException {
        try (Stream<Path> paths = Files.walk(root)) {
            return paths
                    .filter(p -> p.toString().endsWith(suffix))
                    .sorted()
                    .toList();
        }
    }

    static List<String> instantNowCalls(String javaSource) {
        return find(INSTANT_NOW, blank(javaSource, JAVA_NOT_CODE),
                "«сейчас» в журнале берут из часов: clock.instant()");
    }

    static List<String> timestampsWithoutZone(String sql) {
        return find(TIMESTAMP_WITHOUT_ZONE, blank(sql, SQL_COMMENT),
                "пиши TIMESTAMPTZ (короткая форма); в Java это Instant");
    }

    /** Заменить всё, что нашёл notCode, пробелами; переводы строк оставить. */
    static String blank(String text, Pattern notCode) {
        return notCode.matcher(text).replaceAll(m -> m.group().replaceAll("[^\\n]", " "));
    }

    private static List<String> find(Pattern rule, String code, String fix) {
        List<String> problems = new ArrayList<>();
        Matcher m = rule.matcher(code);
        while (m.find()) {
            int line = 1 + (int) code.substring(0, m.start()).chars().filter(c -> c == '\n').count();
            String found = m.group().replaceAll("\\s+", "");
            problems.add("строка " + line + ": " + found + " — " + fix);
        }
        return problems;
    }
}
```

```java
// src/test/java/example/gameday/journal/GameDayRulesTest.java
package example.gameday.journal;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.fail;
import static org.junit.jupiter.api.Named.named;
import static org.junit.jupiter.params.provider.Arguments.arguments;

class GameDayRulesTest {

    private static final Path JOURNAL = Path.of("src/main/java/example/gameday/journal");
    private static final Path MIGRATIONS = Path.of("src/main/resources/db/migration");

    // --- сторожа: настоящие файлы журнала ---

    static List<Arguments> journalSources() throws IOException {
        return GameDayRules.filesIn(JOURNAL, ".java").stream()
                .map(file -> arguments(named(JOURNAL.relativize(file).toString(), file)))
                .toList();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("journalSources")
    void timeComesFromClock(Path file) throws IOException {
        List<String> problems = GameDayRules.instantNowCalls(Files.readString(file));
        if (!problems.isEmpty()) {
            fail(String.join("\n", problems));
        }
    }

    static List<Arguments> journalMigrations() throws IOException {
        return GameDayRules.filesIn(MIGRATIONS, ".sql").stream()
                // getFileName — имя без папок
                .filter(file -> file.getFileName().toString().contains("__game_day_"))
                .map(file -> arguments(named(file.getFileName().toString(), file)))
                .toList();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("journalMigrations")
    void journalTimeHasZone(Path file) throws IOException {
        List<String> problems = GameDayRules.timestampsWithoutZone(Files.readString(file));
        if (!problems.isEmpty()) {
            fail(String.join("\n", problems));
        }
    }

    // --- проверка самих сторожей ---

    @ParameterizedTest(name = "ловит: {0}")
    @ValueSource(strings = {
            "Object t = Instant.now();",
            "Object t = java.time.Instant.now();",
            "Object t = Instant . now ( );",
            "Object t = Instant\n        .now();",
            "Supplier<Instant> s = Instant::now;",
            "String url = \"http://x\"; Object t = Instant.now();",
            "char q = '\"'; Object t = Instant.now(); String s = \"x\";",
            "/* раз */ Object t = Instant.now(); /* два */"})
    void catchesInstantNow(String code) {
        assertThat(GameDayRules.instantNowCalls(code)).hasSize(1);
    }

    @ParameterizedTest(name = "не ловит: {0}")
    @ValueSource(strings = {
            "Instant now = clock.instant();",
            "Object t = Instant.now(clock);",
            "public void fix(Instant now) {",
            "// не Instant.now(), а часы",
            "/* не Instant.now(),\n   а часы */",
            "String hint = \"Instant.now()\";",
            "Object t = FrozenInstant.now();"})
    void ignoresWhatIsNotACall(String code) {
        assertThat(GameDayRules.instantNowCalls(code)).isEmpty();
    }

    @ParameterizedTest(name = "ловит: {0}")
    @ValueSource(strings = {
            "detected_at TIMESTAMP NOT NULL",
            "detected_at timestamp NOT NULL",
            "fixed_at TIMESTAMP(3)"})
    void catchesTimestampWithoutZone(String sql) {
        assertThat(GameDayRules.timestampsWithoutZone(sql)).hasSize(1);
    }

    @ParameterizedTest(name = "не ловит: {0}")
    @ValueSource(strings = {
            "detected_at TIMESTAMPTZ NOT NULL",
            "seen_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP",
            "-- было TIMESTAMP, стало TIMESTAMPTZ",
            "/* было TIMESTAMP */ seen_at TIMESTAMPTZ"})
    void ignoresTimestampWithZone(String sql) {
        assertThat(GameDayRules.timestampsWithoutZone(sql)).isEmpty();
    }

    @Test
    void findsPlantedViolator(@TempDir Path dir) throws IOException {
        Files.createDirectories(dir.resolve("inner"));
        Files.writeString(dir.resolve("inner/Bad.java"),
                "class Bad {\n    Object t = Instant.now();\n}\n");
        Files.writeString(dir.resolve("notes.txt"), "Instant.now()");

        List<Path> files = GameDayRules.filesIn(dir, ".java");

        assertThat(files).containsExactly(dir.resolve("inner/Bad.java"));
        List<String> problems = GameDayRules.instantNowCalls(Files.readString(files.get(0)));
        assertThat(problems).hasSize(1);
        assertThat(problems.get(0)).startsWith("строка 2:");
    }
}
```

**Порядок проверки** — из папки песочницы:

1. `./mvnw verify` — зелёный, вместе с тестами прошлых статей;
   в `GameDayRulesTest` 43 запуска: 18 файлов журнала, 2 миграции,
   22 строки таблиц и временная папка;
2. отрицательный контроль из части 4: `Instant.now()` в `add` —
   `IncidentLog.java` красный, `строка 39`; `TIMESTAMP` в `V1` —
   `V1__game_day_incident.sql` красный, `строка 6`; верни оба;
3. что будет, если: `"\b"` вместо `"\\b"` в `INSTANT_NOW` — красные
   все восемь «ловит» и `findsPlantedViolator`, а сторож на файлах
   журнала зелёный; `p.endsWith(".java")` в `filesIn` — ноль запусков
   у обоих сторожей и красная временная папка; опечатка в `JOURNAL` —
   `NoSuchFileException`.
