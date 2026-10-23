# Две коллекции: индекс вместо стрима в стриме

> «Стримы по шагам» · статья 9 · читать минут 15
>
> **Для кого.** Ты прочитал статьи 1–8 серии или знаешь то же сам:
> конвейер, лямбды, `findFirst` и `Optional`, `toMap` и карты,
> `IntStream`. До сих пор все вопросы были к одному списку — заказам.
>
> **Что будет.** Как сопоставить две коллекции — заказы и гостей
> с картами лояльности; почему стрим внутри стрима работает, но с ростом
> данных тонет; как построить индекс за один проход и что делать, когда
> нужного ключа в нём нет или ключ повторился.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем индекс

В «Наковальне» завели карты лояльности: у постоянных гостей скидка —
5 или 10 процентов. Хозяйка спрашивает: сколько скидок мы дали за день?

Ответ лежит в двух коллекциях сразу. Сумма — в заказе, процент —
в карте гостя. А заказ знает о госте только имя. Значит, для каждого
заказа нужно найти гостя в другом списке.

Первое, что приходит в голову, — для каждого заказа пройти по гостям.
На стримах это стрим внутри стрима, и он работает. На десяти заказах —
незаметно. На месяце работы сети из статьи 8 — пять миллионов
сравнений там, где хватило бы одиннадцати тысяч шагов.

В этой статье — как устроен такой поиск, сколько он стоит на самом деле
и как заменить его **индексом**: картой, которую строят один раз
и в которой потом находят сразу.

---

## Часть 1. Вторая коллекция

### Гости с картой

Записи `Item` и `Order` в серии не меняются. Для карт — новая запись
рядом с ними:

```java
record Guest(String name, String card, int discount) {}   // имя, номер карты, скидка в %
```

И список гостей с картой:

```java
List<Guest> guests() {
    return List.of(
            new Guest("Анна", "К-101", 10),
            new Guest("Борис", "К-102", 5),
            new Guest("Вера", "К-103", 10),
            new Guest("Глеб", "К-104", 5),
            new Guest("Дина", "К-105", 10),
            new Guest("Зоя", "К-106", 15));
}
```

Двух гостей дня здесь нет: у Егора и Жанны карты нет. Можно было бы
завести их с пустым номером или с `null` вместо карты — но тогда
каждый, кто читает список, должен помнить об этой оговорке. Правило
проще: нет карты — нет записи. А Зоя в списке есть, но сегодня
не заходила: база карт всегда шире одного дня.

### Стрим в стриме

Скидка по каждому заказу:

```java
List<Integer> discounts = orders.stream()
        .map(order -> guests.stream()                                   // для заказа — стрим по гостям
                .filter(guest -> guest.name().equals(order.guest()))   // гость этого заказа
                .findFirst()                                            // Optional<Guest>
                .map(guest -> order.total() * guest.discount() / 100)   // скидка в рублях
                .orElse(0))                                             // карты нет — скидки нет
        .toList();
```

```
[43, 15, 22, 41, 17, 65, 0, 89, 33, 0]
```

Внутри `map` по заказам — целый конвейер по гостям: отобрать того,
чьё имя совпало с именем в заказе, и взять первого (`findFirst`,
[статья 2](https://hammerhall.io/ledger/streams/2-filter-map-optional)). `map` у `Optional`
работает, как у стрима: гость нашёлся — превращает его в скидку;
не нашёлся — коробка остаётся пустой, и `orElse(0)` даёт ноль.
Деление целое: копейки отбросились бы, но скидки в примере делятся
нацело.

Сумма скидок за день — 325 ₽, ответ верный. Но во внутреннем стриме
спрятана работа, которой в коде не видно.

---

## Часть 2. Сколько стоит стрим в стриме

### Считаем сравнения

Вынесем поиск в метод и посчитаем каждое сравнение имён:

```java
long comparisons = 0;   // сколько раз сравнили имена — только чтобы увидеть работу

int discountBySearch(Order order, List<Guest> guests) {
    return guests.stream()
            .filter(guest -> {
                comparisons++;
                return guest.name().equals(order.guest());
            })
            .findFirst()
            .map(guest -> order.total() * guest.discount() / 100)
            .orElse(0);
}
```

Счётчик в `filter` — тот же приём, что печать в статье 1: чтобы
увидеть, что делает конвейер, а не для рабочего кода. Объявлен он
полем, рядом с методами файла, а не переменной внутри `main`: менять
переменную метода из лямбды Java не даёт — помнишь правило
«фактически final» из [статьи 2](https://hammerhall.io/ledger/streams/2-filter-map-optional);
почему поле менять можно, разберём в следующей статье.

```java
int daySearch = orders.stream()
        .mapToInt(order -> discountBySearch(order, guests))
        .sum();
```

```
скидок за день: 325 ₽, сравнений: 33
```

33 сравнения на 10 заказов. `findFirst` останавливает поиск на первом
совпадении, поэтому Анне хватает одного сравнения, Дине — пяти. А для
Егора и Жанны, которых в списке нет, поиск проходит всех шестерых
до конца.

### Месяц сети

Теперь масштаб из [статьи 8](https://hammerhall.io/ledger/streams/8-number-streams): сеть
кофеен за месяц. Тысяча гостей с картой и десять тысяч заказов —
сгенерируем их через `IntStream.rangeClosed` и `mapToObj`:

```java
List<Guest> manyGuests = IntStream.rangeClosed(1, 1_000)
        .mapToObj(i -> new Guest("гость " + i, "К-" + i, 10))
        .toList();
List<Order> manyOrders = IntStream.rangeClosed(1, 10_000)
        .mapToObj(i -> new Order(i, "гость " + (i % 1_000 + 1), List.of(new Item("латте", 250, 1))))
        .toList();
```

Подчёркивание в `1_000` — только для глаз, Java его пропускает. Заказы
по кругу делают гости с 1-го по 1000-го, каждый берёт латте за 250 ₽.

```java
comparisons = 0;
int monthSearch = manyOrders.stream()
        .mapToInt(order -> discountBySearch(order, manyGuests))
        .sum();
```

```
месяц перебором: скидок 250000 ₽, сравнений: 5005000
```

Пять миллионов сравнений. Гость номер k находится на k-м шаге,
в среднем — на пятисотом, и так для каждого из 10 000 заказов.

Это и есть цена стрима в стриме: работа растёт как произведение
размеров. Заказов n, гостей m — сравнений порядка n · m; программисты
записывают это как **O(n·m)**. Вдвое больше заказов и вдвое больше
гостей — вчетверо больше работы. На десяти заказах этого не видно,
а данные со временем только растут.

🔑 Стрим внутри стрима — это вложенный цикл. В коде он не похож
на цикл, но работает как цикл: для каждого внешнего элемента — полный
проход по внутренней коллекции.

---

## Часть 3. Индекс

### Один проход по гостям

Идея: пройти по гостям один раз и разложить их так, чтобы потом
находить по имени сразу. Это карта «имя → гость», `toMap`
из [статьи 5](https://hammerhall.io/ledger/streams/5-grouping):

```java
Map<String, Guest> cards = guests.stream()
        .collect(Collectors.toMap(Guest::name, Function.identity()));   // имя → сам гость
```

Ключ — `Guest::name`. Значение — сам гость, и для этого есть готовая
функция `Function.identity()`: она возвращает то, что получила. Это то
же самое, что `guest -> guest`, — можно писать и так. Документация
`toMap` сама советует её для случая, когда значение — сам элемент.

Такая карта и есть индекс — как предметный указатель в конце книги:
не листаешь все страницы, а сразу открываешь нужную.

```java
IO.println(cards.get("Вера"));
IO.println(cards.get("Егор"));
```

```
Guest[name=Вера, card=К-103, discount=10]
null
```

`get` находит Веру без перебора. Какую карту вернёт `toMap`,
документация не обещает, но на JDK 25 это `HashMap`. По ключу она
вычисляет место значения через `hashCode` ключа — здесь строки (тот же
номерок, что у `HashSet` в [статье 4](https://hammerhall.io/ledger/streams/4-flatmap)) —
и идёт прямо туда.
Документация `HashMap` обещает для `get` и `put` постоянное время —
не зависящее от того, сколько в карте ключей, если хеш раскладывает
ключи равномерно.

### ⚠️ `get` без ключа — `null`

Егора в индексе нет, и `get` вернул `null` — «ничего». Вызови на нём
метод — и программа упадёт:

```java
IO.println(cards.get("Егор").discount());
```

```
Exception in thread "main" java.lang.NullPointerException: Cannot invoke "Coffee$Guest.discount()" because the return value of "java.util.Map.get(Object)" is null
```

Сообщение точное: метод `discount()` не вызвать, потому что `Map.get`
вернул `null`. `Coffee$Guest` — так Java называет запись `Guest`
из файла `Coffee.java`.

### Индекс вместо внутреннего стрима

Проверять `null` руками не нужно: `Optional.ofNullable(…)` кладёт
значение в коробку `Optional`, а `null` превращает в пустую коробку.
Дальше — знакомый хвост:

```java
long lookups = 0;       // сколько раз обратились к индексу

int discountByIndex(Order order, Map<String, Guest> cards) {
    lookups++;
    return Optional.ofNullable(cards.get(order.guest()))   // гость или пустая коробка
            .map(guest -> order.total() * guest.discount() / 100)
            .orElse(0);
}
```

Сравни с `discountBySearch`: хвост `.map(…).orElse(0)` тот же.
Поменялась голова: вместо конвейера по всем гостям — одно обращение
`get`. Тот же месяц сети:

```java
Map<String, Guest> manyCards = manyGuests.stream()
        .collect(Collectors.toMap(Guest::name, Function.identity()));
lookups = 0;
int monthIndex = manyOrders.stream()
        .mapToInt(order -> discountByIndex(order, manyCards))
        .sum();
```

```
месяц по индексу: скидок 250000 ₽, обращений к индексу: 10000
```

Ответ тот же — 250 000 ₽. Работа — один проход по 1 000 гостям, чтобы
построить индекс, и 10 000 обращений к нему. Вместо пяти миллионов
сравнений — одиннадцать тысяч шагов: работа растёт как сумма
размеров, O(n + m).

🔑 Нужно сопоставить две коллекции — построй индекс по той, в которой
ищешь, один раз и до конвейера. Внутри конвейера — только `get`.
Построй индекс внутри `map` — и он будет строиться заново для каждого
заказа: снова n · m.

### Нужна одна величина — `getOrDefault`

Если из гостя нужен только процент, индекс можно сделать проще: «имя →
процент». А отсутствующий ключ закроет `getOrDefault(ключ, запасное)`:
значение по ключу, а если ключа нет — запасное.

```java
Map<String, Integer> percentByName = guests.stream()
        .collect(Collectors.toMap(Guest::name, Guest::discount));      // имя → процент
List<Integer> percents = orders.stream()
        .map(order -> percentByName.getOrDefault(order.guest(), 0))    // нет карты — 0 %
        .toList();
```

```
[10, 5, 10, 5, 10, 10, 0, 10, 5, 0]
```

Ни `null`, ни `Optional`: у Егора и Жанны честные ноль процентов.

---

## Часть 4. Ключ индекса

### Повтор ключа

Карту завела вторая Анна — новая гостья, карта К-107, скидка 5 %.
Добавим её в список гостей и запустим:

```
Exception in thread "main" java.lang.IllegalStateException: Duplicate key Анна (attempted merging values Guest[name=Анна, card=К-101, discount=10] and Guest[name=Анна, card=К-107, discount=5])
```

Это `toMap` из статьи 5: на повторе ключа он не выбирает молча,
а бросает исключение. Функция слияния `(first, second) -> first`
исключение заглушит — но тогда одна Анна получит чужую скидку, и никто
этого не заметит.

⚠️ В настоящих системах имя — плохой ключ: Анн может быть сколько
угодно, поэтому заказ хранит номер карты или идентификатор гостя,
и индекс строят по нему.

### Кого нет в индексе

Обратный вопрос: кто из сегодняшних гостей без карты — кому бариста
её предложит?

```java
List<String> noCard = orders.stream()
        .map(Order::guest)
        .filter(name -> !cards.containsKey(name))   // имени нет в индексе
        .distinct()
        .toList();
```

```
[Егор, Жанна]
```

`containsKey` — тоже одно обращение к индексу, без перебора.

💡 Если нужно только «есть или нет», индексом послужит и множество
имён: `toSet()` из статьи 4 и `contains`.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему для Егора и Жанны нет записи `Guest` — ни с пустой картой,
   ни с `null`?
2. Сколько сравнений имён делает стрим в стриме на 10 заказах
   и 6 гостях — и почему не 60?
3. Откуда пять миллионов сравнений на месяце сети? Как вырастет работа,
   если удвоить и заказы, и гостей?
4. Что делает `Function.identity()` и чем её можно заменить?
5. Что вернёт `cards.get("Егор")` и что будет, если сразу вызвать
   на результате `discount()`? Как обойтись без проверки на `null`?
6. Чем `getOrDefault` удобнее `get` и когда его хватает?
7. Что сделает `toMap`, если в списке гостей две Анны? Почему функция
   слияния здесь — плохое лекарство?
8. Почему индекс строят до конвейера по заказам, а не внутри него?

---

## Реши в кузнице

Задачи на две коллекции — страны и их города — в кузнице Stream Forge
на платформе Hammerhall. Первые задачи бесплатны, нужен только вход:

* [«Час пик»](https://hammerhall.io/forge/stream-forge/task/WldCode0015);
* [«Конверты в посольства»](https://hammerhall.io/forge/stream-forge/task/WldCode0026);
* [«Жалоба губернатора»](https://hammerhall.io/forge/stream-forge/task/WldMind0020);
* [«Спор двух городов»](https://hammerhall.io/forge/stream-forge/task/WldMind0021).

## Что дальше

Статья 10 — последняя в серии: из каких частей состоит коллектор
и как собрать свой; `peek` для отладки; и честно — когда цикл лучше
стрима. Там же — почему поле-счётчик `comparisons` лямбде менять можно.

## Первоисточники

* [Class Collectors — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Collectors.html) —
  `toMap`: повтор ключа — `IllegalStateException`, совет про
  `Function.identity()`, тип карты не гарантирован.
* [Interface Function — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/function/Function.html) —
  `identity()`: функция, которая возвращает свой аргумент.
* [Interface Map — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Map.html) —
  `get` и `null` без ключа, `getOrDefault`, `containsKey`.
* [Class HashMap — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/HashMap.html) —
  в начале страницы: постоянное время `get` и `put`.
* [Class Optional — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Optional.html) —
  `ofNullable` и `map`.

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Устроен файл, как в [статье 1](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop):
записи вверху, методы и `main` — без класса вокруг. Заказы те же,
`total()` — стримом, как в статье 8; новое — запись `Guest`, список
`guests()`, два счётчика-поля и два метода поиска. Сохрани файл как
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
// Coffee.java — учебный пример статьи 9 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;
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

/** Гость с картой лояльности: имя, номер карты, скидка в процентах. */
record Guest(String name, String card, int discount) {}

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

/** Гости с картой лояльности. У кого карты нет, того в списке нет. */
List<Guest> guests() {
    return List.of(
            new Guest("Анна", "К-101", 10),
            new Guest("Борис", "К-102", 5),
            new Guest("Вера", "К-103", 10),
            new Guest("Глеб", "К-104", 5),
            new Guest("Дина", "К-105", 10),
            new Guest("Зоя", "К-106", 15));
}

long comparisons = 0;   // сколько раз сравнили имена — только чтобы увидеть работу
long lookups = 0;       // сколько раз обратились к индексу

/** Скидка по заказу в рублях: перебором гостей — стрим в стриме. */
int discountBySearch(Order order, List<Guest> guests) {
    return guests.stream()
            .filter(guest -> {
                comparisons++;
                return guest.name().equals(order.guest());
            })
            .findFirst()
            .map(guest -> order.total() * guest.discount() / 100)
            .orElse(0);
}

/** Скидка по заказу в рублях: одним обращением к индексу. */
int discountByIndex(Order order, Map<String, Guest> cards) {
    lookups++;
    return Optional.ofNullable(cards.get(order.guest()))
            .map(guest -> order.total() * guest.discount() / 100)
            .orElse(0);
}

void main() {
    List<Order> orders = orders();
    List<Guest> guests = guests();

    // 1. Скидка по каждому заказу: для каждого заказа — стрим по гостям
    List<Integer> discounts = orders.stream()
            .map(order -> guests.stream()
                    .filter(guest -> guest.name().equals(order.guest()))
                    .findFirst()
                    .map(guest -> order.total() * guest.discount() / 100)
                    .orElse(0))
            .toList();
    IO.println(discounts);

    // 2. Сколько сравнений имён ушло на день
    int daySearch = orders.stream()
            .mapToInt(order -> discountBySearch(order, guests))
            .sum();
    IO.println("скидок за день: " + daySearch + " ₽, сравнений: " + comparisons);

    // 3. Месяц сети: 1 000 гостей с картой, 10 000 заказов
    List<Guest> manyGuests = IntStream.rangeClosed(1, 1_000)
            .mapToObj(i -> new Guest("гость " + i, "К-" + i, 10))
            .toList();
    List<Order> manyOrders = IntStream.rangeClosed(1, 10_000)
            .mapToObj(i -> new Order(i, "гость " + (i % 1_000 + 1), List.of(new Item("латте", 250, 1))))
            .toList();

    // 4. Месяц перебором
    comparisons = 0;
    int monthSearch = manyOrders.stream()
            .mapToInt(order -> discountBySearch(order, manyGuests))
            .sum();
    IO.println("месяц перебором: скидок " + monthSearch + " ₽, сравнений: " + comparisons);

    // 5. Индекс: имя → гость, один проход по гостям
    Map<String, Guest> cards = guests.stream()
            .collect(Collectors.toMap(Guest::name, Function.identity()));
    IO.println(cards.get("Вера"));
    IO.println(cards.get("Егор"));

    // 6. День по индексу — ответ тот же
    int dayIndex = orders.stream()
            .mapToInt(order -> discountByIndex(order, cards))
            .sum();
    IO.println("скидок за день: " + dayIndex + " ₽, обращений к индексу: " + lookups);

    // 7. Месяц по индексу
    Map<String, Guest> manyCards = manyGuests.stream()
            .collect(Collectors.toMap(Guest::name, Function.identity()));
    lookups = 0;
    int monthIndex = manyOrders.stream()
            .mapToInt(order -> discountByIndex(order, manyCards))
            .sum();
    IO.println("месяц по индексу: скидок " + monthIndex + " ₽, обращений к индексу: " + lookups);

    // 8. Нужен один процент — индекс «имя → скидка» и getOrDefault
    Map<String, Integer> percentByName = guests.stream()
            .collect(Collectors.toMap(Guest::name, Guest::discount));
    List<Integer> percents = orders.stream()
            .map(order -> percentByName.getOrDefault(order.guest(), 0))
            .toList();
    IO.println(percents);

    // 9. Гости без карты — кому её предложить
    List<String> noCard = orders.stream()
            .map(Order::guest)
            .filter(name -> !cards.containsKey(name))
            .distinct()
            .toList();
    IO.println(noCard);

    // Сделай руками — раскомментируй и запусти:
    // IO.println(cards.get("Егор").discount());   // NullPointerException
}
```

Сделай руками:

1. Запусти файл. Первая строка — `[43, 15, 22, 41, 17, 65, 0, 89, 33, 0]`;
   дальше — `сравнений: 33`, `сравнений: 5005000`, потом
   `обращений к индексу: 10` и `обращений к индексу: 10000`.
2. Раскомментируй последнюю строку `main` — с `cards.get("Егор")` —
   и увидишь `NullPointerException`. Верни комментарий.
3. Добавь в `guests()` после Зои вторую Анну:
   `new Guest("Анна", "К-107", 5)` (не забудь запятую после Зои).
   Запуск упадёт на блоке `// 5.` с `Duplicate key Анна`. Убери её.
4. В блоке `// 3.` замени `"гость " + (i % 1_000 + 1)` на
   `"гость без карты"`. Перебор сделает 10 000 000 сравнений — ровно
   n · m, у индекса по-прежнему 10 000 обращений. Верни как было.
5. В блоке `// 5.` замени `Function.identity()` на `guest -> guest` —
   вывод не изменится. Верни как было.
