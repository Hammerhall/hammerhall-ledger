# Свой коллектор и когда цикл лучше

> «Стримы по шагам» · статья 10 · читать минут 20
>
> **Для кого.** Ты прочитал статьи 1–9 серии или знаешь то же сам:
> конвейер и ленивость, `Optional`, `flatMap`, `collect` и готовые
> коллекторы, `IntStream`, индекс по карте. Это последняя статья серии.
>
> **Что будет.** Из каких четырёх частей состоит любой коллектор и как
> собрать свой через `Collector.of`; `peek` — подсмотреть, что едет
> по конвейеру, и почему только подсмотреть; и честно — когда цикл
> лучше стрима: состояние и ранний выход, проверяемые исключения,
> работа по индексам.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем свой коллектор — и зачем цикл

Вера заходила в «Наковальню» дважды и просит общий чек за день:
по строке на каждую позицию и итог внизу.

Готовые коллекторы почти справляются. `mapping` соберёт строки,
`summingInt` — итог, `teeing` из
[статьи 6](https://hammerhall.io/ledger/streams/6-downstream-collectors) сведёт их вместе.
Но это три коллектора, вложенных друг в друга, и каждый раз, когда
нужен чек, конструкцию придётся собирать заново. Хочется одного слова:
`collect(toReceipt())`.

Это первая половина статьи: как устроен коллектор и как сделать свой.
Вторая — о другом крае. Девять статей серия учила писать стримом,
и честно будет закончить тем, где стрим перестаёт помогать и цикл
читается лучше.

---

## Часть 1. Из чего сделан коллектор

### Четыре функции

Помнишь сравнение из [статьи 5](https://hammerhall.io/ledger/streams/5-grouping): коллектор —
рецепт ответа: какую посуду взять, что делать с каждым элементом, что
подать в конце. В Java этот рецепт — четыре функции:

| часть | что делает | для чека |
|---|---|---|
| **supplier** (поставщик) | создаёт пустой контейнер — посуду, куда копить | пустой черновик чека |
| **accumulator** (накопитель) | кладёт в контейнер очередной элемент | пробить позицию: строка и сумма |
| **combiner** (объединитель) | сливает два контейнера в один | приклеить один черновик к другому |
| **finisher** (завершитель) | превращает контейнер в ответ | напечатать готовый чек |

В обычном стриме supplier вызывается один раз в начале, accumulator —
для каждого элемента, finisher — один раз в конце. Combiner не
вызывается вовсе: он для параллельного стрима, о нём ниже.

### Контейнер — черновик чека

Сначала — что получится. Чек — запись: строки и итог.

```java
record Receipt(List<String> lines, int total) {
    String text() {                                          // чек текстом: строки, внизу итог
        return String.join("\n", lines) + "\nитого: " + total + " ₽";
    }
}
```

`String.join` склеивает строки через разделитель — здесь перевод
строки `\n`.

Пока позиции едут по конвейеру, чек не готов — нужен черновик, который
можно дополнять. Запись для этого не годится: её поля не меняются.
Поэтому черновик — обычный класс:

```java
class ReceiptDraft {
    private final List<String> lines = new ArrayList<>();
    private int total = 0;

    void add(Item item) {                                    // пробить позицию
        int cost = item.price() * item.qty();
        lines.add(item.name() + " " + item.qty() + " × " + item.price() + " = " + cost);
        total += cost;
    }

    ReceiptDraft merge(ReceiptDraft other) {                 // слить два черновика
        lines.addAll(other.lines);
        total += other.total;
        return this;
    }

    Receipt finish() {                                       // черновик → готовый чек
        return new Receipt(List.copyOf(lines), total);
    }
}
```

`List.copyOf` делает неизменяемую копию строк: готовый чек уже
не поправить — как список из `toList()`.

### Collector.of

Четыре функции собирает в коллектор `Collector.of`:

```java
Collector<Item, ReceiptDraft, Receipt> toReceipt() {
    return Collector.of(
            ReceiptDraft::new,       // supplier: пустой черновик
            ReceiptDraft::add,       // accumulator: пробить позицию
            ReceiptDraft::merge,     // combiner: слить два черновика
            ReceiptDraft::finish);   // finisher: напечатать чек
}
```

У типа `Collector` три параметра: что едет на вход (`Item`), в чём
копим (`ReceiptDraft`) и что получится (`Receipt`). `ReceiptDraft::new` —
ссылка на конструктор, «создай новый черновик», как `TreeMap::new`
в статье 5. `ReceiptDraft::add` Java читает как
`(draft, item) -> draft.add(item)`: черновик и очередная позиция.
`ReceiptDraft::merge` — как `(left, right) -> left.merge(right)`.

Чек Веры:

```java
Receipt vera = orders.stream()
        .filter(order -> order.guest().equals("Вера"))
        .flatMap(order -> order.items().stream())    // заказы → позиции, статья 4
        .collect(toReceipt());
IO.println(vera.text());
```

```
капучино 1 × 220 = 220
латте 1 × 250 = 250
чизкейк 2 × 320 = 640
итого: 1110 ₽
```

Итог сходится с суммой её заказов: 220 + 890. А весь день одним
чеком — 14 позиций на 4490 ₽, ровно выручка из
[статьи 8](https://hammerhall.io/ledger/streams/8-number-streams).

💡 Тот же чек собирается и готовыми коллекторами — `teeing`,
`mapping` и `summingInt` дают равный чек. Свой коллектор нужен
не потому, что иначе нельзя: он даёт сборке имя, и `collect(toReceipt())`
читается одинаково везде, где нужен чек. Нужна сборка один раз —
обойдись готовыми.

### Combiner — для параллельного стрима

В обычном стриме черновик один, позиции идут в него по очереди,
и combiner не нужен. Он нужен **параллельному стриму** —
`parallelStream()` вместо `stream()`: Java делит элементы на куски,
считает каждый на своём ядре процессора в своём черновике, а потом
сливает черновики по порядку. В серии параллельных стримов нет, но
`Collector.of` требует combiner всегда.

⚠️ Combiner, который «всё равно не вызывается», — мина. Замени
`ReceiptDraft::merge` на `(left, right) -> left` — выбросить второй
черновик: обычный стрим работает как прежде, а параллельный теряет
позиции. В нашем прогоне от дневного чека осталось 3 позиции на 730 ₽
вместо 14 на 4490. Мина взорвётся в тот день, когда кто-то заменит
`stream()` на `parallelStream()`.

---

## Часть 2. `peek` — подсмотреть, что едет

### Печать без фигурных скобок

В статье 1, чтобы увидеть работу конвейера, мы вставляли печать прямо
в `filter` — с фигурными скобками и `return`. Для этого есть своя
операция — **`peek`** («подглядеть»). Она промежуточная: пропускает
каждый элемент дальше без изменений и по пути выполняет с ним действие.

```java
List<String> bigGuests = orders.stream()
        .filter(order -> order.total() >= 500)
        .peek(order -> IO.println("прошёл фильтр: заказ " + order.number()))
        .map(Order::guest)
        .toList();
```

```
прошёл фильтр: заказ 4
прошёл фильтр: заказ 6
прошёл фильтр: заказ 8
прошёл фильтр: заказ 9
[Глеб, Дина, Вера, Борис]
```

Документация так и пишет: `peek` существует в основном для отладки —
чтобы видеть элементы, когда они проходят нужную точку конвейера.
Поставил, посмотрел, убрал.

### ⚠️ Дело в `peek` пропадает

Соблазн — сделать в `peek` дело: например, заодно собрать имена
в список.

```java
List<String> seen = new ArrayList<>();
long count = orders.stream()
        .peek(order -> seen.add(order.guest()))      // дело в peek — так нельзя
        .count();
IO.println(count + " " + seen);
```

```
10 []
```

Заказов 10, а список пуст: действие в `peek` не выполнилось ни разу.
Это оговорка `count()` из статьи 1: сколько элементов, известно
из источника, и Java вправе не гонять конвейер. Документация `peek`
предупреждает о том же: где реализация может не производить элементы —
при `findFirst` или в случае `count()`, — действие для них
не выполнится. Замени `count()` на `toList().size()` — и список
заполнится. Дело, которое зависит от выбора конечной операции, — уже
не дело, а случайность.

🔑 `peek` — для глаз, а не для дела. Всё, что должно случиться, —
в конечной операции или вне конвейера.

---

## Часть 3. Когда цикл честнее

Стрим хорош, когда вопрос — «что получить»: отобрать, превратить,
собрать, посчитать. Есть задачи, где он начинает мешать. Вот три
самых частых.

### Состояние и ранний выход

Хозяйка спрашивает: на каком заказе выручка дня перевалила за 2000 ₽?
Нужна нарастающая сумма — состояние, которое переходит от заказа
к заказу, — и остановка, как только порог взят. Попробуем стримом:

```java
int running = 0;
OptionalInt reached = orders.stream()
        .filter(order -> {
            running += order.total();
            return running >= 2000;
        })
        .mapToInt(Order::number)
        .findFirst();
```

Компилятор ответит:

```
Coffee.java:159: error: local variables referenced from a lambda expression must be final or effectively final
                running += order.total();
                ^
Coffee.java:160: error: local variables referenced from a lambda expression must be final or effectively final
                return running >= 2000;
                       ^
2 errors
error: compilation failed
```

«Локальные переменные, на которые ссылается лямбда, должны быть final
или фактически final». Это правило «фактически final»
из [статьи 2](https://hammerhall.io/ledger/streams/2-filter-map-optional): лямбда пользуется
только переменными, которым значение присвоили один раз. Она получает
не саму переменную, а копию её значения:
выполниться лямбда может позже — помнишь ленивость из статьи 1? — или
вовсе в другом потоке выполнения. Меняйся переменная, копия бы врала;
поэтому Java разрешает брать только то, что уже не изменится.

Правило — про локальные переменные метода. Поэтому в
[статье 9](https://hammerhall.io/ledger/streams/9-two-collections) счётчик сравнений был
полем: лямбда держит не копию поля, а объект, которому оно
принадлежит, — в компактном файле это объект самого файла, на котором
Java запускает `main`. Объект тот же, меняется только его поле. Так же
выше прошёл `seen.add(…)`: переменная `seen` не меняется — меняется
список, на который она указывает.

⚠️ В интернете ты увидишь и третий обход — массив из одного элемента:
`int[] running = {0}` и `running[0] += …` внутри лямбды. Компилятор
доволен, но состояние спрятано в конвейере — ровно то, от чего
предостерегала статья 1. Потянуло на обход — задача просит цикл:

```java
OptionalInt reachedAt(List<Order> orders, int goal) {
    int running = 0;
    for (Order order : orders) {
        running += order.total();
        if (running >= goal) {
            return OptionalInt.of(order.number());   // порог взят — дальше не идём
        }
    }
    return OptionalInt.empty();                      // за весь день не набрали
}
```

`reachedAt(orders, 2000)` — `OptionalInt[6]`: 430 + 300 + 220 + 820 +
170 + 650 = 2590. `reachedAt(orders, 5000)` — `OptionalInt.empty`:
за день набрали 4490. Читается сверху вниз, выход — ровно там, где
найден ответ.

### Проверяемые исключения

Чековый принтер может сломаться, и метод печати честно это объявляет:

```java
void printReceipt(Order order) throws IOException {
    IO.println("чек: заказ " + order.number() + ", " + order.total() + " ₽");
}
```

**Проверяемое исключение** (checked exception) — такое, о котором Java
заставляет позаботиться: поймать в `try`/`catch` или объявить
в `throws`. `IOException` — из их числа. Напечатаем чеки крупных
заказов стримом; `forEach` — конечная операция «сделай с каждым»:

```java
orders.stream()
        .filter(order -> order.total() >= 500)
        .forEach(order -> printReceipt(order));
```

```
Coffee.java:167: error: unreported exception IOException; must be caught or declared to be thrown
            .forEach(order -> printReceipt(order));
                                          ^
1 error
error: compilation failed
```

И это при том, что `main` в примере объявлен с `throws IOException`.
Лямбда — не кусок `main`: это метод `accept` интерфейса `Consumer`,
который принимает `forEach`, а `accept` не объявляет никаких
исключений. Значит, ловить придётся внутри лямбды — `try`/`catch`
в каждой. Цикл обходится без этого:

```java
for (Order order : orders) {
    if (order.total() >= 500) {
        printReceipt(order);                         // исключение уходит наверх, как обычно
    }
}
```

### Логика по индексам

Сколько раз заказ оказывался дороже предыдущего? Нужны соседи —
элементы `i` и `i - 1`. Стримом это делают через `IntStream.range`
из статьи 8:

```java
long rises = IntStream.range(1, orders.size())
        .filter(i -> orders.get(i).total() > orders.get(i - 1).total())
        .count();
```

И циклом:

```java
int risesByLoop = 0;
for (int i = 1; i < orders.size(); i++) {
    if (orders.get(i).total() > orders.get(i - 1).total()) {
        risesByLoop++;
    }
}
```

Оба ответа — 3: заказы 4, 6 и 8. Стрим здесь — цикл в маскировке:
по конвейеру едут не заказы, а номера, и каждый шаг лезет в список
через `get`. Если в лямбде появилось `list.get(i)`, сравни с циклом
и возьми то, что читается легче. Здесь — дело вкуса; добавь к соседям
состояние — и цикл выиграет.

### Читаемость важнее изящества

🔑 Стрим — инструмент, а не экзамен. Пиши то, что коллега прочитает
через месяц без отладчика.

* Стрим — когда ответ укладывается во фразу «из чего — что — каким
  видом»: отобрать, превратить, сгруппировать, посчитать.
* Цикл — когда нужно состояние от элемента к элементу, выход
  по сложному условию, проверяемые исключения, соседи по индексам.
* Потянуло на обход — массив из одного элемента, `try`/`catch`
  в каждой лямбде, дело в `peek`, — значит, задача просит цикл.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Назови четыре функции коллектора и что каждая делает для чека.
   Какая из них не вызывается в обычном стриме?
2. Почему черновик чека — класс, а готовый чек — запись?
3. Что означают три типа в `Collector<Item, ReceiptDraft, Receipt>`?
4. Зачем писать честный combiner, если в коде нет параллельных стримов?
5. Для чего нужен `peek`? Почему в примере с `count()` список `seen`
   остался пустым?
6. Что значит «фактически final»? Почему `running += …`
   в лямбде не компилируется, а `seen.add(…)` — компилируется?
7. Почему лямбда в `forEach` не может бросить `IOException`, даже если
   `main` объявлен с `throws IOException`?
8. Назови три признака того, что задачу лучше решить циклом.

---

## Реши в кузнице

Задачи, где пригодится всё сразу — числа, коллекторы и выбор между
стримом и циклом, — в кузнице Stream Forge на платформе Hammerhall.
Все три бесплатны, нужен только вход:

* [«Найти континент с максимальной плотностью населения»](https://hammerhall.io/forge/stream-forge/task/WldMind0022);
* [«Построить последовательность роста населения»](https://hammerhall.io/forge/stream-forge/task/WldMind0018);
* [«Получить „временной срез“ базы — N самых ранних и N самых поздних фильмов»](https://hammerhall.io/forge/stream-forge/task/MovMind0022).

## Что дальше

Серия закончена. Десять статей прошли путь от первого `filter`
до своего коллектора: конвейер и ленивость, `Optional`, сортировка,
`flatMap`, группировки и коллекторы внутри групп, стримы по картам,
числа, две коллекции.

Дальше — практика. Реши бесплатные задачи кузницы из всех десяти
статей: каждая закрепляет свой приём на чужих данных. Потом — ступени
кузницы сложнее, они уже за пределами бесплатных: задачи на пары
элементов, на соединение нескольких коллекций, на свои коллекторы
целиком.

## Первоисточники

* [Interface Collector — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Collector.html) —
  четыре функции коллектора; `Collector.of`; что значат `T`, `A`, `R`.
* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  `peek`: API Note «exists mainly to support debugging» и оговорка
  про `findFirst` и `count()`.
* [Package java.util.stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/package-summary.html) —
  разделы «Side-effects» (`forEach` и `peek` — «should be used with
  care») и «Mutable reduction» — как `collect` копит в контейнер.
* [JLS 25, §15.27.2 Lambda Body](https://docs.oracle.com/javase/specs/jls/se25/html/jls-15.html#jls-15.27.2) —
  спецификация языка: какие переменные можно использовать в лямбде.

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Устроен файл, как в [статье 1](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop):
записи и класс вверху, методы и `main` — без класса вокруг. Заказы
те же, `total()` — стримом, как в статье 8; новое — запись `Receipt`,
класс `ReceiptDraft` и коллектор `toReceipt()`. `main` объявлен
с `throws IOException` — из-за печати чеков. Сохрани файл как
`Coffee.java` и запусти из его папки:

```bash
java Coffee.java
```

Если вместо русских букв в выводе вопросы или кракозябры, запусти
с явной кодировкой: `java "-Dstdout.encoding=UTF-8" Coffee.java`;
в командной строке Windows перед этим выполни `chcp 65001`. Сообщения
об ошибках Java печатает отдельным потоком — если вопросы в них,
добавь ещё `"-Dstderr.encoding=UTF-8"`.

```java
// Coffee.java — учебный пример статьи 10 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.OptionalInt;
import java.util.stream.Collector;
import java.util.stream.IntStream;

/** Позиция заказа: напиток или десерт, цена за штуку в рублях, сколько штук. */
record Item(String name, int price, int qty) {}

/** Заказ: номер за день, имя гостя, позиции. */
record Order(int number, String guest, List<Item> items) {

    /** Сумма заказа в рублях — стримом, как в статье 8. */
    int total() {
        return items.stream()
                .mapToInt(item -> item.price() * item.qty())
                .sum();
    }
}

/** Чек: строки позиций и итог в рублях. */
record Receipt(List<String> lines, int total) {

    /** Чек текстом: по строке на позицию, внизу итог. */
    String text() {
        return String.join("\n", lines) + "\nитого: " + total + " ₽";
    }
}

/** Черновик чека: копит строки и сумму, пока по конвейеру едут позиции. */
class ReceiptDraft {
    private final List<String> lines = new ArrayList<>();
    private int total = 0;

    /** Пробить позицию. */
    void add(Item item) {
        int cost = item.price() * item.qty();
        lines.add(item.name() + " " + item.qty() + " × " + item.price() + " = " + cost);
        total += cost;
    }

    /** Слить два черновика: сначала свои строки, потом чужие. */
    ReceiptDraft merge(ReceiptDraft other) {
        lines.addAll(other.lines);
        total += other.total;
        return this;
    }

    /** Напечатать чек: черновик → готовый неизменяемый чек. */
    Receipt finish() {
        return new Receipt(List.copyOf(lines), total);
    }
}

/** Заказы кофейни «Наковальня» за один день. */
List<Order> orders() {
    return List.of(
            new Order(1, "Анна", List.of(new Item("латте", 250, 1), new Item("круассан", 180, 1))),
            new Order(2, "Борис", List.of(new Item("эспрессо", 150, 2))),
            new Order(3, "Вера", List.of(new Item("капучино", 220, 1))),
            new Order(4, "Глеб", List.of(new Item("латте", 250, 2), new Item("чизкейк", 320, 1))),
            new Order(5, "Анна", List.of(new Item("американо", 170, 1))),
            new Order(6, "Дина", List.of(new Item("раф", 290, 1), new Item("круассан", 180, 2))),
            new Order(7, "Егор", List.of(new Item("эспрессо", 150, 1))),
            new Order(8, "Вера", List.of(new Item("латте", 250, 1), new Item("чизкейк", 320, 2))),
            new Order(9, "Борис", List.of(new Item("капучино", 220, 3))),
            new Order(10, "Жанна", List.of(new Item("какао", 200, 1))));
}

/** Свой коллектор: позиции → чек. */
Collector<Item, ReceiptDraft, Receipt> toReceipt() {
    return Collector.of(
            ReceiptDraft::new,       // supplier: пустой черновик
            ReceiptDraft::add,       // accumulator: пробить позицию
            ReceiptDraft::merge,     // combiner: слить два черновика
            ReceiptDraft::finish);   // finisher: напечатать чек
}

/** Номер заказа, на котором выручка дня впервые достигла цели. */
OptionalInt reachedAt(List<Order> orders, int goal) {
    int running = 0;
    for (Order order : orders) {
        running += order.total();
        if (running >= goal) {
            return OptionalInt.of(order.number());
        }
    }
    return OptionalInt.empty();
}

/** Печать чека. Объявлена с IOException, как настоящий ввод-вывод: принтер может сломаться. */
void printReceipt(Order order) throws IOException {
    IO.println("чек: заказ " + order.number() + ", " + order.total() + " ₽");
}

void main() throws IOException {
    List<Order> orders = orders();

    // 1. Свой коллектор: чек Веры за день
    Receipt vera = orders.stream()
            .filter(order -> order.guest().equals("Вера"))
            .flatMap(order -> order.items().stream())
            .collect(toReceipt());
    IO.println(vera.text());

    // 2. Весь день одним чеком — итог сходится с выручкой
    Receipt day = orders.stream()
            .flatMap(order -> order.items().stream())
            .collect(toReceipt());
    IO.println("позиций: " + day.lines().size() + ", итого: " + day.total());

    // 3. peek — подсмотреть, что едет по конвейеру
    List<String> bigGuests = orders.stream()
            .filter(order -> order.total() >= 500)
            .peek(order -> IO.println("прошёл фильтр: заказ " + order.number()))
            .map(Order::guest)
            .toList();
    IO.println(bigGuests);

    // 4. Логика в peek пропадает: count() вправе не гонять конвейер
    List<String> seen = new ArrayList<>();
    long count = orders.stream()
            .peek(order -> seen.add(order.guest()))
            .count();
    IO.println(count + " " + seen);

    // 5. Ранний выход с состоянием — циклом в методе reachedAt
    IO.println(reachedAt(orders, 2000));
    IO.println(reachedAt(orders, 5000));

    // 6. Проверяемое исключение — циклом
    for (Order order : orders) {
        if (order.total() >= 500) {
            printReceipt(order);
        }
    }

    // 7. Логика по индексам: заказ дороже предыдущего — стримом и циклом
    long rises = IntStream.range(1, orders.size())
            .filter(i -> orders.get(i).total() > orders.get(i - 1).total())
            .count();
    int risesByLoop = 0;
    for (int i = 1; i < orders.size(); i++) {
        if (orders.get(i).total() > orders.get(i - 1).total()) {
            risesByLoop++;
        }
    }
    IO.println("дороже предыдущего: " + rises + " и " + risesByLoop);

    // Сделай руками — раскомментируй один блок, запусти, верни комментарий.
    // Блок А: счётчик в лямбде — ошибка компиляции
    // int running = 0;
    // OptionalInt reached = orders.stream()
    //         .filter(order -> {
    //             running += order.total();
    //             return running >= 2000;
    //         })
    //         .mapToInt(Order::number)
    //         .findFirst();
    // Блок Б: проверяемое исключение в лямбде — ошибка компиляции
    // orders.stream()
    //         .filter(order -> order.total() >= 500)
    //         .forEach(order -> printReceipt(order));
}
```

Сделай руками:

1. Запусти файл. Сначала — чек Веры с `итого: 1110 ₽`, потом
   `позиций: 14, итого: 4490`, четыре строки «прошёл фильтр», `10 []`,
   `OptionalInt[6]`, `OptionalInt.empty`, четыре чека
   и `дороже предыдущего: 3 и 3`.
2. Раскомментируй блок А — две ошибки «must be final or effectively
   final». Верни комментарии.
3. Раскомментируй блок Б — ошибка «unreported exception IOException».
   Верни комментарии.
4. В блоке `// 4.` замени `.count()` на `.toList().size()` — список
   заполнится: `10 [Анна, Борис, Вера, Глеб, Анна, Дина, Егор, Вера,
   Борис, Жанна]`. Верни как было.
5. В блоке `// 2.` замени `orders.stream()` на `orders.parallelStream()` —
   ответ тот же, `позиций: 14, итого: 4490`. Теперь в `toReceipt()`
   замени `ReceiptDraft::merge` на `(left, right) -> left`: чек Веры
   не изменится, а дневной потеряет позиции. Сколько — зависит от числа
   ядер; в нашем прогоне — `позиций: 3, итого: 730`. Верни всё как было.
