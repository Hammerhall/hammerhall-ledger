# `filter`, `map` и `Optional` без страха

> «Стримы по шагам» · статья 2 · читать минут 20
>
> **Для кого.** Ты прочитал [статью 1](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop):
> знаешь, из каких частей состоит конвейер, читаешь `filter` и `map`
> с лямбдой внутри и помнишь, что без конечной операции ничего
> не происходит.
>
> **Что будет.** Лямбды как следует — и их короткая форма
> `Order::guest`; как найти первый подходящий заказ, проверить «есть ли
> хоть один» и почему конвейер умеет остановиться раньше; что такое
> `Optional`, как достать из него ответ и почему `orElse` иногда
> работает зря.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем `Optional`

Хозяйка «Наковальни» спрашивает: с какого заказа начала день Вера?
А Иван?

На курсе такой поиск пишут методом с циклом:

```java
/** Первый заказ гостя — циклом. Гостя не было — null. */
Order firstOrderByLoop(List<Order> orders, String guest) {
    for (Order order : orders) {
        if (order.guest().equals(guest)) {
            return order;                                // нашёлся — сразу выходим
        }
    }
    return null;                                         // не нашёлся — «ничего»
}
```

Для Веры метод вернёт заказ 3. Ивана сегодня не было, и метод вернёт
`null` — «никакого объекта». По типу `Order` этого не видно: метод
обещает заказ, а приходит пустота. Тот, кто вызывает метод, о ней
легко забудет:

```java
IO.println(firstOrderByLoop(orders, "Иван").number());
```

```
Exception in thread "main" java.lang.NullPointerException: Cannot invoke "Coffee$Order.number()" because the return value of "Coffee.firstOrderByLoop(java.util.List, String)" is null
```

«Не могу вызвать `number()`: метод вернул `null`». `Coffee$Order` —
так Java называет запись `Order` из файла `Coffee.java`. Ошибка
всплывает не при компиляции, а при запуске — и на работе обычно
не в тот день, когда код писали.

Тот же поиск стримом:

```java
/** Первый заказ гостя — стримом. Гостя не было — пустой Optional. */
Optional<Order> firstOrderOf(List<Order> orders, String guest) {
    return orders.stream()
            .filter(order -> order.guest().equals(guest))  // заказы этого гостя
            .findFirst();                                  // первый из них, если есть
}
```

`findFirst()` — конечная операция: она отдаёт первый элемент, который
доехал до конца конвейера. Но отдаёт не `Order`, а `Optional<Order>` —
коробку, в которой заказ или есть, или нет:

```java
Optional<Order> vera = firstOrderOf(orders, "Вера");
Optional<Order> ivan = firstOrderOf(orders, "Иван");
IO.println(vera);
IO.println(ivan);
```

```
Optional[Order[number=3, guest=Вера, items=[Item[name=капучино, price=220, qty=1]]]]
Optional.empty
```

🔑 `Optional` говорит «ответа может не быть» прямо в типе. `null`
молчит до первого падения, а пустую коробку компилятор не даст
принять за заказ — это будет в части 3.

В этой статье — лямбды как следует, поиск с ранней остановкой и всё,
что нужно, чтобы достать ответ из `Optional`. Пример — те же десять
заказов кофейни, что в статье 1.

---

## Часть 1. Лямбда как следует

### Параметр, тело, типы

Помнишь из статьи 1: лямбда — функция без имени, слева от стрелки —
параметр, справа — что вернуть. Разберём лямбду из `firstOrderOf`:

```java
order -> order.guest().equals(guest)
```

* `order` — **параметр**. Тип не написан: Java видит, что по стриму
  едут заказы, и сама понимает, что `order` — это `Order`. Это
  называют **выводом типов**. Тип можно написать и явно:
  `(Order order) -> …`. Когда без этого не обойтись — в статье 3.
* `order.guest().equals(guest)` — **тело**. Если это одно выражение,
  его значение и есть ответ, `return` не нужен. Нужно несколько
  шагов — тело берут в фигурные скобки и пишут `return`, как
  в статье 1 с печатью.
* Параметров бывает и ноль: `() -> nobody()` — функция без входа,
  которая что-то выдаёт. Метод `nobody()` и эта лямбда появятся
  в части 4.

И ещё: справа от стрелки стоит `guest`, который объявлен не в лямбде,
а снаружи, — это параметр метода. Так можно, но с условием; о нём —
в конце части.

### Лямбда — это значение

Лямбду можно положить в переменную, как число или строку. Помнишь
проблему из статьи 1: условие «от 500 ₽» в каждом цикле писали
заново. Теперь его можно назвать один раз:

```java
Predicate<Order> big = order -> order.total() >= 500;
long bigCount = orders.stream().filter(big).count();
List<String> guests = orders.stream()
        .filter(big)
        .map(order -> order.guest())
        .toList();
IO.println(bigCount + " " + guests);
```

```
4 [Глеб, Дина, Вера, Борис]
```

`Predicate<Order>` — тип переменной: «условие на заказ». Функцию,
которая отвечает «да» или «нет», называют **предикатом**; `filter`
ждёт именно его. У других лямбд — другие типы:

* лямбда в `map` — **функция**, `Function<Order, String>`: берёт заказ,
  отдаёт строку;
* лямбда без параметров, которая что-то выдаёт, — `Supplier`,
  «поставщик»;
* лямбда, которая что-то делает и ничего не возвращает, — `Consumer`.

Все они лежат в пакете `java.util.function`. Наизусть учить не нужно:
в конвейере тип Java подбирает сама, а имя типа пишешь, только когда
кладёшь лямбду в переменную.

### Ссылка на метод

Лямбда `order -> order.guest()` только вызывает у заказа один метод.
Для такого случая есть запись короче — **ссылка на метод**:
`Order::guest`. Читается «метод `guest` у `Order`»: Java сама возьмёт
заказ, который едет по конвейеру, и вызовет у него `guest()`.

Бывает и вторая форма: `IO::println`. Здесь элемент передают методу
аргументом — то же, что `x -> IO.println(x)`.

Ссылка годится, только когда лямбда — ровно один вызов метода и его
ответ подходит по типу. `order -> order.total() >= 500` ссылкой
не записать: кроме вызова, там сравнение. Попробуем всё-таки:

```java
Predicate<Order> big = Order::total;
```

```
Coffee.java:73: error: incompatible types: bad return type in method reference
    Predicate<Order> big = Order::total;
                           ^
    int cannot be converted to boolean
1 error
error: compilation failed
```

«Неверный тип результата у ссылки на метод: `int` не превратить
в `boolean`». Предикат должен ответить «да» или «нет», а `total()`
отвечает числом. Не записать ссылкой и `order.guest().equals(guest)`:
там два вызова и значение снаружи. Не получается ссылка или читается
хуже лямбды — пиши лямбду, это не ошибка.

### Переменные снаружи лямбды

⚠️ Лямбда в `firstOrderOf` берёт `guest` — параметр метода. Это
разрешено, пока переменную после первого присваивания не меняют.
Допишем в метод строку, которая убирает пробелы вокруг имени:

```java
Optional<Order> firstOrderOf(List<Order> orders, String guest) {
    guest = guest.trim();                                // поменяли параметр
    return orders.stream()
            .filter(order -> order.guest().equals(guest))  // заказы этого гостя
            .findFirst();                                  // первый из них, если есть
}
```

```
Coffee.java:53: error: local variables referenced from a lambda expression must be final or effectively final
            .filter(order -> order.guest().equals(guest))  // заказы этого гостя
                                                  ^
1 error
error: compilation failed
```

«Переменные, которые использует лямбда, должны быть `final` или
фактически `final`». **Фактически final** (effectively final) —
переменная, которой после первого присваивания ничего не присваивают,
даже если слово `final` не написано. Лямбда может выполниться позже,
чем строка, где её написали, — помнишь ленивость, — и значение, которое
она видит, должно быть одно. Нужно другое значение — заведи новую
переменную: `String name = guest.trim();`, и в лямбде пиши `name`.

---

## Часть 2. Найти, проверить, остановиться

### findFirst — первый, кто доехал

Поставим в `filter` печать, как в статье 1, и поищем первый заказ
Веры:

```java
Optional<Order> found = orders.stream()
        .filter(order -> {
            IO.println("проверяю заказ " + order.number());
            return order.guest().equals("Вера");
        })
        .findFirst();
IO.println(found.isPresent());
```

```
проверяю заказ 1
проверяю заказ 2
проверяю заказ 3
true
```

Заказы с 4-го по 10-й не проверены вовсе. Помнишь из статьи 1: каждый
элемент проходит конвейер целиком, по одному. Заказ 3 доехал до
`findFirst`, ответ готов — брать с ленты следующий незачем.

Так работают операции с **коротким замыканием** (short-circuiting):
чтобы ответить, им не обязательно смотреть все элементы. Ты знаешь
это по `&&` в `if`: если слева `false`, правую часть Java уже
не вычисляет.

### anyMatch, allMatch, noneMatch — «да» или «нет»

Часто нужен не сам заказ, а ответ на вопрос. Для этого три конечные
операции, и каждая принимает предикат:

```java
boolean any800 = orders.stream().anyMatch(order -> order.total() >= 800);
boolean all150 = orders.stream().allMatch(order -> order.total() >= 150);
boolean none1000 = orders.stream().noneMatch(order -> order.total() >= 1000);
IO.println(any800 + " " + all150 + " " + none1000);
```

```
true true true
```

* `anyMatch` — «есть ли хотя бы один»: был ли заказ от 800 ₽? Да,
  заказ 4 на 820 ₽. На нём `anyMatch` и остановится.
* `allMatch` — «все ли»: все ли заказы от 150 ₽? Да. Ему пришлось
  проверить все десять: остановиться он может только на первом «нет».
* `noneMatch` — «ни одного»: нет ли заказов от 1000 ₽? Нет — тоже
  после всех десяти.

💡 В интернете ты увидишь `filter(…).count() > 0`. Ответ тот же, но
`count()` пересчитает все подходящие заказы, а `anyMatch` остановится
на первом — и прямо говорит, о чём вопрос.

Теперь крайний случай — гость, которого не было:

```java
boolean ivanAll = orders.stream()
        .filter(order -> order.guest().equals("Иван"))
        .allMatch(order -> order.total() >= 1000);
IO.println("все заказы Ивана от 1000 ₽: " + ivanAll);
```

```
все заказы Ивана от 1000 ₽: true
```

Заказов у Ивана нет — а ответ «да». Документация Java так и пишет:
на пустом стриме `allMatch` и `noneMatch` отвечают `true`, а
`anyMatch` — `false`. Ни один заказ правило не нарушил — значит,
правило выполнено. Проверяешь «все ли» — подумай, какой ответ нужен,
когда проверять нечего.

### limit — взять несколько и остановиться

`limit(n)` — промежуточная операция: пропускает дальше первые `n`
элементов и закрывает ленту. Имена первых двух гостей с заказом
от 500 ₽:

```java
List<String> firstTwo = orders.stream()
        .filter(order -> {
            IO.println("filter: заказ " + order.number());
            return order.total() >= 500;
        })
        .map(Order::guest)
        .limit(2)
        .toList();
IO.println(firstTwo);
```

```
filter: заказ 1
filter: заказ 2
filter: заказ 3
filter: заказ 4
filter: заказ 5
filter: заказ 6
[Глеб, Дина]
```

Глеб — заказ 4, Дина — заказ 6. Двое есть, и заказы 7–10 `filter`
уже не видит. `limit` считает то, что доехало до него, а не элементы
источника. Он стоит после `filter` — значит, «первые два крупных
заказа», а не «крупные среди первых двух».

🔑 Конвейер берёт элементы по одному и останавливается, как только
ответ известен. Поэтому `findFirst`, `anyMatch` и `limit` дёшевы даже
на длинном списке: работы ровно столько, сколько нужно для ответа.

---

## Часть 3. `Optional`: коробка, в которой может быть пусто

### Что внутри

**`Optional<T>`** — обёртка, внутри которой лежит одно значение типа
`T` или ничего; `T` — тип содержимого; у нас это `Order`, а коробка —
`Optional<Order>`. Возьмём `vera` и `ivan` из начала статьи — первые
заказы Веры и Ивана:

```java
IO.println(vera.isPresent() + " " + ivan.isEmpty());
```

```
true true
```

`isPresent()` — «внутри что-то есть», `isEmpty()` — «пусто».
`isEmpty()` появился в Java 11; в старом коде вместо него пишут
`!isPresent()`.

### Компилятор не даст забыть

С `null` ошибка ждала запуска. С `Optional` её ловит компилятор:

```java
IO.println(ivan.number());                              // не скомпилируется
```

```
Coffee.java:141: error: cannot find symbol
    IO.println(ivan.number());                              // не скомпилируется
                   ^
  symbol:   method number()
  location: variable ivan of type Optional<Order>
1 error
error: compilation failed
```

«Не найден метод `number()` у переменной `ivan` типа
`Optional<Order>`». У коробки нет номера заказа. Чтобы его получить,
нужно решить, что делать, если коробка пуста, — и компилятор
заставляет это решение принять.

### ⚠️ get() без проверки

В интернете ты увидишь `findFirst().get()`. `get()` достаёт значение,
а если коробка пуста — бросает исключение:

```java
ivan.get();                                             // NoSuchElementException
```

```
Exception in thread "main" java.util.NoSuchElementException: No value present
```

«Значения нет». По сути это та же ошибка, что с `null`, только под
другим именем: компилятор пропустил, упало при запуске. `get()` без
проверки — `Optional` без пользы. Документация Java сама советует
вместо `get()` писать `orElseThrow()` — он и другие способы в части 4.

### map у Optional

У `Optional` есть свой `map` — как у стрима, только для одного
элемента или ни одного. Значение есть — `map` его превращает, пусто —
оставляет пусто:

```java
IO.println(vera.map(Order::total));
IO.println(ivan.map(Order::total));
```

```
Optional[220]
Optional.empty
```

Сумма первого заказа Веры — 220 ₽, и она тоже в коробке: будь коробка
пустой, суммы бы не было. Проверять пустоту по дороге не нужно —
`map` делает это сам.

💡 Документация Java говорит, для чего `Optional` придуман: прежде
всего — для ответа метода, когда «результата нет» — нормальный исход,
а `null` легко приведёт к ошибке. И добавляет: переменная типа
`Optional` сама никогда не должна быть `null`. Поэтому `Optional`
пишут в тип ответа метода, а не в поле записи и не в параметр.

---

## Часть 4. Как достать ответ

### orElse — запасное значение

Сумма первого заказа гостя, а если гостя не было — ноль:

```java
int veraTotal = vera.map(Order::total).orElse(0);
int ivanTotal = ivan.map(Order::total).orElse(0);
IO.println(veraTotal + " " + ivanTotal);
```

```
220 0
```

`orElse(x)` — «значение, а если пусто — `x`». После него коробки нет:
в руках обычное число.

### ifPresent — сделать, если есть

```java
vera.ifPresent(order -> IO.println("у Веры заказ " + order.number()));
ivan.ifPresent(order -> IO.println("у Ивана заказ " + order.number()));
```

```
у Веры заказ 3
```

Вторая строка не напечаталась: коробка Ивана пуста, и лямбду никто
не вызвал.

### orElseThrow — пусто значит ошибка

Бывает, что пустой ответ — ошибка программы: заказ обязан быть,
и без него работать дальше нельзя. Тогда — `orElseThrow()`:

```java
Order checked = vera.orElseThrow();
```

Значение есть — получаешь его. Пусто — `NoSuchElementException`, как
у `get()`. Разница в имени: `orElseThrow` прямо говорит, что здесь
может вылететь исключение, а `get` выглядит безобидно. Нужно своё
исключение с понятным текстом — передай лямбду, которая его создаёт:

```java
ivan.orElseThrow(() -> new IllegalArgumentException("гостя Иван сегодня не было"));
```

```
Exception in thread "main" java.lang.IllegalArgumentException: гостя Иван сегодня не было
```

### ⚠️ orElse считает запасной ответ всегда

Чей заказ номер 7? Запасной ответ даёт метод `nobody()`. Он печатает
строку — чтобы видеть, когда его вызывают:

```java
String nobody() {
    IO.println("  (вызван nobody)");
    return "никто";
}
```

Спросим дважды — с `orElse` и с `orElseGet`:

```java
String eager = orders.stream()
        .filter(order -> order.number() == 7)
        .map(Order::guest)
        .findFirst()
        .orElse(nobody());
IO.println("orElse: " + eager);
String lazy = orders.stream()
        .filter(order -> order.number() == 7)
        .map(Order::guest)
        .findFirst()
        .orElseGet(() -> nobody());
IO.println("orElseGet: " + lazy);
```

```
  (вызван nobody)
orElse: Егор
orElseGet: Егор
```

Заказ 7 есть, это Егор. Но в первом случае `nobody()` всё равно
вызван. `Optional` тут ни при чём — так устроена Java: аргументы
метода вычисляются до вызова. Чтобы передать значение в `orElse`, Java
сначала выполнит `nobody()`, и только потом `orElse` посмотрит, нужно
ли оно.

`orElseGet` принимает не значение, а функцию без параметров —
`() -> nobody()`. Её вызывают, только если коробка пуста.

В интернете ты увидишь `orElse(createDefault())` и
`orElse(loadFromDb())`. Пока запасной ответ — готовое значение вроде
`0` или `"никто"`, разницы нет. Если это запрос в базу, запись в лог
или новый объект — `orElse` выполнит это каждый раз, даже когда
значение нашлось. Тогда пиши `orElseGet`.

### Шпаргалка

| что нужно | метод |
|---|---|
| запасное значение, готовое | `orElse(0)` |
| запасное значение, которое дорого получить | `orElseGet(() -> …)` |
| пусто — значит ошибка | `orElseThrow()` |
| сделать что-то, если есть | `ifPresent(…)` |
| превратить значение, не открывая коробку | `map(…)` |
| `get()` | не нужен: есть `orElseThrow()` |

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Метод поиска вернул `null`, и программа упала при запуске. Почему
   с `Optional` такая ошибка видна раньше — и кто её показывает?
2. Чем `Order::guest` отличается от `order -> order.guest()`? Почему
   `Predicate<Order> big = Order::total;` не компилируется?
3. Лямбда использует параметр метода, а строкой выше ему присвоили
   новое значение. Что скажет компилятор и как это исправить?
4. Сколько заказов проверит `findFirst`, когда ищет Веру? Почему
   не все десять?
5. Что ответят `allMatch` и `anyMatch`, если заказов у гостя нет
   ни одного?
6. В примере с двумя гостями `limit(2)` стоит после `filter`. Что
   изменится в ответе, если поставить его перед `filter`?
7. Чем опасен `get()` и что писать вместо него?
8. Почему `orElse(nobody())` вызывает `nobody()`, даже когда значение
   есть? Когда это важно и что писать вместо?

---

## Реши в кузнице

Задачи на то же самое — `findFirst`, `anyMatch`, `limit`, лямбды
и ссылки на методы — в кузнице Stream Forge на платформе Hammerhall,
на фильмах. Первые задачи бесплатны, нужен только вход:

* [«Витрина видеосалона»](https://hammerhall.io/forge/stream-forge/task/MovCode0003);
* [«Долгожданная премьера»](https://hammerhall.io/forge/stream-forge/task/MovCode0005);
* [«Ни рыба ни мясо»](https://hammerhall.io/forge/stream-forge/task/MovCode0007);
* [«Найти все фильмы заданного жанра»](https://hammerhall.io/forge/stream-forge/task/MovCode0014);
* [«Проверить, есть ли в базе хотя бы один фильм указанного жанра»](https://hammerhall.io/forge/stream-forge/task/MovCode0013).

## Что дальше

Статья 3 — сортировка: `sorted`, компараторы `Comparator.comparing`
и `thenComparing`, ловушка `reversed` — и `min` с `max`, которые тоже
отвечают `Optional`.

## Первоисточники

* [Class Optional — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Optional.html) —
  `orElse`, `orElseGet`, `orElseThrow`, `ifPresent`, `map`; примечание
  о том, для чего `Optional` нужен.
* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  `findFirst`, `anyMatch`, `allMatch`, `noneMatch` (и что они отвечают
  на пустом стриме), `limit`.
* [Package java.util.function — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/function/package-summary.html) —
  `Predicate`, `Function`, `Supplier`, `Consumer`: какие бывают
  лямбды.
* [Java Language Specification, глава 15 — Java SE 25](https://docs.oracle.com/javase/specs/jls/se25/html/jls-15.html#jls-15.27) —
  разделы 15.27 «Lambda Expressions» и 15.13 «Method Reference
  Expressions»: точные правила, в том числе про «фактически final».

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Записи стоят прямо вверху файла, а методы — `orders()`,
`firstOrderOf()`, `main` и другие — без класса вокруг: в Java 25 такой
файл сам становится классом, а `void main()` без `public static` и без
параметров — точкой входа. Сохрани файл как `Coffee.java` и запусти
из его папки:

```bash
java Coffee.java
```

Если вместо русских букв в выводе вопросы или кракозябры, запусти
с явной кодировкой — аргумент в кавычках, так его поймёт и PowerShell:
`java "-Dstdout.encoding=UTF-8" Coffee.java`; в командной строке Windows
перед этим выполни `chcp 65001`.

```java
// Coffee.java — учебный пример статьи 2 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.List;
import java.util.Optional;
import java.util.function.Predicate;

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

/** Первый заказ гостя — циклом. Гостя не было — null. */
Order firstOrderByLoop(List<Order> orders, String guest) {
    for (Order order : orders) {
        if (order.guest().equals(guest)) {
            return order;                                // нашёлся — сразу выходим
        }
    }
    return null;                                         // не нашёлся — «ничего»
}

/** Первый заказ гостя — стримом. Гостя не было — пустой Optional. */
Optional<Order> firstOrderOf(List<Order> orders, String guest) {
    return orders.stream()
            .filter(order -> order.guest().equals(guest))  // заказы этого гостя
            .findFirst();                                  // первый из них, если есть
}

/** Запасной ответ. Печатает строку, чтобы было видно, когда его вызывают. */
String nobody() {
    IO.println("  (вызван nobody)");
    return "никто";
}

void main() {
    List<Order> orders = orders();

    // 1. Первый заказ гостя: цикл отвечает заказом или null, стрим — Optional
    IO.println("циклом: заказ " + firstOrderByLoop(orders, "Вера").number());
    Optional<Order> vera = firstOrderOf(orders, "Вера");
    Optional<Order> ivan = firstOrderOf(orders, "Иван");
    IO.println(vera);
    IO.println(ivan);

    // 2. Условие — в переменной, ссылка на метод — вместо лямбды
    Predicate<Order> big = order -> order.total() >= 500;
    long bigCount = orders.stream().filter(big).count();
    List<String> guests = orders.stream()
            .filter(big)
            .map(order -> order.guest())
            .toList();
    IO.println(bigCount + " " + guests);

    // 3. findFirst: конвейер останавливается на первом подходящем
    Optional<Order> found = orders.stream()
            .filter(order -> {
                IO.println("проверяю заказ " + order.number());
                return order.guest().equals("Вера");
            })
            .findFirst();
    IO.println(found.isPresent());

    // 4. anyMatch, allMatch, noneMatch — ответ «да» или «нет»
    boolean any800 = orders.stream().anyMatch(order -> order.total() >= 800);
    boolean all150 = orders.stream().allMatch(order -> order.total() >= 150);
    boolean none1000 = orders.stream().noneMatch(order -> order.total() >= 1000);
    IO.println(any800 + " " + all150 + " " + none1000);
    boolean ivanAll = orders.stream()
            .filter(order -> order.guest().equals("Иван"))
            .allMatch(order -> order.total() >= 1000);
    IO.println("все заказы Ивана от 1000 ₽: " + ivanAll);

    // 5. limit: двух гостей хватит, дальше конвейер не смотрит
    List<String> firstTwo = orders.stream()
            .filter(order -> {
                IO.println("filter: заказ " + order.number());
                return order.total() >= 500;
            })
            .map(Order::guest)
            .limit(2)
            .toList();
    IO.println(firstTwo);

    // 6. Что в коробке: isPresent, isEmpty, map
    IO.println(vera.isPresent() + " " + ivan.isEmpty());
    IO.println(vera.map(Order::total));
    IO.println(ivan.map(Order::total));

    // 7. Достать ответ: orElse, ifPresent, orElseThrow
    int veraTotal = vera.map(Order::total).orElse(0);
    int ivanTotal = ivan.map(Order::total).orElse(0);
    IO.println(veraTotal + " " + ivanTotal);
    vera.ifPresent(order -> IO.println("у Веры заказ " + order.number()));
    ivan.ifPresent(order -> IO.println("у Ивана заказ " + order.number()));
    Order checked = vera.orElseThrow();
    IO.println("проверен заказ " + checked.number());

    // 8. orElse вычисляет запасной ответ всегда, orElseGet — только когда пусто
    String eager = orders.stream()
            .filter(order -> order.number() == 7)
            .map(Order::guest)
            .findFirst()
            .orElse(nobody());
    IO.println("orElse: " + eager);
    String lazy = orders.stream()
            .filter(order -> order.number() == 7)
            .map(Order::guest)
            .findFirst()
            .orElseGet(() -> nobody());
    IO.println("orElseGet: " + lazy);

    // Сделай руками — раскомментируй по одной строке и запусти:
    // IO.println(firstOrderByLoop(orders, "Иван").number());  // NullPointerException
    // IO.println(ivan.number());                              // не скомпилируется
    // ivan.get();                                             // NoSuchElementException
    // ivan.orElseThrow(() -> new IllegalArgumentException("гостя Иван сегодня не было"));
}
```

Сделай руками:

1. Запусти файл. Первые строки — `циклом: заказ 3`, коробка с заказом
   Веры и `Optional.empty`.
2. Найди в выводе три строки «проверяю заказ»: `findFirst` остановился
   на заказе 3.
3. В блоке `// 5.` замени `limit(2)` на `limit(5)`. Строк «filter:
   заказ» станет десять, а гостей — четыре: пятого крупного заказа нет,
   и конвейеру пришлось дойти до конца. Верни как было.
4. В блоке `// 8.` замени `7` на `12` в обоих конвейерах. Теперь
   `nobody()` вызовется дважды, и оба ответа — `никто`. Верни как было.
5. Раскомментируй по одной строке в конце `main`: увидишь
   `NullPointerException`, ошибку компиляции, `NoSuchElementException`
   и `IllegalArgumentException` с твоим текстом. Каждый раз возвращай
   комментарий.
6. В `firstOrderOf` первой строкой допиши `guest = guest.trim();`
   и прочитай ошибку компилятора. Потом сделай, как в части 1: новая
   переменная `name` — и в лямбде `name`.
