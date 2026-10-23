# `groupingBy` и `toMap`: раскладываем по группам

> «Стримы по шагам» · статья 5 · читать минут 20
>
> **Для кого.** Ты прочитал первые четыре статьи серии: конвейер,
> лямбды и `Order::guest`, `Optional`, сортировку и `flatMap`. До сих
> пор ответ конвейера был числом, одним элементом или списком.
>
> **Что будет.** Что такое коллектор и что делает `collect`; как
> разложить заказы по гостям и посчитать их; почему ключи в ответе
> идут вразнобой и как их упорядочить; как `toMap` падает на повторе
> ключа и как это починить; `partitioningBy` — ровно две группы.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем группировать

Конец дня в кофейне «Наковальня». Хозяйка просит разложить заказы
по гостям: кто сколько раз заходил и что брал. Заказы — те же десять,
что во всех статьях серии; список — в «Примере целиком».

Циклом это делают так:

```java
Map<String, List<Order>> byGuestLoop = new HashMap<>();   // пустая карта под ответ
for (Order order : orders) {
    String guest = order.guest();
    if (!byGuestLoop.containsKey(guest)) {                // гость встретился впервые —
        byGuestLoop.put(guest, new ArrayList<>());        // заводим ему пустой список
    }
    byGuestLoop.get(guest).add(order);                    // кладём заказ в список гостя
}
```

**Карта** (`Map`) хранит пары «ключ — значение»: здесь ключ — имя
гостя, значение — список его заказов. `put` кладёт пару, `get`
достаёт значение по ключу, `containsKey` спрашивает, есть ли такой
ключ. Тип пишут с двумя параметрами: `Map<String, List<Order>>` —
«строка → список заказов».

Из восьми строк о самом вопросе — одна: «по гостю». Остальное —
служебное: пустая карта, проверка «новый ли гость», пустой список для
новичка. Забудешь проверку — `get` для нового гостя вернёт `null`,
и `add` упадёт с `NullPointerException`.

Стримом:

```java
Map<String, List<Order>> byGuest = orders.stream()
        .collect(Collectors.groupingBy(Order::guest));     // разложить заказы по гостям
```

Карта та же: `byGuest.equals(byGuestLoop)` — `true`. Читается
как фраза: «заказы — собрать, сгруппировав по гостю».

🔑 Цикл раскладывает заказы по стопкам руками. Стрим только называет,
по какому признаку раскладывать, — стопки заводит Java.

В этой статье — как устроен `collect`, как считать по группам, как
строить карту через `toMap` и на чём здесь спотыкаются в первую
неделю.

---

## Часть 1. collect и первый коллектор

### Коллектор — рецепт ответа

До сих пор конвейер заканчивался `count()`, `toList()`, `findFirst()`
или `max()`: ответ — число, список или один элемент. Для ответа другой
формы, например карты, есть общая конечная операция `collect`. Ей
передают **коллектор** — рецепт, как собрать
ответ из того, что доехало до конца конвейера: какую посуду взять
(пустой список, пустую карту), что делать с каждым элементом и что
подать в конце.

Ты его уже видел: `collect(Collectors.toList())` из статьи 1 — рецепт
«сложить в список», `Collectors.toSet()` из статьи 4 — «сложить
в множество». Готовые рецепты лежат в классе `Collectors` (с `s`
на конце). Сегодня из него — `groupingBy`, `counting`, `toMap`
и `partitioningBy`.

### groupingBy — разложить по ключу

```java
Map<String, List<Order>> byGuest = orders.stream()
        .collect(Collectors.groupingBy(Order::guest));
```

`groupingBy` получает **классификатор** — функцию, которая для каждого
элемента называет его группу. Здесь это `Order::guest`: для заказа —
имя гостя. Заказы с одинаковым именем попадают в одну группу.

Ответ — карта. Ключ — то, что вернул классификатор, значение — список
элементов группы. Отсюда и тип: `Map<String, List<Order>>`. Достанем
заказы Бориса:

```java
IO.println(byGuest.get("Борис"));
```

```
[Order[number=2, guest=Борис, items=[Item[name=эспрессо, price=150, qty=2]]], Order[number=9, guest=Борис, items=[Item[name=капучино, price=220, qty=3]]]]
```

Два заказа, 2 и 9, — в том порядке, в каком они шли в списке. Запись
печатает себя сама, со всеми полями: длинно, зато видно всё.

Классификатор не обязан быть полем — подойдёт любая функция
от элемента. Например, `order -> order.total() >= 500`: ключами
станут `true` и `false`. К этому вернёмся в части 4.

---

## Часть 2. Считаем по группам

### counting — сколько в каждой группе

Хозяйке не нужны сами заказы — только сколько их у каждого гостя.
У `groupingBy` есть второй аргумент: что сделать с группой вместо
того, чтобы сложить её в список.

```java
Map<String, Long> ordersPerGuest = orders.stream()
        .collect(Collectors.groupingBy(Order::guest, Collectors.counting()));
```

```
{Борис=2, Анна=2, Вера=2, Егор=1, Жанна=1, Дина=1, Глеб=1}
```

Карта печатается в фигурных скобках, пара — через `=`: у Бориса два
заказа. `Collectors.counting()` — тоже коллектор, рецепт «посчитать».
Здесь он работает внутри каждой группы: коллектор внутри коллектора.
Таких рецептов для группы много — сумма, среднее, самый крупный, —
о них статья 6.

### Почему Long

Значения в карте — `Long`. Почему не привычный `Integer`? Причин две.
Счёт, как у `count()` из статьи 1, — `long`: элементов может быть
больше, чем помещается в `int`. А карта хранит объекты, не простые
числа, поэтому `long` лежит в ней упакованным в объект `Long` — как
`int` в `Integer`; упаковку ты видел в статье 3. Упаковывает
и распаковывает Java сама.

⚠️ Напишешь по привычке `Map<String, Integer>` — компилятор
не согласится:

```
Coffee.java:63: error: incompatible types: inference variable D has incompatible equality constraints Integer,Long
            .collect(Collectors.groupingBy(Order::guest, Collectors.counting()));
                    ^
…
1 error
error: compilation failed
```

Длинно, но смысл — в конце первой строки. `D` — так внутри
`groupingBy` назван тип значения карты, и он должен оказаться сразу
`Integer` (так ты объявил) и `Long` (так считает `counting()`). Так
не бывает — пиши `Long`.

### Порядок ключей не гарантирован

Посмотри на вывод ещё раз: Борис, Анна, Вера, Егор… Не по алфавиту
и не по порядку заказов, хотя первой в кофейню пришла Анна. История
та же, что с `HashSet` в статье 4. Сейчас, на JDK 25, `groupingBy`
собирает ответ в `HashMap`.
Она раскладывает ключи по ячейкам, номер ячейки вычисляет из самого
ключа и обходит карту по ячейкам.

Документация говорит прямо: `HashMap` не гарантирует порядок
и не обещает, что он не изменится со временем. А `groupingBy`
не обещает даже, что вернёт именно `HashMap`. Появится новый гость —
имена могут перетасоваться. Отчёт хозяйке, сравнение в тесте, вывод
в этой статье не должны зависеть от случая.

Нужен порядок — скажи, какую карту создать. У `groupingBy` есть
вариант с тремя аргументами: классификатор, **фабрика карты** — чем
создать пустую карту под ответ — и коллектор для группы:

```java
Map<String, Long> ordersPerGuestSorted = orders.stream()
        .collect(Collectors.groupingBy(Order::guest, TreeMap::new, Collectors.counting()));
```

```
{Анна=2, Борис=2, Вера=2, Глеб=1, Дина=1, Егор=1, Жанна=1}
```

`TreeMap` держит ключи отсортированными в естественном порядке, как
`sorted()` из статьи 3: числа — по возрастанию, строки — по кодам
символов. Для наших имён это алфавит, но «ё», помнишь, встанет не на
своё место. `TreeMap::new` — ссылка на конструктор: «создай
новую `TreeMap`». Та же запись, что `Order::guest`, только вместо
метода — `new`.

Дальше в серии карты для печати — `TreeMap`, а где карта нарочно
`HashMap`, об этом будет сказано. Так вывод в статье совпадёт с твоим
символ в символ.

💡 Нужен порядок первого появления — `LinkedHashMap::new`: ключи
встанут так, как впервые встретились в заказах.

### Списки в TreeMap — Collectors.toList()

⚠️ Варианта «классификатор и фабрика» без коллектора нет.
`groupingBy(Order::guest, TreeMap::new)` не скомпилируется — ответ
начнётся со строки `no suitable method found for
groupingBy(Order::guest,TreeMap::new)`. Нужны списки в `TreeMap` —
третьим аргументом пиши `Collectors.toList()`:

```java
Map<String, List<Order>> byGuestSorted = orders.stream()
        .collect(Collectors.groupingBy(Order::guest, TreeMap::new, Collectors.toList()));
```

Статья 1 советовала `toList()` вместо `collect(Collectors.toList())`.
Совет — про конец конвейера. Здесь нужен не конец конвейера, а рецепт
для группы, коллектор. `toList()` — метод стрима, коллектором он
не бывает, и в `groupingBy` его не передать.

### Группы по позициям

Второй вопрос хозяйки: сколько раз за день пробивали каждую позицию?
Позиции лежат внутри заказов — их достаёт `flatMap` из статьи 4,
а дальше та же группировка, по названию:

```java
Map<String, Long> linesPerItem = orders.stream()
        .flatMap(order -> order.items().stream())          // все позиции всех заказов подряд
        .collect(Collectors.groupingBy(Item::name, TreeMap::new, Collectors.counting()));
```

```
{американо=1, какао=1, капучино=2, круассан=2, латте=3, раф=1, чизкейк=2, эспрессо=2}
```

После `flatMap` по конвейеру едут позиции, `Item`, поэтому
и классификатор теперь `Item::name`.

⚠️ Латте — 3. А чашек латте продано четыре: Глеб взял две в одной
позиции, `new Item("латте", 250, 2)`. `counting()` считает элементы
группы — строки чека, а не штуки. Чтобы сложить `qty`, нужен другой
коллектор для группы — сумма; он в статье 6.

🔑 `counting()` отвечает, сколько элементов в группе. Прежде чем
считать, назови, что едет по конвейеру: заказы, позиции или чашки.

---

## Часть 3. toMap: одно значение на ключ

### Карта без групп

Не всякая карта — группы. На кассе гость называет номер заказа,
кассиру нужна сумма. У номера одна сумма — список не нужен. Для такой
карты есть `Collectors.toMap`: две функции, одна даёт ключ, другая —
значение.

```java
Map<Integer, Integer> totalByNumber = orders.stream()
        .collect(Collectors.toMap(Order::number, Order::total));   // номер → сумма
IO.println("заказ 8: " + totalByNumber.get(8) + " ₽");
```

```
заказ 8: 890 ₽
```

### Повтор ключа — исключение

Теперь та же карта, но по гостю: сколько потратил каждый.

```java
Map<String, Integer> boom = orders.stream()
        .collect(Collectors.toMap(Order::guest, Order::total));
```

Компилируется. А при запуске:

```
Exception in thread "main" java.lang.IllegalStateException: Duplicate key Анна (attempted merging values 430 and 170)
```

«Повтор ключа Анна (попытка слить значения 430 и 170)». Анна заходила
дважды: заказ 1 на 430 ₽ и заказ 5 на 170 ₽. `toMap` ждёт одно
значение на ключ и, встретив второе, не знает, что с ним делать:
оставить первое, последнее, сложить? Молча выбирать он не станет —
бросает исключение. Борис и Вера тоже заходили дважды, просто до них
дело не дошло.

⚠️ Коварно то, что на данных без повторов всё работает. Падает
потом — на первом постоянном госте.

### Функция слияния

Что делать с повтором, говорят третьим аргументом — **функцией
слияния**. Она получает два значения одного ключа — то, что уже
в карте, и новое — и возвращает одно:

```java
Map<String, Integer> spentByGuest = orders.stream()
        .collect(Collectors.toMap(Order::guest, Order::total, (a, b) -> a + b));
IO.println("Анна потратила " + spentByGuest.get("Анна") + " ₽");
```

```
Анна потратила 600 ₽
```

`(a, b) -> a + b` — лямбда с двумя параметрами в скобках, как
компаратор из статьи 3. Для Анны `a` — 430, `b` — 170, в карту ляжет
600. Нужен только первый
заказ — `(a, b) -> a`, только последний — `(a, b) -> b`.

Сложить два числа умеет готовый метод `Integer.sum(a, b)`, поэтому
вместо лямбды часто пишут ссылку на него — `Integer::sum`. Это вторая
форма ссылки из статьи 2, как `IO::println`, только аргумента два: то же,
что `(a, b) -> Integer.sum(a, b)`. А четвёртым аргументом, как
у `groupingBy`, задают карту:

```java
Map<String, Integer> spentSorted = orders.stream()
        .collect(Collectors.toMap(Order::guest, Order::total, Integer::sum, TreeMap::new));
```

```
{Анна=600, Борис=960, Вера=1110, Глеб=820, Дина=650, Егор=150, Жанна=200}
```

Варианта «ключ, значение, карта» без функции слияния нет: нужна
`TreeMap` — пиши и слияние.

### toMap или groupingBy

* `groupingBy` — когда на ключ приходится много элементов и нужна
  группа: список или что-то, посчитанное по ней.
* `toMap` — когда на ключ одно значение. Повторов быть не может —
  хватит двух аргументов, и исключение, если повтор всё же случится,
  честно скажет, что данные не те. Повторы возможны — сразу пиши
  функцию слияния.

---

## Часть 4. partitioningBy: две группы

### Да или нет

Иногда групп ровно две: крупные заказы и остальные. Для этого есть
`partitioningBy`. Он берёт условие, как `filter`, но ничего
не отсеивает, а раскладывает: `true` — в одну группу, `false` —
в другую.

```java
Map<Boolean, List<Order>> bigAndSmall = orders.stream()
        .collect(Collectors.partitioningBy(order -> order.total() >= 500));
IO.println(bigAndSmall.get(true).size() + " крупных, "
        + bigAndSmall.get(false).size() + " остальных");
```

```
4 крупных, 6 остальных
```

Вторым аргументом, как у `groupingBy`, можно передать коллектор для
группы — например, `counting()`.

### Обе группы есть всегда

Тот же ответ дал бы `groupingBy(order -> order.total() >= 500)` —
ключ и там `true` или `false`. Разница видна, когда одна группа
пустая. Поднимем порог до 1000 ₽ — таких заказов нет:

```java
Map<Boolean, Long> parts = orders.stream()
        .collect(Collectors.partitioningBy(order -> order.total() >= 1000, Collectors.counting()));
Map<Boolean, Long> groups = orders.stream()
        .collect(Collectors.groupingBy(order -> order.total() >= 1000, Collectors.counting()));
```

```
partitioningBy: {false=10, true=0}
groupingBy:     {false=10}
```

`groupingBy` заводит группу, только когда в неё попал первый элемент.
Нет крупных заказов — нет и ключа `true`, и `groups.get(true)` вернёт
`null`. `partitioningBy` по документации отдаёт обе группы всегда,
и `parts.get(true)` безопасен.

🔑 Ровно два исхода — `partitioningBy`. Больше двух или заранее
неизвестно сколько — `groupingBy`.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что такое коллектор? Чем `collect(…)` отличается от `toList()`
   в конце конвейера?
2. Что такое классификатор? Откуда берутся `String` и `List<Order>`
   в типе `Map<String, List<Order>>`?
3. Почему `counting()` даёт `Long`, а не `Integer`? Что ответит
   компилятор, если объявить карту как `Map<String, Integer>`?
4. Ты напечатал карту, а гости идут не по алфавиту и не по порядку
   заказов. Почему так, и как получить алфавит?
5. Почему внутри `groupingBy` пишут `Collectors.toList()`, хотя в конце
   конвейера статья 1 советует `toList()`?
6. Латте пробили трижды, а чашек продано четыре. Что именно считает
   `counting()`?
7. Когда `toMap` бросает `IllegalStateException`? Что получится, если
   функция слияния — `(a, b) -> b`?
8. Чем `partitioningBy` отличается от `groupingBy` с тем же условием?

---

## Реши в кузнице

Задачи на то же самое — `groupingBy`, `counting`, `toMap`, `TreeMap` —
в кузнице Stream Forge на платформе Hammerhall, на фильмах и странах
мира. Задачи бесплатны, нужен только вход:

* [«Ящики прокатной конторы»](https://hammerhall.io/forge/stream-forge/task/MovCode0016);
* [«Анфилада залов»](https://hammerhall.io/forge/stream-forge/task/MovCode0021);
* [«Летопись студии»](https://hammerhall.io/forge/stream-forge/task/MovCode0023);
* [«Багажные бирки»](https://hammerhall.io/forge/stream-forge/task/WldCode0008).

## Что дальше

Статья 6 — коллекторы внутри группы: вместо списка заказов — номера,
сумма, средний чек, самый крупный заказ; чем `filtering` отличается
от `filter`; `teeing` — два ответа за один проход. Там же латте
наконец посчитаем в чашках.

## Первоисточники

* [Class Collectors — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Collectors.html) —
  `groupingBy`, `counting`, `toMap`, `partitioningBy`; у `toMap` —
  про повтор ключа, у `partitioningBy` — что обе группы есть всегда.
* [Interface Collector — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Collector.html) —
  из чего состоит рецепт: создать контейнер, добавить элемент, слить
  два контейнера, отдать ответ.
* [Class HashMap — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/HashMap.html) —
  первый абзац: порядок не гарантирован и может меняться.
* [Class TreeMap — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/TreeMap.html) —
  карта, отсортированная по ключам.

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
// Coffee.java — учебный пример статьи 5 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.Collectors;

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

    // 1. Заказы по гостям — циклом: для нового гостя заводим пустой список
    Map<String, List<Order>> byGuestLoop = new HashMap<>();
    for (Order order : orders) {
        String guest = order.guest();
        if (!byGuestLoop.containsKey(guest)) {
            byGuestLoop.put(guest, new ArrayList<>());
        }
        byGuestLoop.get(guest).add(order);
    }

    // 2. То же — стримом: groupingBy раскладывает заказы по ключу
    Map<String, List<Order>> byGuest = orders.stream()
            .collect(Collectors.groupingBy(Order::guest));
    IO.println("циклом и стримом одно и то же: " + byGuest.equals(byGuestLoop));
    IO.println(byGuest.get("Борис"));

    // 3. Сколько заказов у каждого гостя: counting() считает в Long
    Map<String, Long> ordersPerGuest = orders.stream()
            .collect(Collectors.groupingBy(Order::guest, Collectors.counting()));
    IO.println(ordersPerGuest);

    // 4. Ключи по алфавиту: карту для ответа создаёт TreeMap::new
    Map<String, Long> ordersPerGuestSorted = orders.stream()
            .collect(Collectors.groupingBy(Order::guest, TreeMap::new, Collectors.counting()));
    IO.println(ordersPerGuestSorted);

    // 5. Позиции всех заказов: сколько раз пробили каждую
    Map<String, Long> linesPerItem = orders.stream()
            .flatMap(order -> order.items().stream())
            .collect(Collectors.groupingBy(Item::name, TreeMap::new, Collectors.counting()));
    IO.println(linesPerItem);

    // 6. toMap: номер заказа → сумма; номера не повторяются
    Map<Integer, Integer> totalByNumber = orders.stream()
            .collect(Collectors.toMap(Order::number, Order::total));
    IO.println("заказ 8: " + totalByNumber.get(8) + " ₽");

    // 7. toMap по гостю: повтор ключа складывает функция слияния
    Map<String, Integer> spentByGuest = orders.stream()
            .collect(Collectors.toMap(Order::guest, Order::total, (a, b) -> a + b));
    IO.println("Анна потратила " + spentByGuest.get("Анна") + " ₽");

    // 8. То же с Integer::sum и картой TreeMap
    Map<String, Integer> spentSorted = orders.stream()
            .collect(Collectors.toMap(Order::guest, Order::total, Integer::sum, TreeMap::new));
    IO.println(spentSorted);

    // 9. partitioningBy: ровно две группы — true и false
    Map<Boolean, List<Order>> bigAndSmall = orders.stream()
            .collect(Collectors.partitioningBy(order -> order.total() >= 500));
    IO.println(bigAndSmall.get(true).size() + " крупных, "
            + bigAndSmall.get(false).size() + " остальных");

    // 10. Порог 1000: partitioningBy оставит пустую группу, groupingBy — нет
    Map<Boolean, Long> parts = orders.stream()
            .collect(Collectors.partitioningBy(order -> order.total() >= 1000, Collectors.counting()));
    Map<Boolean, Long> groups = orders.stream()
            .collect(Collectors.groupingBy(order -> order.total() >= 1000, Collectors.counting()));
    IO.println("partitioningBy: " + parts);
    IO.println("groupingBy:     " + groups);

    // Сделай руками — раскомментируй две строки и запусти:
    // Map<String, Integer> boom = orders.stream()
    //         .collect(Collectors.toMap(Order::guest, Order::total));   // IllegalStateException
}
```

Сделай руками:

1. Запусти файл. Первая строка — `циклом и стримом одно и то же: true`.
   Найди в выводе две карты «гость → число заказов»: в первой гости
   идут вразнобой, во второй — по алфавиту.
2. Раскомментируй две строки с `boom` в конце `main` — после всего
   вывода упадёт `IllegalStateException: Duplicate key Анна
   (attempted merging values 430 and 170)`. Верни комментарии.
3. В блоке `// 3.` замени `Map<String, Long>` на `Map<String, Integer>`
   и прочитай ошибку компилятора: `Integer,Long` в конце первой строки.
   Верни как было.
4. В блоке `// 7.` замени `(a, b) -> a + b` на `(a, b) -> b` — выйдет
   `Анна потратила 170 ₽`: в карте остался только последний заказ.
   Верни как было.
5. В блоке `// 5.` замени `TreeMap::new` на `LinkedHashMap::new`
   (импорт не нужен: компактный файл сам видит все публичные классы
   модуля `java.base`, а `LinkedHashMap` — из него) — позиции встанут
   в порядке первого появления: `{латте=3, круассан=2, эспрессо=2, …}`.
   Верни как было.
6. В блоке `// 4.` убери `, Collectors.counting()` — компилятор ответит
   `no suitable method found for groupingBy(Order::guest,TreeMap::new)`.
   Верни как было.
