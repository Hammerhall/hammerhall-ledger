# `flatMap`: списки внутри объектов

> «Стримы по шагам» · статья 4 · читать минут 15
>
> **Для кого.** Ты прочитал статьи [1](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop),
> [2](https://hammerhall.io/ledger/streams/2-filter-map-optional) и [3](https://hammerhall.io/ledger/streams/3-sorting):
> знаешь, как устроен конвейер, читаешь лямбды и ссылки на методы,
> умеешь достать ответ из `Optional` и сортировать компаратором.
>
> **Что будет.** Как собрать в один стрим позиции из всех заказов —
> `flatMap`; как убрать повторы — `distinct` и множество `Set`; почему
> две позиции «латте» бывают одинаковыми, а бывают нет — и при чём тут
> `equals` у записи.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем flatMap

До сих пор вопросы были про заказы: сумма, гость, номер. Теперь
хозяйка «Наковальни» спрашивает про то, что внутри: сколько раз сегодня
пробили латте? Что вообще продавали?

Позиции лежат в заказах списками: у заказа 1 — латте и круассан,
у заказа 2 — эспрессо. Циклом это цикл в цикле:

```java
int latteByLoop = 0;
for (Order order : orders) {
    for (Item item : order.items()) {               // цикл в цикле — по позициям заказа
        if (item.name().equals("латте")) {
            latteByLoop++;
        }
    }
}
IO.println("циклом: " + latteByLoop);
```

```
циклом: 3
```

Латте пробивали трижды: в заказах 1, 4 и 8. Попробуем стримом, как
в статье 1: `map` от заказа к его позициям, потом фильтр:

```java
long latte = orders.stream()
        .map(order -> order.items())
        .filter(item -> item.name().equals("латте"))
        .count();
```

```
Coffee.java:69: error: cannot find symbol
            .filter(item -> item.name().equals("латте"))
                                ^
  symbol:   method name()
  location: variable item of type List<Item>
1 error
error: compilation failed
```

Помнишь главную мысль статьи 1: держи в голове, что едет по
конвейеру. Строка `location:` подсказывает: `item` здесь не позиция,
а `List<Item>` — весь список позиций заказа. `map` превращает один
заказ в одну вещь, здесь — в список. Сколько заказов вошло, столько
списков и вышло:

```java
List<List<Item>> lists = orders.stream()
        .map(order -> order.items())
        .toList();
IO.println(lists.size() + " " + lists.get(0));
```

```
10 [Item[name=латте, price=250, qty=1], Item[name=круассан, price=180, qty=1]]
```

Десять списков, по одному на заказ; первый — позиции заказа 1.
`List<List<Item>>` читается «список списков позиций». Нужна другая
операция — та, что разложит списки в одну ленту.

🔑 `map` — один элемент на входе, один на выходе. `flatMap` — один
на входе, сколько угодно на выходе, и все они едут дальше по одной
ленте.

---

## Часть 1. flatMap — списки в одну ленту

### Как это работает

Сколько всего позиций пробили за день?

```java
long itemCount = orders.stream()
        .flatMap(order -> order.items().stream())
        .count();
IO.println(itemCount);
```

```
14
```

`flatMap` (от англ. flat — «плоский»): для каждого заказа лямбда отдаёт
стрим его позиций, а `flatMap` выкладывает их все на одну ленту. Как
на кассе: покупатели приходят с пакетами, а на ленту ложатся сами
покупки — из всех пакетов подряд. В десяти заказах 14 позиций, и дальше
по конвейеру едут уже они: был `Stream<Order>`, стал `Stream<Item>`.
Порядок сохраняется: сначала позиции заказа 1, потом заказа 2 и так
далее — это будет видно в части 2.

Теперь фильтр по позиции работает:

```java
long latte = orders.stream()
        .flatMap(order -> order.items().stream())
        .filter(item -> item.name().equals("латте"))
        .count();
IO.println("стримом: " + latte);
```

```
стримом: 3
```

Три строки с латте — как у цикла.

💡 Чашек латте, правда, четыре: Глеб взял две. Сложить количества
`qty` — задача для стрима чисел, о нём статья 8.

### Лямбда во flatMap отдаёт стрим, а не список

Частая ошибка — забыть `.stream()`:

```java
        .flatMap(order -> order.items())
```

```
Coffee.java:62: error: incompatible types: cannot infer type-variable(s) R
            .flatMap(order -> order.items())
                    ^
    (argument mismatch; bad return type in lambda expression
      List<Item> cannot be converted to Stream<? extends R>)
…
```

Главное — в строке `List<Item> cannot be converted…`: «`List<Item>`
не превратить в `Stream`». `flatMap` ждёт от лямбды стрим, а стрим у списка даёт
`stream()`. `R` и `? extends` — обозначения из описания метода, их пока
можно пропустить.

В интернете ты увидишь ту же операцию в два шага, ссылками на методы:
`.map(Order::items).flatMap(List::stream)`. Сначала заказ превращают
в список, потом список — в стрим его элементов. Ответ тот же, выбирай,
что легче читать.

### Ноль, один или несколько

Стрим, который отдаёт лямбда, может быть любой длины — в том числе
из одного элемента или пустой. Для этого есть `Stream.of(…)` — стрим
из перечисленного — и `Stream.empty()` — пустой стрим:

```java
List<String> bigGuests = orders.stream()
        .flatMap(order -> order.total() >= 500
                ? Stream.of(order.guest())
                : Stream.empty())
        .toList();
IO.println(bigGuests);
```

```
[Глеб, Дина, Вера, Борис]
```

`условие ? a : b` — короткий `if`, который отдаёт значение: условие
верно — `a`, иначе `b`. Крупный заказ даёт одного гостя, остальные —
ничего. Ответ знакомый: тот же, что в статье 1 дали `filter` и `map`.

Здесь так писать не нужно — `filter` и `map` читаются проще. Приём
пригодится, когда «ноль, один или несколько» решает одна функция
и решение не разделить на «отобрать» и «превратить».

💡 С Java 16 у стрима есть и `mapMulti` — родственник `flatMap` для того
же случая. Он обходится без маленьких стримов на каждый элемент.
Встретишь — знай, что это он.

---

## Часть 2. Без повторов: distinct и множество

### Что продавали

Названия всех позиций дня — `flatMap`, потом `map`:

```java
List<String> names = orders.stream()
        .flatMap(order -> order.items().stream())
        .map(Item::name)
        .toList();
IO.println(names);
```

```
[латте, круассан, эспрессо, капучино, латте, чизкейк, американо, раф, круассан, эспрессо, латте, чизкейк, капучино, какао]
```

Виден порядок: латте и круассан из заказа 1, эспрессо из заказа 2
и дальше по списку. И видны повторы: латте трижды, а эспрессо,
круассан, чизкейк и капучино — по два раза.

### distinct — убрать повторы

```java
List<String> distinctNames = orders.stream()
        .flatMap(order -> order.items().stream())
        .map(Item::name)
        .distinct()
        .toList();
IO.println(distinctNames);
```

```
[латте, круассан, эспрессо, капучино, чизкейк, американо, раф, какао]
```

`distinct()` — промежуточная операция: пропускает элемент, только если
такого ещё не было. Из повторов остаётся первый, и порядок первого
появления сохраняется. Документация обещает это для стримов с порядком
обхода; у стрима из списка он есть — порядок элементов в списке. Так же
было с устойчивостью `sorted` в статье 3. Названий восемь.

### Множество — Set

Бывает, что нужен не список, а **множество** — коллекция без повторов.
В Java это `Set`: добавить то, что уже есть, можно, но второй копии
не появится: `add` вернёт `false`. А проверить, есть ли элемент, —
быстро: метод `contains`.

Собрать стрим в множество — `collect(Collectors.toSet())`:

```java
Set<String> soldSet = orders.stream()
        .flatMap(order -> order.items().stream())
        .map(Item::name)
        .collect(Collectors.toSet());
IO.println(soldSet);
IO.println(soldSet.contains("раф") + " " + soldSet.contains("матча"));
```

```
[американо, раф, латте, какао, чизкейк, круассан, эспрессо, капучино]
true false
```

**`collect`** — конечная операция «собери по рецепту», а
`Collectors.toSet()` — рецепт «в множество». Помнишь
`collect(Collectors.toList())` из статьи 1 — тот же приём.
По-настоящему `collect` раскроется в статье 5, на группировках.

⚠️ Посмотри на порядок: ни алфавита, ни порядка продаж. Множество из
`toSet()` сейчас — `HashSet`, а он порядок не обещает: раскладывает
элементы по своим правилам, и в другой версии Java порядок может стать
другим. Документация `toSet()` не обещает даже, что это будет `HashSet`.
Нужен порядок первого появления — `distinct().toList()`.

---

## Часть 3. Что значит «одинаковые»: equals и hashCode у записи

### Две позиции «латте»

Уберём повторы не из названий, а из самих позиций:

```java
long distinctItems = orders.stream()
        .flatMap(order -> order.items().stream())
        .distinct()
        .count();
IO.println(distinctItems + " разных позиций, " + distinctNames.size() + " разных названий");
```

```
13 разных позиций, 8 разных названий
```

Позиций 14, разных — 13, а разных названий — 8. Почему не 8 и не 14?

`distinct` и `Set` решают, одинаковы ли два элемента, методом `equals`.
У записи `equals` Java пишет сама — помнишь из статьи 1, сравнение
запись получает вместе с конструктором и печатью. И сравнивает он
**все поля**:

```java
Item a = new Item("латте", 250, 1);
Item b = new Item("латте", 250, 1);
Item c = new Item("латте", 250, 2);
IO.println(a.equals(b) + " " + (a == b) + " " + a.equals(c));
```

```
true false false
```

* `a.equals(b)` — `true`: название, цена и количество совпали. Это два
  разных объекта — `a == b` даёт `false`, — но для `equals` они
  одинаковые.
* `a.equals(c)` — `false`: отличается только количество, но и этого
  хватает.

Теперь посмотри на заказы. Анна (заказ 1) и Вера (заказ 8) взяли
по одному латте за 250 ₽ — `Item("латте", 250, 1)` дважды. Это повтор,
и `distinct` его убрал: 14 − 1 = 13. А Глеб взял два латте —
`Item("латте", 250, 2)`, для `equals` это другая позиция. Так же
с круассаном, эспрессо, капучино и чизкейком: в разных заказах разное
количество.

🔑 Прежде чем убирать повторы, реши, что значит «одинаковые».
`distinct` сравнивает элементы целиком. Нужно «одинаковые
по названию» — сначала `map` к названию, потом `distinct`.

### hashCode — номерок к equals

```java
IO.println(a.hashCode() == b.hashCode());
```

```
true
```

`hashCode()` — число, которое объект считает из своих полей. `HashSet`
сначала по нему находит место, где искать, и только там сравнивает
`equals`. Как в гардеробе: номерок ведёт к крючку, а на крючке уже
ищут свою куртку. Отсюда правило Java: объекты, равные по `equals`,
обязаны давать одинаковый `hashCode`. Запись соблюдает его сама — оба
метода у неё считаются по всем полям.

### ⚠️ Обычный класс — другое дело

У обычного класса без своего `equals` этот метод достаётся от `Object`
и отвечает «равны, только если это один и тот же объект». Два объекта
«латте», созданные через `new`, для него разные, и `distinct` не уберёт
ни одного. В интернете ты увидишь классы с `equals` и `hashCode`,
написанными руками или сгенерированными средой разработки, — вот ради
чего. Запись делает это за тебя.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему `map(order -> order.items())` и следом
   `filter(item -> item.name()…)` не компилируется? Что подсказывает
   строка `location:`?
2. Чем `flatMap` отличается от `map`? Сколько элементов выходит
   из каждого на один входящий?
3. Почему `flatMap(order -> order.items())` не компилируется и как это
   исправить?
4. Как через `flatMap` получить из заказа ноль или один элемент? Почему
   в этом случае обычно лучше `filter` и `map`?
5. Чем `distinct().toList()` отличается от `collect(Collectors.toSet())`:
   по порядку и по тому, что удобно делать с ответом?
6. Почему `new Item("латте", 250, 1).equals(new Item("латте", 250, 1))` —
   `true`, а `==` для них — `false`?
7. Почему `distinct` по позициям дал 13, а по названиям — 8?
8. Зачем объекту `hashCode`, если есть `equals`? Что будет с `distinct`
   у обычного класса без своего `equals`?

---

## Реши в кузнице

Задачи на то же самое — `flatMap`, `distinct`, множество — в кузнице
Stream Forge на платформе Hammerhall, на фильмах и странах мира. Первые
задачи бесплатны, нужен только вход:

* [«Справочник почтальона»](https://hammerhall.io/forge/stream-forge/task/WldCode0005);
* [«Свиток дипломата»](https://hammerhall.io/forge/stream-forge/task/WldCode0014);
* [«Пригласительные на фестиваль»](https://hammerhall.io/forge/stream-forge/task/MovCode0019);
* [«Атлас для первоклассника»](https://hammerhall.io/forge/stream-forge/task/WldCode0002).

## Что дальше

Статья 5 — `groupingBy` и `toMap`: `collect` по-настоящему. Как
разложить заказы по группам и посчитать, сколько в каждой, как собрать
`Map` и не споткнуться о повтор ключа.

## Первоисточники

* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  `flatMap`, `distinct` (сравнение через `equals`, порядок первого
  появления), `mapMulti`.
* [Class Collectors — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Collectors.html) —
  `toSet()`: тип и изменяемость множества не обещаны.
* [Class Record — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Record.html) —
  как запись сравнивает себя (`equals`) и считает `hashCode`.
* [Class Object — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Object.html) —
  `equals` по умолчанию и правило «равные объекты — одинаковый
  `hashCode`».
* [Class HashSet — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/HashSet.html) —
  почему порядок элементов не обещан.

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

Если вместо русских букв в выводе вопросы или кракозябры, запусти
с явной кодировкой — аргумент в кавычках, так его поймёт и PowerShell:
`java "-Dstdout.encoding=UTF-8" Coffee.java`; в командной строке Windows
перед этим выполни `chcp 65001`.

```java
// Coffee.java — учебный пример статьи 4 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;

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

    // 1. Сколько раз пробили латте — циклом в цикле
    int latteByLoop = 0;
    for (Order order : orders) {
        for (Item item : order.items()) {               // цикл в цикле — по позициям заказа
            if (item.name().equals("латте")) {
                latteByLoop++;
            }
        }
    }
    IO.println("циклом: " + latteByLoop);

    // 2. map: по конвейеру едут списки позиций
    List<List<Item>> lists = orders.stream()
            .map(order -> order.items())
            .toList();
    IO.println(lists.size() + " " + lists.get(0));

    // 3. flatMap: по конвейеру едут сами позиции
    long itemCount = orders.stream()
            .flatMap(order -> order.items().stream())
            .count();
    IO.println(itemCount);

    // 4. Теперь фильтр по позиции работает
    long latte = orders.stream()
            .flatMap(order -> order.items().stream())
            .filter(item -> item.name().equals("латте"))
            .count();
    IO.println("стримом: " + latte);

    // 5. Ноль или один элемент на заказ: Stream.of и Stream.empty
    List<String> bigGuests = orders.stream()
            .flatMap(order -> order.total() >= 500
                    ? Stream.of(order.guest())
                    : Stream.empty())
            .toList();
    IO.println(bigGuests);

    // 6. Названия проданного — с повторами и без
    List<String> names = orders.stream()
            .flatMap(order -> order.items().stream())
            .map(Item::name)
            .toList();
    IO.println(names);
    List<String> distinctNames = orders.stream()
            .flatMap(order -> order.items().stream())
            .map(Item::name)
            .distinct()
            .toList();
    IO.println(distinctNames);

    // 7. Множество: повторов нет, порядок не обещан
    Set<String> soldSet = orders.stream()
            .flatMap(order -> order.items().stream())
            .map(Item::name)
            .collect(Collectors.toSet());
    IO.println(soldSet);
    IO.println(soldSet.contains("раф") + " " + soldSet.contains("матча"));

    // 8. Записи равны, если равны все поля
    Item a = new Item("латте", 250, 1);
    Item b = new Item("латте", 250, 1);
    Item c = new Item("латте", 250, 2);
    IO.println(a.equals(b) + " " + (a == b) + " " + a.equals(c));
    IO.println(a.hashCode() == b.hashCode());

    // 9. distinct по позициям и по названиям — разные ответы
    long distinctItems = orders.stream()
            .flatMap(order -> order.items().stream())
            .distinct()
            .count();
    IO.println(distinctItems + " разных позиций, " + distinctNames.size() + " разных названий");
}
```

Сделай руками:

1. Запусти файл. Первые строки — `циклом: 3`, число `10` с позициями
   заказа 1, `14` и `стримом: 3`.
2. В блоке `// 4.` замени строку с `flatMap` на
   `.map(order -> order.items())` и прочитай ошибку компилятора.
   Верни как было.
3. В блоке `// 3.` убери `.stream()` внутри `flatMap` — получишь
   ошибку из части 1. Верни как было.
4. В блоке `// 3.` замени строку с `flatMap` на две:
   `.map(Order::items)` и `.flatMap(List::stream)`. Ответ — снова `14`.
   Верни как было.
5. В блоке `// 8.` поменяй у `c` количество с `2` на `1`. Третье слово
   в строке станет `true`.
6. Сравни строки блоков `// 6.` и `// 7.`: сколько в них элементов
   и в каком порядке.
