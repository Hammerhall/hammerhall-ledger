# Коллекторы внутри группы

> «Стримы по шагам» · статья 6 · читать минут 15
>
> **Для кого.** Ты прочитал статью 5: `collect`, `groupingBy`,
> `counting()`, `TreeMap::new`. Помнишь `Optional` из статьи 2,
> компараторы из статьи 3 и `flatMap` из статьи 4.
>
> **Что будет.** Как получить в каждой группе то, что нужно, а не
> список заказов: номера, сумму, среднее, самый крупный чек; почему
> `maxBy` отвечает `Optional`; как доделать ответ коллектора через
> `collectingAndThen`; чем `filtering` отличается от `filter`; что такое
> `flatMapping` и `teeing`.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем коллекторы внутри группы

Хозяйка «Наковальни» спрашивает: сколько потратил за день каждый
гость? Статья 5 дала группы — списки заказов по гостям. Остаётся
пройти по каждому списку и сложить суммы:

```java
Map<String, List<Order>> byGuest = orders.stream()
        .collect(Collectors.groupingBy(Order::guest, TreeMap::new, Collectors.toList()));
Map<String, Integer> spentLoop = new TreeMap<>();
for (String guest : byGuest.keySet()) {               // по каждому гостю
    int sum = 0;
    for (Order order : byGuest.get(guest)) {          // по каждому его заказу
        sum += order.total();
    }
    spentLoop.put(guest, sum);
}
```

`keySet()` — все ключи карты. Работает, но стрим собрал группы только
затем, чтобы два цикла тут же их разобрали. Есть ещё `toMap`
с функцией слияния из статьи 5 — для суммы он годится. Но попроси
номера заказов списком, средний чек или самый крупный заказ — и функция
слияния станет головоломкой.

То же без циклов:

```java
Map<String, Integer> spent = orders.stream()
        .collect(Collectors.groupingBy(Order::guest, TreeMap::new, Collectors.summingInt(Order::total)));
```

```
{Анна=600, Борис=960, Вера=1110, Глеб=820, Дина=650, Егор=150, Жанна=200}
```

Последний аргумент `groupingBy` — **коллектор для группы**
(в документации — downstream, «ниже по течению»): рецепт, что сделать
с каждой группой.
Первым таким был `counting()` из статьи 5. Здесь — остальные.

🔑 `groupingBy` раскладывает заказы по стопкам, коллектор для группы
решает, что сделать с каждой стопкой: пересчитать, сложить, взять
самый крупный. Меняется вопрос — меняется только он.

---

## Часть 1. Превратить, сложить, усреднить

### Статический импорт

Строка из «Зачем» — уже за сто символов, а дальше коллекторы будут
вкладываться друг в друга по два и по три. `Collectors.` перед каждым
съест строку. Поэтому с этой статьи в примерах — **статический
импорт**:

```java
import static java.util.stream.Collectors.*;
```

Обычный `import` разрешает писать класс без пакета, `import static` —
статический метод без класса: `groupingBy(…)` вместо
`Collectors.groupingBy(…)`. Звёздочка — все такие методы класса сразу.
Импорт стоит вверху файла, в «Примере целиком»; в коротких кусках его
не видно.

### mapping — map внутри группы

Хозяйке для отчёта нужны номера заказов каждого гостя — строкой,
а не заказы целиком:

```java
Map<String, String> numbersByGuest = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                mapping(order -> "№" + order.number(), joining(" "))));
```

```
{Анна=№1 №5, Борис=№2 №9, Вера=№3 №8, Глеб=№4, Дина=№6, Егор=№7, Жанна=№10}
```

`mapping` — тот же `map` из статьи 1, только внутри группы. Аргумента
два: функция — во что превратить каждый элемент группы (заказ — в строку
«№1») — и ещё один коллектор: что сделать с превращённым. Здесь это
`joining(" ")` — ещё один готовый коллектор: он склеивает строки через
разделитель в том порядке, в каком они пришли. Вложенность читается
слева направо: «по гостю, в `TreeMap`, номера — через пробел».

### summingInt — сложить

`summingInt` складывает число, которое функция достаёт из каждого
элемента группы. Выручка с гостя в «Зачем» — `summingInt(Order::total)`.
А вот и чашки, обещанные в статье 5:

```java
Map<String, Integer> portionsByItem = orders.stream()
        .flatMap(order -> order.items().stream())
        .collect(groupingBy(Item::name, TreeMap::new, summingInt(Item::qty)));
```

```
{американо=1, какао=1, капучино=4, круассан=3, латте=4, раф=1, чизкейк=3, эспрессо=3}
```

Латте — 4: `counting()` считал позиции, `summingInt(Item::qty)`
складывает штуки. Ответ — `Integer`. Для чисел `long` и `double` есть
`summingLong` и `summingDouble`.

### averagingInt — среднее, и оно Double

Средний чек гостя:

```java
Map<String, Double> averageByGuest = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new, averagingInt(Order::total)));
```

```
{Анна=300.0, Борис=480.0, Вера=555.0, Глеб=820.0, Дина=650.0, Егор=150.0, Жанна=200.0}
```

Суммы заказов целые, а ответ — `Double`, с `.0`. Среднее целых чисел
редко бывает целым, и `averagingInt` его не округляет. Здесь просто
повезло: у каждого гостя суммы делятся нацело.

⚠️ Объявишь `Map<String, Integer>` — компилятор ответит ошибкой
того же вида, что в статье 5, только в конце первой строки будет
`incompatible equality constraints Integer,D,Double`: объявленный
`Integer` не сходится с `Double`, который отдаёт `averagingInt`,
а `D` между ними — тип значения внутри `groupingBy`.

---

## Часть 2. maxBy и collectingAndThen

### maxBy — наибольшее в группе

Самый крупный чек каждого гостя:

```java
Map<String, Optional<Integer>> biggestCheck = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                mapping(Order::total, maxBy(Comparator.naturalOrder()))));
IO.println(biggestCheck);
```

```
{Анна=Optional[430], Борис=Optional[660], Вера=Optional[890], Глеб=Optional[820], Дина=Optional[650], Егор=Optional[150], Жанна=Optional[200]}
```

`mapping` из части 1 превращает заказ в его сумму, а `maxBy` выбирает
из сумм группы наибольшую. Компаратор ему нужен, как `max` из статьи 3;
для чисел годится естественный порядок — `Comparator.naturalOrder()`,
тоже из статьи 3. `minBy` — то же, но наименьшее. В статье 3 ты искал
самый крупный заказ одной Веры, а здесь ответ — для каждого гостя
за один проход.

### Почему в карте Optional и почему он не пуст

В каждой ячейке карты — не число, а `Optional[…]`. Как и `max`, `maxBy`
честно говорит «может не быть»: у пустого стрима наибольшего нет.

Но внутри `groupingBy` пустых групп не бывает — вспомни статью 5:
группа заводится, только когда в неё попал первый элемент. У каждого
гостя есть хотя бы один заказ, значит, и наибольший чек есть всегда.
`Optional` здесь — лишняя обёртка: каждый, кто достанет значение
из карты, будет снимать её заново.

### collectingAndThen — доделать ответ коллектора

Бывает, что ответ коллектора — почти то, что нужно. Помнишь статью 5:
`counting()` считает в `Long`, и карту с `Integer` компилятор не принял.
Если дальше код ждёт именно `Map<String, Integer>`, ответ счёта надо
доделать — превратить `Long` в `int`. Для этого есть `collectingAndThen`:
«собери, а потом сделай с ответом вот это».

```java
Map<String, Integer> visits = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                collectingAndThen(counting(), Long::intValue)));
```

```
{Анна=2, Борис=2, Вера=2, Глеб=1, Дина=1, Егор=1, Жанна=1}
```

Аргумента два: коллектор и **завершающая функция** (finisher). Её
применяют к ответу коллектора — по разу на группу, когда группа собрана.
`counting()` отдаёт `Long`, а `Long::intValue` — ссылка на метод самого
`Long`, как `Order::guest` у заказа, — делает из него `int`. Заказов
у гостя заведомо меньше двух миллиардов, число влезет.

Та же мысль снимает и `Optional` из `maxBy`: завершающая функция получает
ответ коллектора — там это `Optional<Integer>` — и может вернуть то, что
лежит внутри. Каким методом `Optional` это сделать, ты знаешь из статьи 2,
а почему исключения здесь не будет — сказано выше. Сложить это в одну
строку попробуй сам.

---

## Часть 3. filtering и flatMapping

### filter до группировки или filtering внутри

Вопрос хозяйки: сколько крупных заказов, от 500 ₽, у каждого гостя?
Первое, что приходит в голову, — отсеять мелкие заказы и сгруппировать
оставшиеся:

```java
Map<String, Long> bigByFilter = orders.stream()
        .filter(order -> order.total() >= 500)
        .collect(groupingBy(Order::guest, TreeMap::new, counting()));
```

Второй способ — отсеивать внутри группы, коллектором `filtering`:

```java
Map<String, Long> bigByFiltering = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                filtering(order -> order.total() >= 500, counting())));
```

Ответы разные:

```
filter:    {Борис=1, Вера=1, Глеб=1, Дина=1}
filtering: {Анна=0, Борис=1, Вера=1, Глеб=1, Дина=1, Егор=0, Жанна=0}
```

Анна, Егор и Жанна в первой карте пропали. `filter` отсеял их заказы
до раскладки: к `groupingBy` они не доехали, и стопок для этих гостей
никто не завёл. `filtering` работает внутри группы: заказ сначала
попадает в стопку своего гостя и только там проверяется. Стопка
заводится в любом случае — пусть и пустая, с нулём.

Какой вариант верный, решает вопрос. «У кого были крупные заказы» —
`filter`, нули там лишние. «Отчёт по всем гостям дня» — `filtering`:
«у Анны крупных нет» — тоже ответ, и в отчёте он нужен.

🔑 `filter` до группировки решает, какие группы будут. `filtering`
решает, что окажется внутри групп, а сами группы не трогает.

💡 Теперь группа бывает пустой — и `Optional` из части 2 оживает.
С `filtering(…, maxBy(…))` у Анны вместо заказа будет `Optional.empty`:
снимать `Optional`, не глядя, здесь уже нельзя.

### flatMapping — flatMap внутри группы

Что брал каждый гость? Позиции лежат внутри заказов, их достаёт
`flatMap` из статьи 4. Но поставь его перед группировкой — и компилятор
остановит:

```java
Map<String, String> itemsByGuest = orders.stream()
        .flatMap(order -> order.items().stream())
        .collect(groupingBy(item -> item.guest(), TreeMap::new, mapping(Item::name, joining(" + "))));
```

```
Coffee.java:95: error: cannot find symbol
            .collect(groupingBy(item -> item.guest(), TreeMap::new, mapping(Item::name, joining(" + "))));
                                            ^
  symbol:   method guest()
  location: variable item of type Item
```

Та же ошибка, что в статье 1: после `flatMap` по конвейеру едут
позиции, а позиция не знает, чей это заказ, — гость остался в `Order`.
Раскладывать по гостю надо, пока едут заказы, а позиции доставать уже
внутри группы:

```java
Map<String, String> itemsByGuest = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                flatMapping(order -> order.items().stream().map(Item::name), joining(" + "))));
```

```
{Анна=латте + круассан + американо, Борис=эспрессо + капучино, Вера=капучино + латте + чизкейк, Глеб=латте + чизкейк, Дина=раф + круассан, Егор=эспрессо, Жанна=какао}
```

`flatMapping` — `flatMap` внутри группы. Функция превращает заказ
в стрим — здесь стрим названий его позиций, — а коллектор вторым
аргументом получает всё, что из этих стримов вышло: здесь `joining`
склеивает названия в строку чека. Возьмёт гость латте в двух заказах —
латте попадёт в строку дважды: `joining` ничего не убирает.

💡 Вторым аргументом у `mapping`, `filtering` и `flatMapping` может
стоять любой коллектор — те же, что и у самого `groupingBy`: в части 2
у `mapping` стоял `maxBy`.

Три новых коллектора — близнецы операций, которые ты знаешь:

| в конвейере | внутри группы | что делает |
|---|---|---|
| `map` | `mapping` | превращает каждый элемент |
| `filter` | `filtering` | оставляет подходящие (`filtering` — не убирая групп) |
| `flatMap` | `flatMapping` | превращает элемент в несколько |

---

## Часть 4. teeing: два ответа за один проход

Новый вопрос хозяйки: какую долю выручки дают крупные заказы? Нужны два
числа — вся выручка и выручка крупных — и одно действие над ними. Можно
пройти по заказам двумя конвейерами, а можно одним — через `teeing`:

```java
int bigShare = orders.stream()
        .collect(teeing(
                summingInt(Order::total),                                            // вся выручка
                filtering(order -> order.total() >= 500, summingInt(Order::total)),  // выручка крупных
                (all, big) -> big * 100 / all));                                     // доля, %
IO.println("крупные заказы дали " + bigShare + "% выручки");
```

```
крупные заказы дали 67% выручки
```

`teeing` (с Java 12) берёт два коллектора и функцию. Каждый элемент
уходит в оба коллектора. В конце функция получает оба ответа — здесь
4490 и 3020 — и делает из них один. Название — от английского tee,
тройник в трубах: поток делится на два и сходится снова.

Деление здесь целочисленное: 302 000 / 4490 — это 67,26…, и дробную
часть Java отбросила. Нужна точность — считай в `double`.

Для списка в памяти два конвейера — тоже честный ответ. `teeing`
выручает, когда второго прохода нет: внутри `groupingBy`, где каждая
группа собирается один раз, или когда данные читаются из файла и второй
раз их не прочесть.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что такое коллектор для группы? Какой из них ты знал ещё по
   статье 5?
2. Что делает `mapping` и зачем ему второй коллектор?
3. Почему для латте `counting()` дал 3, а `summingInt(Item::qty)` — 4?
   Почему `averagingInt` отвечает `Double`, даже если суммы целые?
4. Почему `maxBy` отвечает `Optional` и почему внутри `groupingBy` он
   не бывает пустым?
5. Что делает `collectingAndThen` и что получает его завершающая
   функция? Как с её помощью убрать `Optional` из карты «гость → самый
   крупный чек»?
6. Чем `filtering` внутри группы отличается от `filter` перед
   группировкой? Когда нужен каждый?
7. Почему нельзя развернуть заказы в позиции `flatMap`-ом, а потом
   сгруппировать по гостю?
8. Что делает `teeing`? Что получает его третий аргумент?

---

## Реши в кузнице

Задачи на то же самое — `filtering`, `flatMapping`, `averagingInt`,
`maxBy` внутри группы — в кузнице Stream Forge на платформе Hammerhall,
на странах мира. Задачи бесплатны, нужен только вход:

* [«Региональные саммиты»](https://hammerhall.io/forge/stream-forge/task/WldCode0038);
* [«Найти среднее население городов по каждому континенту»](https://hammerhall.io/forge/stream-forge/task/WldCode0044);
* [«Открытки туриста»](https://hammerhall.io/forge/stream-forge/task/WldCode0053).

## Что дальше

Статья 7 — стрим по `Map`: как отсортировать карту по значению, найти
три самые прибыльные позиции и не потеряться в ничьих.

## Первоисточники

* [Class Collectors — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Collectors.html) —
  `mapping`, `joining`, `summingInt`, `averagingInt`, `maxBy`,
  `collectingAndThen`, `flatMapping`, `teeing`; у `filtering` — пример,
  чем он отличается от `filter` стрима.
* [Class Optional — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Optional.html) —
  коробка, которую отдаёт `maxBy`: когда она пуста и как достают
  значение.
* [JLS 25, §7.5.4 Static-Import-on-Demand Declarations](https://docs.oracle.com/javase/specs/jls/se25/html/jls-7.html#jls-7.5.4) —
  что делает `import static … .*`.

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Записи стоят прямо вверху файла, а методы `orders()` и `main` — без
класса вокруг: в Java 25 такой файл сам становится классом, а
`void main()` без `public static` и без параметров — точкой входа.
Сохрани файл как `Coffee.java` и запусти из его папки:

```bash
java Coffee.java
```

Java сама скомпилирует файл и выполнит `main` — ни Maven, ни проекта
не нужно. Если вместо русских букв в выводе вопросы или кракозябры,
запусти с явной кодировкой — аргументы в кавычках, так их поймёт
и PowerShell: `java "-Dstdout.encoding=UTF-8" "-Dstderr.encoding=UTF-8" Coffee.java`;
в командной строке Windows перед этим выполни `chcp 65001`. Второй
аргумент — для текста исключений и ошибок: они печатаются отдельно
от обычного вывода.

```java
// Coffee.java — учебный пример статьи 6 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.TreeMap;

import static java.util.stream.Collectors.*;

/** Позиция заказа: напиток или десерт, цена за штуку в рублях, сколько штук. */
record Item(String name, int price, int qty) {}

/** Заказ: номер за день, имя гостя, позиции. */
record Order(int number, String guest, List<Item> items) {

    /** Сумма заказа в рублях. Пока циклом — стримом перепишем позже в серии. */
    int total() {
        int sum = 0;
        for (Item item : items) {
            sum += item.price() * item.qty();
        }
        return sum;
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

    // 1. Номера заказов каждого гостя строкой: mapping — map внутри группы
    Map<String, String> numbersByGuest = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    mapping(order -> "№" + order.number(), joining(" "))));
    IO.println(numbersByGuest);

    // 2. Сколько потратил каждый гость: summingInt складывает
    Map<String, Integer> spentByGuest = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new, summingInt(Order::total)));
    IO.println(spentByGuest);

    // 3. Сколько штук каждой позиции продано: складываем qty
    Map<String, Integer> portionsByItem = orders.stream()
            .flatMap(order -> order.items().stream())
            .collect(groupingBy(Item::name, TreeMap::new, summingInt(Item::qty)));
    IO.println(portionsByItem);

    // 4. Средний чек гостя: averagingInt отвечает в Double
    Map<String, Double> averageByGuest = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new, averagingInt(Order::total)));
    IO.println(averageByGuest);

    // 5. Самый крупный чек гостя: maxBy отвечает в Optional
    Map<String, Optional<Integer>> biggestCheck = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    mapping(Order::total, maxBy(Comparator.naturalOrder()))));
    IO.println(biggestCheck);

    // 6. collectingAndThen: доделать ответ коллектора — счёт из Long в Integer
    Map<String, Integer> visits = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    collectingAndThen(counting(), Long::intValue)));
    IO.println(visits);

    // 7. filter до группировки: гости без крупных заказов пропадают
    Map<String, Long> bigByFilter = orders.stream()
            .filter(order -> order.total() >= 500)
            .collect(groupingBy(Order::guest, TreeMap::new, counting()));
    IO.println("filter:    " + bigByFilter);

    // 8. filtering внутри группы: гости остаются, у кого-то — 0
    Map<String, Long> bigByFiltering = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    filtering(order -> order.total() >= 500, counting())));
    IO.println("filtering: " + bigByFiltering);

    // 9. Что брал каждый гость: flatMapping — flatMap внутри группы
    Map<String, String> itemsByGuest = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    flatMapping(order -> order.items().stream().map(Item::name), joining(" + "))));
    IO.println(itemsByGuest);

    // 10. teeing: два коллектора за один проход — доля крупных заказов в выручке
    int bigShare = orders.stream()
            .collect(teeing(
                    summingInt(Order::total),
                    filtering(order -> order.total() >= 500, summingInt(Order::total)),
                    (all, big) -> big * 100 / all));
    IO.println("крупные заказы дали " + bigShare + "% выручки");
}
```

Сделай руками:

1. Запусти файл. Первая строка — `{Анна=№1 №5, Борис=№2 №9, …}`;
   найди в третьей строке `латте=4`.
2. В блоке `// 5.` замени `maxBy` на `minBy` — выйдут самые маленькие
   чеки: `{Анна=Optional[170], Борис=Optional[300], …}`. Верни как было.
3. В блоке `// 6.` замени `collectingAndThen(counting(), Long::intValue)`
   на `counting()` — компилятор напомнит статью 5: в конце первой строки
   ошибки будет `Integer,D,Long`. Верни как было.
4. Замени блок `// 9.` куском из части 3, где `flatMap` стоит перед
   группировкой, — увидишь `location: variable item of type Item`.
   Верни как было.
5. В блоке `// 8.` замени `counting()` на
   `maxBy(Comparator.comparingInt(Order::total))`, а `Map<String, Long>` —
   на `Map<String, Optional<Order>>`: у Анны, Егора и Жанны будет
   `Optional.empty`. Верни как было.
6. В блоке `// 10.` поменяй порог 500 на 300 — выйдет
   `крупные заказы дали 83% выручки`.
