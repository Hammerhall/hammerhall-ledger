# Числа: `IntStream`, суммы и переполнение

> «Стримы по шагам» · статья 8 · читать минут 20
>
> **Для кого.** Ты прочитал статьи 1–7 серии или знаешь то же сам:
> конвейер, лямбды и ссылки на методы, `Optional`, сортировку,
> `collect` и коллекторы внутри группы. Сумму по стриму считал
> через `summingInt` — или по старинке циклом.
>
> **Что будет.** Почему у стрима из `Integer` нет `sum()` и что взять
> вместо него; что вернёт среднее, когда считать не из чего; как
> стрим заменяет счётный цикл `for (int i = …)`; почему сумма `int`
> может молча соврать — и как это поймать.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем числовые стримы

Конец дня в кофейне «Наковальня». Хозяйка спрашивает главное: сколько
выручили?

Сумма заказа есть — `total()`. Сложить суммы всех заказов — кажется,
это `map` и что-нибудь вроде `sum()`:

```java
int revenue = orders.stream()
        .map(Order::total)                       // заказ → его сумма
        .sum();                                  // так не скомпилируется
```

Компилятор не согласен:

```
Coffee.java:45: error: cannot find symbol
            .sum();
            ^
  symbol:   method sum()
  location: interface Stream<Integer>
1 error
error: compilation failed
```

Строка `location:` говорит, где Java искала `sum()`: у `Stream<Integer>`.
И не нашла. Можно выкрутиться коллектором из
[статьи 6](https://hammerhall.io/ledger/streams/6-downstream-collectors) —
`collect(Collectors.summingInt(Order::total))`, — но для простой
суммы это громоздко.

В этой статье — стримы, которые умеют считать: сумма, среднее,
максимум, сводка за один проход. Метод `total()` наконец станет
стримом, как обещала статья 1. А в конце — ловушка, в которой выручка
сети кофеен уходит в минус на миллиард, и никто об этом не сообщает.

---

## Часть 1. `mapToInt` и `IntStream`

### Почему у `Stream<Integer>` нет суммы

`Order::total` возвращает `int` — простое число. Но по обычному стриму
едут только объекты, а `int` не объект. Поэтому Java молча кладёт
каждое число в объект-обёртку `Integer`. Это называется **упаковка**
(boxing): `int` → `Integer`; обратный путь — распаковка.

Отсюда две беды:

* лишняя работа: каждое число — отдельный объект в памяти, и чтобы
  сложить, каждый надо распаковать. Как раскладывать мелочь
  по конвертам, чтобы потом пересчитать;
* нет `sum()`: `Stream<T>` написан для любых `T` — строк, заказов,
  гостей. Что такое сумма строк? Стрим не знает, что внутри числа,
  поэтому ни `sum()`, ни `average()` у него нет.

### `mapToInt` — конвейер для чисел

```java
int revenue = orders.stream()
        .mapToInt(Order::total)                  // заказ → число int, без обёртки
        .sum();                                  // сложить
```

Ответ — `4490`. `mapToInt` превращает каждый элемент в `int`, как
`map`, но отдаёт не `Stream<Integer>`, а **`IntStream`** — стрим простых
чисел `int`. Это тот же конвейер — с `filter`, `map`, `limit`,
ленивостью и одноразовостью из статьи 1, — только числа едут без
обёрток, и у него есть арифметика: `sum()`, `average()`, `min()`,
`max()`.

Таких стримов три — по основным типам чисел:

| стрим | что едет | как перейти из обычного стрима |
|---|---|---|
| `IntStream` | `int` | `mapToInt(…)` |
| `LongStream` | `long` | `mapToLong(…)` |
| `DoubleStream` | `double` | `mapToDouble(…)` |

`summingInt` из статьи 6 даёт те же `4490`. Его место — внутри группы,
в `groupingBy`; для суммы по всему стриму `mapToInt(…).sum()` короче.

### `total()` — стримом

Статья 1 обещала: метод `total()`, который считал сумму заказа циклом,
станет стримом. Сумма позиций — ровно то, что умеет
`mapToInt(…).sum()`:

```java
record Order(int number, String guest, List<Item> items) {
    int total() {                                              // сумма заказа в рублях
        return items.stream()
                .mapToInt(item -> item.price() * item.qty())   // позиция → её стоимость
                .sum();
    }
}
```

Счётчик, `for`, `+=` — всё ушло, осталась фраза: «позиции — их
стоимость — сумма». Поля записи и их порядок не тронуты, поменялось
только тело метода. Это единственная правка `Item` и `Order` за всю
серию; дальше `total()` — такой.

Суммы заказов прежние — проверим, напечатав их списком:

```java
IO.println(orders.stream().map(Order::total).toList());
```

```
[430, 300, 220, 820, 170, 650, 150, 890, 660, 200]
```

Здесь `map`, а не `mapToInt`, и это не ошибка: список хранит объекты,
так что обёртки тут к месту. Числовой стрим нужен, когда с числами
считают.

---

## Часть 2. Среднее, максимум — и пустой стрим

### `average()` возвращает не число

Средний чек:

```java
OptionalDouble average = orders.stream()
        .mapToInt(Order::total)
        .average();
IO.println(average);                             // OptionalDouble[449.0]
```

Не просто число `449.0`, а `449.0` в коробке **`OptionalDouble`** — это `Optional`
из [статьи 2](https://hammerhall.io/ledger/streams/2-filter-map-optional), только для
простого `double`. Зачем коробка, видно на пустом стриме. Заказов
от 1000 ₽ за день не было:

```java
OptionalDouble none = orders.stream()
        .filter(order -> order.total() >= 1000)  // таких заказов нет
        .mapToInt(Order::total)
        .average();
IO.println(none);                                // OptionalDouble.empty
```

Среднее от ничего — ноль, делённый на ноль: ответа нет, и Java говорит
об этом честно, пустой коробкой. А `sum()` того же пустого стрима
вернёт просто `0`: сумма ничего — ноль, тут спорить не о чем.

Многие методы у `OptionalDouble` те же, что у `Optional`: `orElse`,
`orElseThrow`, `isPresent`. Отличий два: значение достают не `get()`,
а `getAsDouble()`, и `map` у `OptionalDouble` нет.

### `max()` и `OptionalInt`

Самый крупный заказ:

```java
int biggest = orders.stream()
        .mapToInt(Order::total)
        .max()                                   // OptionalInt[890]
        .orElseThrow();                          // заказов нет — исключение
```

Ответ — `890`. У `IntStream` метод `max()` без компаратора, в отличие
от `max(Comparator)` из [статьи 3](https://hammerhall.io/ledger/streams/3-sorting): числа
сравнивать умеют сами. Возвращает он **`OptionalInt`** — по той же
причине: у пустого стрима максимума нет. `orElseThrow()` здесь —
осознанный выбор: день без единого заказа — повод упасть громко,
а не вернуть выдуманный ноль. Достать значение из `OptionalInt`
без `orElse…` — `getAsInt()`.

### `summaryStatistics()` — всё за один проход

Хозяйке нужна сводка: сколько заказов, выручка, средний чек, самый
крупный. Четыре стрима подряд — четыре прохода по списку. Можно одним:

```java
IntSummaryStatistics stats = orders.stream()
        .mapToInt(Order::total)
        .summaryStatistics();
IO.println(stats.getCount() + " заказов, выручка " + stats.getSum()
        + ", средний чек " + stats.getAverage() + ", самый крупный " + stats.getMax());
```

```
10 заказов, выручка 4490, средний чек 449.0, самый крупный 890
```

**`IntSummaryStatistics`** — сводка, которую конвейер собирает за один
проход: количество, сумма, минимум, максимум, среднее. Её можно
напечатать и целиком, но методы `getCount()`, `getSum()`, `getMin()`,
`getMax()`, `getAverage()` надёжнее: печать целиком зависит от языка
системы, и в русской среднее выйдет как `449,000000`.

### ⚠️ Сводка пустого стрима

У сводки `Optional` нет. Вот она для того же пустого стрима — заказов
от 1000 ₽:

```java
IntSummaryStatistics empty = orders.stream()
        .filter(order -> order.total() >= 1000)
        .mapToInt(Order::total)
        .summaryStatistics();
IO.println(empty.getCount() + " " + empty.getMax() + " " + empty.getAverage());
```

```
0 -2147483648 0.0
```

Самый крупный заказ — минус два миллиарда, средний чек — ноль. Так
и задумано: документация обещает для пустой сводки максимум
`Integer.MIN_VALUE`, минимум `Integer.MAX_VALUE`, сумму и среднее —
ноль. Отсюда правило: прежде чем верить сводке, проверь `getCount()`.

### ⚠️ Среднее — `double`, деньги — целые

Средний чек вышел дробным: `average()` всегда возвращает `double`.
Показать среднее так — нормально. А деньги в `double` не храни
и не складывай: дробные числа в компьютере приблизительные, и `0.1 + 0.2`
в Java — `0.30000000000000004`. Цены в серии — целые рубли, `int`.
Понадобятся копейки — храни целое число копеек.

---

## Часть 3. Счётный цикл — стримом

### `range` и `rangeClosed`

Иногда стрим нужен не по списку, а по числам подряд. Кофейня открыта
с 8 до 22, и приложению для предзаказа нужен список часов. На курсе
это цикл `for (int hour = 8; hour < 22; hour++)`. Стримом:

```java
List<String> slots = IntStream.range(8, 22)      // 8, 9, …, 21
        .mapToObj(hour -> hour + ":00")          // число → строка «8:00»
        .toList();
```

```
[8:00, 9:00, 10:00, 11:00, 12:00, 13:00, 14:00, 15:00, 16:00, 17:00, 18:00, 19:00, 20:00, 21:00]
```

`IntStream.range(8, 22)` — числа от 8 до 21: левый конец входит,
правый нет, как в условии `hour < 22`. В 22:00 кофейня уже закрыта,
предзаказ на это время не нужен. Если правый конец нужен —
`rangeClosed`: `IntStream.rangeClosed(8, 22)` даёт 15 чисел вместо 14.

⚠️ Перепутать их — классическая ошибка «на единицу». Читай `range`
как «до», а `rangeClosed` — как «по … включительно».

### `boxed` и `mapToObj` — обратно к объектам

У `IntStream` нет `toList()`: список хранит объекты, а по числовому
стриму едут простые числа. Обратно к объектам ведут два пути:

* `mapToObj(…)` — превратить каждое число в любой объект; так выше
  из часа получилась строка;
* `boxed()` — завернуть каждое число в `Integer`, получится
  `Stream<Integer>`.

Вечерней смене нужны номерки — номера заказов с 11 по 15:

```java
List<Integer> tickets = IntStream.rangeClosed(11, 15)   // 11, 12, 13, 14, 15
        .boxed()                                         // int → Integer
        .toList();
```

```
[11, 12, 13, 14, 15]
```

💡 Пара «туда и обратно»: `mapToInt` уводит от объектов к числам,
`boxed` и `mapToObj` возвращают. К числам — когда считаешь, обратно —
когда собираешь.

---

## Часть 4. Переполнение: сумма, которая молча врёт

### Сеть за год

Хозяйка мечтает о сети: 20 кофеен, и каждая торгует, как «Наковальня»
сегодня. Бухгалтерия считает в копейках. Сколько сеть выручит за год?

```java
int dayKopecks = revenue * 100;                  // день одной кофейни: 449 000 коп.
int chainDay = dayKopecks * 20;                  // день сети из 20 кофеен
int chainYear = IntStream.rangeClosed(1, 365)    // дни года
        .map(day -> chainDay)                    // каждый день — как сегодня
        .sum();
IO.println("сеть за год, int: " + chainYear);
```

```
сеть за год, int: -1017267296
```

Выручка — минус миллиард. Ни исключения, ни предупреждения: программа
отработала и выдала уверенный ответ.

Это **переполнение** (overflow). В `int` помещаются числа
от −2 147 483 648 до 2 147 483 647, самое большое из них —
`Integer.MAX_VALUE`. Настоящая выручка — 3 277 700 000 копеек —
не влезает. Java не сообщает об ошибке, а продолжает счёт по кругу:
за самым большим числом идёт самое маленькое. Как механический счётчик
пробега в старой машине: после 999 999 снова 000 000.

```java
IO.println(Integer.MAX_VALUE);                   // 2147483647
IO.println(Integer.MAX_VALUE + 1);               // -2147483648
```

🔑 `int` переполняется молча. Спецификация Java так и пишет: операции
над целыми никак не сообщают о переполнении. Здесь ошибку выдал
странный ответ — отрицательная выручка. Но ответ мог выйти
и правдоподобным: у сети из 60 кофеен сумма дважды перескочит через
предел и получится положительной — 1 243 165 408 вместо
9 833 100 000.

### `long` — с запасом

Лекарство — считать в **`long`**: это целое до
9 223 372 036 854 775 807, больше девяти миллиардов миллиардов.
Хватит на копейки любой сети кофеен.

```java
long chainYearLong = IntStream.rangeClosed(1, 365)
        .mapToLong(day -> chainDay)              // каждый день — уже long
        .sum();                                  // сумма LongStream — long
```

```
сеть за год, long: 3277700000
```

`mapToLong` переводит конвейер в `LongStream`, и сумма считается
в `long`. Из стрима заказов — так же: `orders.stream().mapToLong(Order::total).sum()`.

⚠️ `long` спасает сложение, но не умножение внутри лямбды. Сеть
из 5000 кофеен: `mapToLong(day -> dayKopecks * 5000)`. Здесь оба числа
`int`, перемножатся они в `int` и переполнятся раньше, чем результат
станет `long`. Сделай одно из чисел `long` — `dayKopecks * 5000L`, —
и всё умножение пойдёт в `long`.

💡 `summingInt` из статьи 6 тоже считает в `int` и переполняется
так же; для больших сумм есть `summingLong`. А `summaryStatistics()`
хранит сумму в `long`: её `getSum()` для сети за год вернёт честные
3 277 700 000.

### `Math.addExact` — громко

Бывает, что такой большой суммы быть не должно, и если она случилась —
это ошибка в данных. Тогда лучше не расширять тип, а упасть. Для этого
есть `Math.addExact(a, b)`: складывает, как `+`, но при переполнении
бросает исключение.

Как подставить её в стрим? Документация `IntStream` раскрывает, что
такое `sum()`: это `reduce(0, Integer::sum)`. **Свёртка**
`reduce(начало, функция)` берёт начальное значение и по очереди
присоединяет к нему каждый элемент: 0 + первый, к результату — второй,
и так до конца. Подставим вместо обычного сложения строгое:

```java
int loud = IntStream.rangeClosed(1, 365)
        .map(day -> chainDay)
        .reduce(0, Math::addExact);              // сложение с проверкой
```

```
Exception in thread "main" java.lang.ArithmeticException: integer overflow
```

Что выбрать: `long` — когда большие суммы законны, как выручка
за год. `addExact` — когда переполнение означает, что где-то ошибка,
и молчаливый неверный ответ хуже падения.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему у `orders.stream().map(Order::total)` нет метода `sum()`,
   а у `orders.stream().mapToInt(Order::total)` — есть?
2. Что такое упаковка и почему `IntStream` обходится без неё?
3. Почему `average()` возвращает `OptionalDouble`, а `sum()` — просто
   число? Что вернёт каждый из них на пустом стриме?
4. Что вернёт `getMax()` сводки по пустому стриму? Что проверить,
   прежде чем верить сводке?
5. Сколько чисел даст `IntStream.range(8, 22)`, а сколько
   `rangeClosed(8, 22)`? Как из `IntStream` получить список?
6. Сеть кофеен за год «выручила» минус миллиард. Что произошло и почему
   Java не сообщила об ошибке?
7. Чем отличаются две защиты — `mapToLong` и `reduce(0, Math::addExact)`?
   Когда какую выбрать?
8. В `mapToLong(day -> dayKopecks * 5000)` сумма считается в `long`.
   Почему ответ всё равно может быть неверным?

---

## Реши в кузнице

Задачи на суммы, средние и сводки — в кузнице Stream Forge
на платформе Hammerhall, на странах и городах мира. Первые задачи
бесплатны, нужен только вход:

* [«Вычислить суммарную численность населения всех городов мира»](https://hammerhall.io/forge/stream-forge/task/WldCode0009);
* [«Найти минимальное, максимальное и среднее население стран мира»](https://hammerhall.io/forge/stream-forge/task/WldCode0021);
* [«Найти страны, где сумма населения городов больше населения страны»](https://hammerhall.io/forge/stream-forge/task/WldMind0019).

## Что дальше

Статья 9 — две коллекции. У гостей появляются карты лояльности, и
заказы нужно сопоставить с ними: как сделать это через индекс,
а не стримом внутри стрима.

## Первоисточники

* [Interface IntStream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/IntStream.html) —
  `sum()` как `reduce(0, Integer::sum)`; `average()` и `max()`
  на пустом стриме; `range`, `rangeClosed`, `boxed`.
* [Class IntSummaryStatistics — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/IntSummaryStatistics.html) —
  что возвращает сводка, если значений не было; `getSum()` — `long`.
* [Class Math — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Math.html) —
  `addExact` и абзац в начале страницы о методах `…Exact`.
* [JLS 25, §4.2.2 Integer Operations](https://docs.oracle.com/javase/specs/jls/se25/html/jls-4.html#jls-4.2.2) —
  спецификация языка: целые операции «никак не сообщают
  о переполнении»; диапазоны `int` и `long` — в §4.2.1 рядом.

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Устроен файл, как в [статье 1](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop):
записи вверху, методы `orders()` и `main` — без класса вокруг. Заказы
те же; у `Order` новое только тело `total()`. Сохрани файл как
`Coffee.java` и запусти из его папки:

```bash
java Coffee.java
```

Если вместо русских букв в выводе вопросы или кракозябры, запусти
с явной кодировкой: `java "-Dstdout.encoding=UTF-8" Coffee.java`;
в командной строке Windows перед этим выполни `chcp 65001`.

```java
// Coffee.java — учебный пример статьи 8 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.IntSummaryStatistics;
import java.util.List;
import java.util.OptionalDouble;
import java.util.stream.Collectors;
import java.util.stream.IntStream;

/** Позиция заказа: напиток или десерт, цена за штуку в рублях, сколько штук. */
record Item(String name, int price, int qty) {}

/** Заказ: номер за день, имя гостя, позиции. */
record Order(int number, String guest, List<Item> items) {

    /** Сумма заказа в рублях. С этой статьи — стримом. */
    int total() {
        return items.stream()
                .mapToInt(item -> item.price() * item.qty())
                .sum();
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

void main() {
    List<Order> orders = orders();

    // 1. Выручка за день: mapToInt и sum
    int revenue = orders.stream()
            .mapToInt(Order::total)
            .sum();
    IO.println("выручка: " + revenue);

    // 2. То же коллектором из статьи 6 — длиннее
    int byCollector = orders.stream()
            .collect(Collectors.summingInt(Order::total));
    IO.println("коллектором: " + byCollector);

    // 3. total() теперь стрим — суммы заказов те же
    IO.println(orders.stream().map(Order::total).toList());

    // 4. Средний чек — OptionalDouble
    OptionalDouble average = orders.stream()
            .mapToInt(Order::total)
            .average();
    IO.println(average);

    // 5. Пустой стрим: среднего нет, сумма — 0
    OptionalDouble none = orders.stream()
            .filter(order -> order.total() >= 1000)
            .mapToInt(Order::total)
            .average();
    IO.println(none);
    int noneSum = orders.stream()
            .filter(order -> order.total() >= 1000)
            .mapToInt(Order::total)
            .sum();
    IO.println(noneSum);

    // 6. Самый крупный заказ — OptionalInt
    int biggest = orders.stream()
            .mapToInt(Order::total)
            .max()
            .orElseThrow();
    IO.println("самый крупный: " + biggest);

    // 7. Сводка за один проход
    IntSummaryStatistics stats = orders.stream()
            .mapToInt(Order::total)
            .summaryStatistics();
    IO.println(stats.getCount() + " заказов, выручка " + stats.getSum()
            + ", средний чек " + stats.getAverage() + ", самый крупный " + stats.getMax());

    // 8. Сводка пустого стрима: Optional нет, максимум — странное число
    IntSummaryStatistics empty = orders.stream()
            .filter(order -> order.total() >= 1000)
            .mapToInt(Order::total)
            .summaryStatistics();
    IO.println(empty.getCount() + " " + empty.getMax() + " " + empty.getAverage());

    // 9. Часы работы: range — правый конец не входит
    List<String> slots = IntStream.range(8, 22)
            .mapToObj(hour -> hour + ":00")
            .toList();
    IO.println(slots);

    // 10. Номерки: rangeClosed — правый конец входит; boxed — обратно к Integer
    List<Integer> tickets = IntStream.rangeClosed(11, 15)
            .boxed()
            .toList();
    IO.println(tickets);

    // 11. Переполнение: сеть из 20 кофеен за год, в копейках
    int dayKopecks = revenue * 100;
    int chainDay = dayKopecks * 20;
    int chainYear = IntStream.rangeClosed(1, 365)
            .map(day -> chainDay)
            .sum();
    IO.println("сеть за год, int: " + chainYear);

    // 12. То же в long — верно
    long chainYearLong = IntStream.rangeClosed(1, 365)
            .mapToLong(day -> chainDay)
            .sum();
    IO.println("сеть за год, long: " + chainYearLong);

    // 13. Предел int и что за ним
    IO.println(Integer.MAX_VALUE);
    IO.println(Integer.MAX_VALUE + 1);

    // Сделай руками — раскомментируй три строки и запусти: ArithmeticException
    // int loud = IntStream.rangeClosed(1, 365)
    //         .map(day -> chainDay)
    //         .reduce(0, Math::addExact);
}
```

Сделай руками:

1. Запусти файл. Первые строки — `выручка: 4490`, `коллектором: 4490`
   и список сумм заказов; ближе к концу — `сеть за год, int: -1017267296`
   и `сеть за год, long: 3277700000`.
2. В блоке `// 1.` замени `mapToInt` на `map` и прочитай ошибку
   компилятора: `Stream<Integer>` и нет `sum()`. Верни как было.
3. Замени `1000` на `800` во всех трёх фильтрах — в блоках `// 5.`
   и `// 8.`. Среднее станет `OptionalDouble[855.0]`, сумма — `1710`,
   сводка — `2 890 855.0`: таких заказов два. Верни `1000`.
4. В блоке `// 9.` замени `range` на `rangeClosed` — в конце списка
   появится `22:00`. Верни как было.
5. В блоке `// 11.` замени `20` на `60`: `int` покажет правдоподобные
   `1243165408`, `long` — настоящие `9833100000`. Верни `20`.
6. Раскомментируй три строки с `Math::addExact` в конце `main` —
   увидишь `ArithmeticException: integer overflow`. Верни комментарии.
