# Стрим по `Map`: сортировка по значению и «топ-N»

> «Стримы по шагам» · статья 7 · читать минут 15
>
> **Для кого.** Ты прочитал статьи 5 и 6: собираешь карту через
> `groupingBy` и считаешь в группе сумму. Помнишь компараторы
> и `thenComparing` из статьи 3, `limit` и `Optional` из статьи 2.
>
> **Что будет.** Как пустить стрим по карте и что по нему едет; как
> отсортировать карту по значению и взять «топ-3»; почему
> `comparingByValue().reversed()` не компилируется; как не дать ничьей
> решиться случаем; как собрать результат обратно в карту и когда
> вместо пары нужна запись.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем стрим по карте

Хозяйка «Наковальни» спрашивает: какие три позиции принесли за день
больше всего денег? Выручку по позициям ты уже умеешь считать — это
группировка из статьи 6, только складываем цену, умноженную на штуки:

```java
Map<String, Integer> revenue = orders.stream()
        .flatMap(order -> order.items().stream())
        .collect(groupingBy(Item::name, TreeMap::new,
                summingInt(item -> item.price() * item.qty())));
```

```
{американо=170, какао=200, капучино=880, круассан=540, латте=1000, раф=290, чизкейк=960, эспрессо=450}
```

Коллекторы, как и в статье 6, пришли статическим импортом — без
`Collectors.` впереди.

Глазами ответ виден: латте, чизкейк, капучино. Но `TreeMap` сортирует
только по ключам — по названиям, а нужно по деньгам. Даже одного лидера
циклом искать — восемь строк:

```java
String leader = null;                          // лучшая позиция пока не найдена
int best = 0;
for (String name : revenue.keySet()) {
    if (revenue.get(name) > best) {            // выручка больше лучшей —
        best = revenue.get(name);              // запоминаем
        leader = name;
    }
}
```

Для трёх лучших — три прохода или сортировка руками. Стримом «топ-3» —
четыре строки:

```java
List<Map.Entry<String, Integer>> top3 = revenue.entrySet().stream()
        .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))  // по выручке, по убыванию
        .limit(3)                                                       // первые три
        .toList();
```

```
[латте=1000, чизкейк=960, капучино=880]
```

🔑 Карту не сортируют. Её превращают в стрим пар «ключ — значение»
и сортируют стрим.

В этой статье — что такое `entrySet()` и `Map.Entry`, как сортировать
по значению, где здесь ловушка компилятора и как не дать ничьей
решиться случаем.

---

## Часть 1. Пары карты

### У карты нет stream()

Первое, что хочется написать, — `revenue.stream()`. Компилятор
не даст:

```
Coffee.java:55: error: cannot find symbol
    revenue.stream();
           ^
  symbol:   method stream()
  location: variable revenue of type Map<String,Integer>
```

`stream()` есть у списков и множеств: у них общий предок — интерфейс
`Collection`, метод объявлен в нём. `Map` — не `Collection`: она хранит
не элементы, а пары, и в Java стоит отдельно.

### Три вида на карту

Зато у карты есть три метода, которые показывают её содержимое
коллекцией, — а у коллекции `stream()` есть:

| метод | что внутри | когда нужен |
|---|---|---|
| `keySet()` | ключи — названия позиций | нужны только ключи |
| `values()` | значения — выручка | нужны только значения |
| `entrySet()` | пары «ключ — значение» | нужно и то и другое |

Сортировать по выручке, а отвечать названиями — нужно и то и другое.
Значит, `entrySet()`.

### Map.Entry — ключ и значение вместе

По стриму из `entrySet()` едут **пары** — объекты типа
`Map.Entry<String, Integer>`. `Entry` — интерфейс внутри `Map`,
поэтому и пишется через точку. Не путай пару с записью `record`: пару
выдаёт карта, и читают её два метода — `getKey()` и `getValue()`.
Печатается пара так же, как внутри карты: `латте=1000`.

Какие позиции принесли от 500 ₽?

```java
List<String> over500 = revenue.entrySet().stream()
        .filter(entry -> entry.getValue() >= 500)      // смотрим на значение пары
        .map(Map.Entry::getKey)                        // а отвечаем ключом
        .toList();
```

```
[капучино, круассан, латте, чизкейк]
```

`Map.Entry::getKey` — ссылка на метод, как `Order::guest`: «от пары —
её ключ». Названия идут по алфавиту: пары едут в порядке карты,
а карта — `TreeMap`.

---

## Часть 2. Сортировка по значению

### comparingByValue

У `Map.Entry` есть готовые компараторы: `comparingByKey()` — по ключу
и `comparingByValue()` — по значению. По возрастанию выручки:

```java
List<Map.Entry<String, Integer>> ascending = revenue.entrySet().stream()
        .sorted(Map.Entry.comparingByValue())
        .toList();
```

```
[американо=170, какао=200, раф=290, эспрессо=450, круассан=540, капучино=880, чизкейк=960, латте=1000]
```

Ответ — список пар, `List<Map.Entry<String, Integer>>`. Тип длинный,
но читается по частям: список — пар — «строка, число».

Для убывания `comparingByValue` принимает компаратор для самих
значений — так сделано в «Зачем»: `Comparator.reverseOrder()`
из статьи 3 значит «наоборот». А `limit(3)` из статьи 2 оставляет
первые три пары. Это и есть «топ-3».

### Ловушка: comparingByValue().reversed()

⚠️ В статье 3 компаратор разворачивали через `.reversed()`. Напишешь
так и здесь:

```java
List<Map.Entry<String, Integer>> top3Reversed = revenue.entrySet().stream()
        .sorted(Map.Entry.comparingByValue().reversed())     // так не скомпилируется
        .limit(3)
        .toList();
```

Компилятор ответит:

```
Coffee.java:78: error: no suitable method found for sorted(Comparator<Entry<Object,V#1>>)
            .sorted(Map.Entry.comparingByValue().reversed())
            ^
…
      (argument mismatch; Comparator<Entry<Object,V#2>> cannot be converted to Comparator<? super Entry<String,Integer>>)
…
```

Смотри на `Entry<Object, …>`: Java решила, что ключ пары — `Object`,
а не `String`. Типы для `comparingByValue()` компилятор берёт из того,
куда уходит её результат. Без `.reversed()` результат уходит прямо
в `sorted`, и видно: нужны пары «строка, число». С `.reversed()` он
уходит в `reversed()`, а тот ничего не подсказывает — и ключ становится
`Object`. Это ловушка «лямбда перед `reversed` теряет тип» из статьи 3:
там параметр лямбды стал `Object`, здесь — ключ пары.

Выхода два. Первый — не строить цепочку:
`comparingByValue(Comparator.reverseOrder())`, как в «Зачем». Второй —
подсказать типы самому. **Подсказка типа** (type witness) — угловые
скобки перед именем метода:

```java
List<Map.Entry<String, Integer>> top3Reversed = revenue.entrySet().stream()
        .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
        .limit(3)
        .toList();
```

`Map.Entry.<String, Integer>comparingByValue()` читается так:
«компаратор по значению для пар „строка, число“». Ответ тот же:
`[латте=1000, чизкейк=960, капучино=880]`.

---

## Часть 3. Ничьи

### Когда значения равны

Теперь «топ-3» по штукам, а не по деньгам. Штуки по позициям — это
`summingInt(Item::qty)` из статьи 6. Карту на этот раз собираем без
`TreeMap::new` — нарочно, как часто и бывает в рабочем коде:

```java
Map<String, Integer> pieces = orders.stream()
        .flatMap(order -> order.items().stream())
        .collect(groupingBy(Item::name, summingInt(Item::qty)));
```

```
{американо=1, раф=1, какао=1, латте=4, чизкейк=3, круассан=3, капучино=4, эспрессо=3}
```

Порядок — вразнобой: это `HashMap`, помнишь статью 5. Тот же «топ-3»:

```java
List<Map.Entry<String, Integer>> top3Pieces = pieces.entrySet().stream()
        .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
        .limit(3)
        .toList();
```

```
без правила ничьей: [латте=4, капучино=4, чизкейк=3]
```

У латте и капучино по 4 — обе позиции в тройке, вопрос только, кто
первый.
А по 3 штуки — у трёх позиций: чизкейка, круассана и эспрессо. Почему
в тройку попал чизкейк?

Сортировка в стриме, помнишь из статьи 3, устойчивая: равные элементы
она не переставляет, они остаются в том порядке, в каком пришли. А пришли
они в порядке `HashMap`, который никто не гарантирует. Чизкейк в тройке
потому, что в этой карте лежал раньше круассана. Добавится позиция,
сменится версия Java — в тройке может оказаться другой. Отчёт будет
меняться без причины, а тест — то проходить, то падать.

### Правило ничьей — второй компаратор

Ничью решает правило, а не случай. Правило записывают вторым
компаратором — `thenComparing` из статьи 3: при равных штуках —
по названию.

```java
List<Map.Entry<String, Integer>> top3Fair = pieces.entrySet().stream()
        .sorted(Map.Entry.<String, Integer>comparingByValue().reversed()
                .thenComparing(Map.Entry.comparingByKey()))
        .limit(3)
        .toList();
```

```
с правилом ничьей:  [капучино=4, латте=4, круассан=3]
```

Теперь порядок задан целиком: сначала больше штук, при равенстве —
по алфавиту. `reversed()` стоит до `thenComparing` и разворачивает
только значение — названия идут по алфавиту, как обычно. Какой бы
ни пришла карта, ответ один. Подсказка типа снова нужна:
`.thenComparing(…)` — тоже цепочка.

💡 Подсказка типа режет глаз — положи первый компаратор в переменную
с явным типом. Тогда типы Java возьмёт из объявления:

```java
Comparator<Map.Entry<String, Integer>> byValueDesc =
        Map.Entry.comparingByValue(Comparator.reverseOrder());
List<Map.Entry<String, Integer>> top3Fair = pieces.entrySet().stream()
        .sorted(byValueDesc.thenComparing(Map.Entry.comparingByKey()))
        .limit(3)
        .toList();
```

🔑 «Топ-N» без правила ничьей — ответ, который зависит от случая.
Сортируешь по значению — сразу спроси себя: а если значения равны?

💡 «Топ-3» разрезал ничью: круассан в тройке, а чизкейк и эспрессо
с теми же тремя штуками — нет. Алфавит — правило, но не
справедливость. Какое правило верное, решает тот, кто задаёт вопрос;
в задачах кузницы оно написано в условии — читай внимательно.

---

## Часть 4. Один лидер и обратно в карту

### max — один лидер

Нужен только лидер — сортировать всё незачем. `max` из статьи 3
с компаратором по значению:

```java
String leader = revenue.entrySet().stream()
        .max(Map.Entry.comparingByValue())
        .map(Map.Entry::getKey)                 // от пары — название
        .orElse("продаж нет");
```

```
лидер по выручке: латте
```

`max` отвечает `Optional`: у пустой карты лидера нет. `map` и `orElse`
над ним — из статьи 2.

Лидеров с равной выручкой может быть несколько, и кого из них вернёт
`max`, документация не обещает. Правило ничьей добавляют тем же
`thenComparing` — и с подсказкой типа, как в части 3. Только помни:
`max` берёт наибольшее и по второму правилу — из равных по выручке
победит тот, чей ключ больше.

### Обратно в карту: порядок держит LinkedHashMap

Иногда рейтинг нужен картой: печатать по порядку и при этом быстро
доставать выручку по названию. Обычный `toMap` из статьи 5 порядок
потеряет:

```java
Map<String, Integer> ratingLost = revenue.entrySet().stream()
        .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
        .collect(toMap(Map.Entry::getKey, Map.Entry::getValue));
```

```
{американо=170, раф=290, латте=1000, какао=200, чизкейк=960, круассан=540, капучино=880, эспрессо=450}
```

Стрим отдал пары по убыванию, а `toMap` сложил их в `HashMap`, и та
разложила по-своему. Нужна карта, которая помнит порядок добавления, —
`LinkedHashMap` из статьи 5. Её задают четвёртым аргументом `toMap`,
а значит, нужен и третий — функция слияния. Повторов ключей здесь
не будет, пары пришли из карты, так что годится любая — например,
«оставить первое»:

```java
Map<String, Integer> rating = revenue.entrySet().stream()
        .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
        .collect(toMap(Map.Entry::getKey, Map.Entry::getValue,
                (a, b) -> a, LinkedHashMap::new));
```

```
{латте=1000, чизкейк=960, капучино=880, круассан=540, эспрессо=450, раф=290, какао=200, американо=170}
```

⚠️ `TreeMap::new` здесь не поможет: она снова отсортирует по ключам,
и рейтинг станет алфавитом.

А если по рейтингу нужно только пройти по порядку, карта не нужна
вовсе — хватит списка пар из `toList()`, как в «топ-3».

### Свои пары: Map.entry и запись

Пары приходится и строить — например, «позиция и её доля в выручке
дня». Быстрая пара на ходу — `Map.entry(ключ, значение)`:

```java
int total = orders.stream().collect(summingInt(Order::total));      // выручка дня, 4490 ₽
List<Map.Entry<String, Integer>> sharePairs = top3.stream()
        .map(entry -> Map.entry(entry.getKey(), entry.getValue() * 100 / total))
        .toList();
```

```
[латте=22, чизкейк=21, капучино=19]
```

`Map.entry` (с Java 9) даёт неизменяемую пару, и `null` в ней быть
не может — ни ключом, ни значением. Но посмотри на код, который будет
эти пары читать: `getValue()` — это рубли или проценты? По имени
не понять. Пара уходит дальше — из метода, в отчёт, — дай ей имена,
заведи запись:

```java
record ItemShare(String name, int percent) {}
```

```java
List<ItemShare> shares = top3.stream()
        .map(entry -> new ItemShare(entry.getKey(), entry.getValue() * 100 / total))
        .toList();
```

```
[ItemShare[name=латте, percent=22], ItemShare[name=чизкейк, percent=21], ItemShare[name=капучино, percent=19]]
```

Теперь `percent()` говорит сам за себя. `Map.Entry` хороша внутри
одного конвейера; то, что живёт дольше, лучше записью.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему у `Map` нет `stream()`? Какие три метода дают коллекцию
   и что лежит в каждой?
2. Что такое `Map.Entry`, как прочитать её ключ и значение и как она
   печатается?
3. Как отсортировать пары по значению по убыванию? Назови два способа.
4. Почему `Map.Entry.comparingByValue().reversed()` не компилируется?
   Что значит `<String, Integer>` перед именем метода?
5. В «топ-3» по штукам без правила ничьей третьим оказался чизкейк.
   Почему именно он и почему на это нельзя полагаться?
6. Как сделать, чтобы «топ-N» не зависел от порядка в карте?
7. Почему `max` отвечает `Optional`? Кого он выберет из равных, если
   добавить `thenComparing(Map.Entry.comparingByKey())`?
8. Почему обычный `toMap` не годится для рейтинга и чем его заменить?
   Когда вместо `Map.entry` лучше завести запись?

---

## Реши в кузнице

Задачи на то же самое — `entrySet`, `comparingByValue`, `max`,
«топ-N» и правила ничьей — в кузнице Stream Forge на платформе
Hammerhall, на фильмах и странах мира. Задачи бесплатны, нужен только
вход:

* [«Найти год, в котором вышло больше всего фильмов»](https://hammerhall.io/forge/stream-forge/task/MovCode0031);
* [«Найти название самого популярного жанра по количеству фильмов»](https://hammerhall.io/forge/stream-forge/task/MovCode0032);
* [«Найти топ-5 самых населённых городов мира вместе со страной и континентом»](https://hammerhall.io/forge/stream-forge/task/WldCode0043).

## Что дальше

Статья 8 — числа: `IntStream`, `mapToInt`, `sum` и `average`,
переполнение — и метод `total()` наконец станет стримом.

## Первоисточники

* [Interface Map.Entry — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Map.Entry.html) —
  `getKey`, `getValue`, `comparingByKey`, `comparingByValue`.
* [Interface Map — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Map.html) —
  три вида на карту, `entrySet()`, `Map.entry`; в описании класса —
  что `TreeMap` порядок гарантирует, а `HashMap` нет.
* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  у `sorted` — что сортировка упорядоченного стрима устойчивая; `max`.
* [Class LinkedHashMap — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/LinkedHashMap.html) —
  карта, которая помнит порядок добавления.

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
// Coffee.java — учебный пример статьи 7 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
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

/** Позиция и её доля в выручке дня, в процентах: пара с понятными именами. */
record ItemShare(String name, int percent) {}

void main() {
    List<Order> orders = orders();

    // Выручка по позициям: цена × штуки, сложенные по названию (статья 6)
    Map<String, Integer> revenue = orders.stream()
            .flatMap(order -> order.items().stream())
            .collect(groupingBy(Item::name, TreeMap::new,
                    summingInt(item -> item.price() * item.qty())));
    IO.println(revenue);

    // 1. У карты нет stream() — стрим берут у entrySet(): по нему едут пары
    List<String> over500 = revenue.entrySet().stream()
            .filter(entry -> entry.getValue() >= 500)
            .map(Map.Entry::getKey)
            .toList();
    IO.println(over500);

    // 2. Пары по значению, по возрастанию
    List<Map.Entry<String, Integer>> ascending = revenue.entrySet().stream()
            .sorted(Map.Entry.comparingByValue())
            .toList();
    IO.println(ascending);

    // 3. «Топ-3»: по убыванию значения и первые три
    List<Map.Entry<String, Integer>> top3 = revenue.entrySet().stream()
            .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
            .limit(3)
            .toList();
    IO.println(top3);

    // 4. То же через reversed(): без подсказки типа <String, Integer> не скомпилируется
    List<Map.Entry<String, Integer>> top3Reversed = revenue.entrySet().stream()
            .sorted(Map.Entry.<String, Integer>comparingByValue().reversed())
            .limit(3)
            .toList();
    IO.println(top3Reversed);

    // 5. Штуки по позициям — нарочно в HashMap, без TreeMap::new
    Map<String, Integer> pieces = orders.stream()
            .flatMap(order -> order.items().stream())
            .collect(groupingBy(Item::name, summingInt(Item::qty)));
    IO.println(pieces);

    // 6. «Топ-3» по штукам: в ничьей решает порядок, в котором пары пришли
    List<Map.Entry<String, Integer>> top3Pieces = pieces.entrySet().stream()
            .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
            .limit(3)
            .toList();
    IO.println("без правила ничьей: " + top3Pieces);

    // 7. Правило ничьей: при равных штуках — по названию
    List<Map.Entry<String, Integer>> top3Fair = pieces.entrySet().stream()
            .sorted(Map.Entry.<String, Integer>comparingByValue().reversed()
                    .thenComparing(Map.Entry.comparingByKey()))
            .limit(3)
            .toList();
    IO.println("с правилом ничьей:  " + top3Fair);

    // 8. Один лидер: max отвечает Optional
    String leader = revenue.entrySet().stream()
            .max(Map.Entry.comparingByValue())
            .map(Map.Entry::getKey)
            .orElse("продаж нет");
    IO.println("лидер по выручке: " + leader);

    // 9. Весь рейтинг — обратно в карту: обычный toMap порядок теряет
    Map<String, Integer> ratingLost = revenue.entrySet().stream()
            .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
            .collect(toMap(Map.Entry::getKey, Map.Entry::getValue));
    IO.println(ratingLost);

    // 10. LinkedHashMap::new хранит порядок, в котором пришли ключи
    Map<String, Integer> rating = revenue.entrySet().stream()
            .sorted(Map.Entry.comparingByValue(Comparator.reverseOrder()))
            .collect(toMap(Map.Entry::getKey, Map.Entry::getValue,
                    (a, b) -> a, LinkedHashMap::new));
    IO.println(rating);

    // 11. Новые пары: Map.entry — на ходу, запись — с понятными именами
    int total = orders.stream().collect(summingInt(Order::total));
    List<Map.Entry<String, Integer>> sharePairs = top3.stream()
            .map(entry -> Map.entry(entry.getKey(), entry.getValue() * 100 / total))
            .toList();
    IO.println(sharePairs);
    List<ItemShare> shares = top3.stream()
            .map(entry -> new ItemShare(entry.getKey(), entry.getValue() * 100 / total))
            .toList();
    IO.println(shares);
    IO.println(shares.get(0).name() + " — " + shares.get(0).percent() + "% выручки");
}
```

Сделай руками:

1. Запусти файл. Первая строка — выручка по позициям; найди строки
   «без правила ничьей» и «с правилом ничьей» — третьи места у них
   разные.
2. Сразу после `IO.println(revenue);` допиши `revenue.stream();` —
   компилятор скажет `location: variable revenue of type
   Map<String,Integer>`. Убери строку.
3. В блоке `// 4.` убери подсказку `<String, Integer>` и прочитай
   ошибку: `Entry<Object,…>`. Верни как было.
4. В блоке `// 5.` допиши фабрику: `groupingBy(Item::name, TreeMap::new,
   summingInt(Item::qty))`. Строки «без правила» и «с правилом» совпадут:
   `[капучино=4, латте=4, круассан=3]`, — алфавит пришёл из `TreeMap`,
   то есть случайно. Верни как было.
5. В блоке `// 8.` замени `revenue.entrySet()` на
   `new TreeMap<String, Integer>().entrySet()` — выйдет
   `лидер по выручке: продаж нет`. Верни как было.
6. В блоке `// 10.` замени `LinkedHashMap::new` на `TreeMap::new` —
   рейтинг станет алфавитом: `{американо=170, какао=200, …}`.
