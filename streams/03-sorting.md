# Сортировка: компараторы и ловушка `reversed`

> «Стримы по шагам» · статья 3 · читать минут 20
>
> **Для кого.** Ты прочитал [статью 1](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop)
> и [статью 2](https://hammerhall.io/ledger/streams/2-filter-map-optional): знаешь, как
> устроен конвейер, читаешь лямбды и ссылки на методы вроде
> `Order::guest` и умеешь достать ответ из `Optional`.
>
> **Что будет.** Как стрим сортирует строки и почему «ё» оказывается
> после «я»; что такое компаратор и как собрать его из
> `Comparator.comparing`, `thenComparing` и `reversed` — и где
> `reversed` разворачивает не то, что ты хотел; что делать с `null`
> в списке и как найти наибольшее без сортировки.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи
> на стримы — в кузнице Stream Forge на платформе; здесь — то, что
> нужно знать, чтобы их решать. Примеры учебные: каждый запускается
> одним файлом.

---

## Зачем компараторы

Хозяйке «Наковальни» нужны три списка: меню на доску — по алфавиту;
отчёт — три самых крупных заказа дня; и гости по алфавиту, а у каждого
гостя — его заказы от крупного к мелкому.

На курсе сортируют `Collections.sort(list)`: метод переставляет
элементы прямо в списке. С меню так не выйдет:

```java
List<String> menu = List.of("раф", "латте", "ёлочный раф", "Эспрессо-тоник", "американо");
Collections.sort(menu);
```

```
Exception in thread "main" java.lang.UnsupportedOperationException
```

Помнишь из статьи 1: список из `toList()` неизменяемый. Из `List.of` —
тоже: ни добавить, ни переставить. Можно скопировать меню в `ArrayList`
и отсортировать копию, но это опять служебные строки.

Стрим сортирует по дороге: `sorted()` — промежуточная операция, она
отдаёт элементы дальше в нужном порядке и источник не трогает.

Со строками Java знает, кто раньше. С заказами — нет: какой заказ
«меньше», 4-й или 6-й? По номеру, по сумме, по имени гостя? Правило
«кто из двух раньше» придётся дать самому. Такое правило называется
**компаратором**, и вся статья — о том, как его записать.

🔑 Сортировка — это ответ на вопрос «кто из двух раньше». Всё
остальное — способы записать этот ответ.

---

## Часть 1. sorted() и естественный порядок

### Строки сортируются по кодам, а не по алфавиту

```java
IO.println(menu.stream().sorted().toList());
```

```
[Эспрессо-тоник, американо, латте, раф, ёлочный раф]
```

Два сюрприза: «Эспрессо-тоник» первым, хотя «Э» в конце алфавита,
а «ёлочный раф» — последним.

`sorted()` без аргументов сортирует в **естественном порядке** — том,
который класс задаёт сам: числа — по возрастанию, строки — посимвольно,
по кодам символов в таблице Unicode. Документация `String.compareTo`
так и пишет: сравнение основано на Unicode-значении каждого символа.
Коды русских букв:

```java
IO.println((int) 'Э' + " " + (int) 'а' + " " + (int) 'я' + " " + (int) 'ё');
```

```
1069 1072 1103 1105
```

Все заглавные — А–Я, коды 1040–1071 — идут раньше всех строчных:
а–я, 1072–1103. А «ё» в этот ряд не попала: её код 1105, после «я».
Заглавная «Ё» — наоборот, 1025, раньше «А». С латиницей то же:
«Zebra» встанет раньше «apple».

### 💡 По-русски — Collator

Для текста на человеческом языке в Java есть **`Collator`** —
сравнение строк по правилам языка, из пакета `java.text`. Язык задают
так: `Locale.of("ru")` — «русский». `Collator` сам компаратор, его можно
отдать в `sorted`:

```java
Collator russian = Collator.getInstance(Locale.of("ru"));
IO.println(menu.stream().sorted(russian).toList());
```

```
[американо, ёлочный раф, латте, раф, Эспрессо-тоник]
```

«ё» встала рядом с «е», заглавная буква больше не уводит слово в начало.
Для меню и имён на экране — то, что нужно. Для кодов, ключей и всего,
что читает программа, а не человек, оставь естественный порядок.

### ⚠️ У заказа естественного порядка нет

```java
orders.stream().sorted().toList();                      // ClassCastException
```

```
Exception in thread "main" java.lang.ClassCastException: class Coffee$Order cannot be cast to class java.lang.Comparable (Coffee$Order is in unnamed module of loader com.sun.tools.javac.launcher.MemoryClassLoader @2c78324b; java.lang.Comparable is in module java.base of loader 'bootstrap')
```

«`Order` нельзя привести к `Comparable`»; число после `@` у тебя будет
другим. **`Comparable`** — интерфейс
«умею сравниваться сам»: его реализуют `String`, `Integer` и другие
классы с естественным порядком. Запись `Order` его не реализует — и не
должна: одного «правильного» порядка у заказов нет.

Заметь: код скомпилировался и упал только при запуске, когда конечная
операция запустила конвейер. Компилятор не мешает: `sorted()` есть
у стрима любых элементов, а умеют ли они сравниваться, выясняется
только при запуске. Документация `sorted()` так и предупреждает.

---

## Часть 2. Компаратор

### Правило «кто раньше»

В Java компаратор заказов — объект типа `Comparator<Order>`, функция
от двух элементов. Она отвечает отрицательным числом, если первый
раньше, нулём, если они равны, и положительным, если первый позже.
Её можно записать лямбдой с двумя параметрами — их берут в скобки:

```java
List<Integer> byLambda = orders.stream()
        .sorted((a, b) -> Integer.compare(a.total(), b.total()))
        .map(Order::number)
        .toList();
IO.println(byLambda);
```

```
[7, 5, 10, 3, 2, 1, 6, 9, 4, 8]
```

`Integer.compare(x, y)` как раз отвечает «минус, ноль, плюс» для двух
чисел. Номера заказов — от самого скромного, 7-го на 150 ₽, к самому
крупному, 8-му на 890 ₽.

⚠️ В интернете ты увидишь `(a, b) -> a.total() - b.total()`: разность
тоже бывает «минус, ноль, плюс». Для сумм кофейни это сработает, но
на больших числах вычитание переполняет `int`: 2 000 000 000 минус
−2 000 000 000 даёт −294 967 296, и порядок ломается. `Integer.compare`
сравнивает, ничего не вычитая, — пиши его.

### comparing и comparingInt

Писать сравнение руками не нужно. `Comparator.comparingInt` собирает
компаратор сам — ему нужно сказать только, откуда брать число:

```java
List<Integer> byTotal = orders.stream()
        .sorted(Comparator.comparingInt(Order::total))
        .map(Order::number)
        .toList();
IO.println(byTotal);
```

```
[7, 5, 10, 3, 2, 1, 6, 9, 4, 8]
```

Читается «сравнивай по сумме», ответ тот же. Для ключей-объектов —
строк и всего, что умеет сравниваться само, — есть
`Comparator.comparing`: `Comparator.comparing(Order::guest)` —
«сравнивай по имени гостя».

💡 Почему для суммы `comparingInt`, а не `comparing(Order::total)`?
Тот тоже скомпилируется и даст тот же порядок. Но `comparing` работает
с объектами, а `int` — не объект, и Java на каждом сравнении будет
**упаковывать** число в объект `Integer` (boxing). `comparingInt`
сравнивает числа как есть. Для `long` и `double` есть `comparingLong`
и `comparingDouble`.

### Сортировка устойчивая

Отсортируем по гостю. Подпись заказа «гость сумма» положим
в переменную — помнишь из статьи 2, лямбда — это значение:

```java
Function<Order, String> label = order -> order.guest() + " " + order.total();
Comparator<Order> byGuest = Comparator.comparing(Order::guest);
IO.println(orders.stream().sorted(byGuest).map(label).toList());
```

```
[Анна 430, Анна 170, Борис 300, Борис 660, Вера 220, Вера 890, Глеб 820, Дина 650, Егор 150, Жанна 200]
```

Гости — по алфавиту. А у Анны сначала 430, потом 170: заказы 1 и 5
остались в том порядке, в каком лежали в списке. Это не случайность:
сортировка в стриме **устойчивая** — элементы, равные для компаратора,
сохраняют порядок источника. Документация обещает это для стримов
с порядком обхода; у стрима из списка он есть — порядок элементов
в списке.

### thenComparing — второй ключ

Нужен у одного гостя другой порядок — добавь второй ключ. Его
спрашивают, только когда первый сказал «равны»:

```java
Comparator<Order> byGuestThenTotal = Comparator.comparing(Order::guest)
        .thenComparingInt(Order::total);
IO.println(orders.stream().sorted(byGuestThenTotal).map(label).toList());
```

```
[Анна 170, Анна 430, Борис 300, Борис 660, Вера 220, Вера 890, Глеб 820, Дина 650, Егор 150, Жанна 200]
```

Как в телефонной книге: сначала по фамилии, у однофамильцев — по
имени. `thenComparingInt` — это `thenComparing` для числового ключа.

Хозяйке нужно наоборот: у гостя — от крупного к мелкому. Тут
и начинается `reversed`.

---

## Часть 3. reversed и его ловушка

### reversed — в обратную сторону

`reversed()` — метод компаратора: он возвращает компаратор с обратным
порядком. Три самых крупных заказа — для отчёта хозяйки:

```java
List<String> topThree = orders.stream()
        .sorted(Comparator.comparingInt(Order::total).reversed())
        .limit(3)
        .map(label)
        .toList();
IO.println(topThree);
```

```
[Вера 890, Глеб 820, Борис 660]
```

`reversed()` поставил крупные заказы вперёд, а `limit(3)` из статьи 2
взял первые три. Вот и второй список хозяйки.

### ⚠️ reversed в конце разворачивает всю цепочку

Кажется, для «гости по алфавиту, у гостя — от крупного» достаточно
дописать `reversed()` после второго ключа:

```java
Comparator<Order> wrong = Comparator.comparing(Order::guest)
        .thenComparingInt(Order::total)
        .reversed();
IO.println(orders.stream().sorted(wrong).map(label).toList());
```

```
[Жанна 200, Егор 150, Дина 650, Глеб 820, Вера 890, Вера 220, Борис 660, Борис 300, Анна 430, Анна 170]
```

Суммы у гостя — от крупной, как хотели. Но и гости поехали от Жанны
к Анне.

Каждый вызов в цепочке возвращает новый компаратор — целиком.
`comparing(Order::guest).thenComparingInt(Order::total)` — уже готовое
правило «по гостю, потом по сумме», и `.reversed()` разворачивает его
всё, а не последний ключ.

🔑 `reversed()` относится ко всему, что слева от него. Нужно развернуть
один ключ — разворачивай его внутри скобок.

### Развернуть только второй ключ

```java
Comparator<Order> right = Comparator.comparing(Order::guest)
        .thenComparing(Comparator.comparingInt(Order::total).reversed());
IO.println(orders.stream().sorted(right).map(label).toList());
```

```
[Анна 430, Анна 170, Борис 660, Борис 300, Вера 890, Вера 220, Глеб 820, Дина 650, Егор 150, Жанна 200]
```

Вот он, третий список хозяйки. `thenComparing` принимает целый
компаратор, и `reversed()` стоит внутри скобок — у суммы.

Для естественного порядка «наоборот» есть готовый компаратор —
`Comparator.reverseOrder()`:

```java
IO.println(menu.stream().sorted(Comparator.reverseOrder()).toList());
```

```
[ёлочный раф, раф, латте, американо, Эспрессо-тоник]
```

`reverseOrder()` можно передать и вторым аргументом в `comparing`
или `thenComparing` — «по этому ключу, но наоборот»:
`thenComparing(Order::total, Comparator.reverseOrder())` даёт тот же
правильный список, только с упаковкой чисел, как у `comparing`.

### ⚠️ Лямбда перед reversed теряет тип

Помнишь из статьи 2: тип параметра лямбды Java выводит сама. Перед
`reversed()` это ломается. Заменим в примере с тремя крупными заказами
ссылку на лямбду:

```java
        .sorted(Comparator.comparing(order -> order.total()).reversed())
```

```
Coffee.java:82: error: cannot find symbol
            .sorted(Comparator.comparing(order -> order.total()).reversed())
                                                       ^
  symbol:   method total()
  location: variable order of type Object
1 error
error: compilation failed
```

«У переменной `order` типа `Object` нет метода `total()`». Тип лямбды
Java берёт из места, куда её передают. Без `reversed()` это место —
`sorted(…)`, и Java понимает, что сравнивают заказы. С `reversed()`
вызов `comparing(…)` — уже не аргумент `sorted`, а объект, у которого
вызывают метод. Про заказы Java в этой точке не знает и считает
`order` самым общим типом — `Object`.

Выхода два: ссылка на метод — `Comparator.comparing(Order::total)` —
или тип параметра явно, как обещала статья 2:
`Comparator.comparing((Order order) -> order.total())`. В интернете
ты увидишь оба; теперь понятно, зачем там тип в скобках. Для числа,
впрочем, лучше всего `comparingInt(Order::total).reversed()`.

---

## Часть 4. Края: null, наибольшее, наименьшее

### nullsLast — пустые значения в конец

Хозяйка раздала анкету «любимый напиток», и один гость графу
не заполнил — там `null`. `List.of` с `null` не создаётся, бросает
`NullPointerException`, поэтому список собран через `Arrays.asList` —
он `null` пускает:

```java
List<String> favourites = Arrays.asList("раф", null, "какао", "латте");
```

Отсортируем как обычно:

```java
favourites.stream().sorted().toList();                  // NullPointerException
```

```
Exception in thread "main" java.lang.NullPointerException: Cannot invoke "java.lang.Comparable.compareTo(Object)" because "c1" is null
```

Естественный порядок спрашивает у элемента `compareTo`, а у `null`
спрашивать нечего. Компаратор нужно обернуть:

```java
List<String> nullLast = favourites.stream()
        .sorted(Comparator.nullsLast(Comparator.naturalOrder()))
        .toList();
IO.println(nullLast);
```

```
[какао, латте, раф, null]
```

`Comparator.naturalOrder()` — естественный порядок в виде компаратора.
`nullsLast(…)` ставит `null` в конец, а остальное сравнивает тем, что
передали внутрь, — например, `russian` из части 1. Есть и `nullsFirst`:
`null` в начало.

### min и max — тоже Optional

Самый крупный заказ Веры — сортировать весь список ради него не нужно:

```java
Optional<Order> veraMax = orders.stream()
        .filter(order -> order.guest().equals("Вера"))
        .max(Comparator.comparingInt(Order::total));
Optional<Order> ivanMax = orders.stream()
        .filter(order -> order.guest().equals("Иван"))
        .max(Comparator.comparingInt(Order::total));
IO.println(veraMax.map(Order::number) + " " + ivanMax.map(Order::number));
```

```
Optional[8] Optional.empty
```

`max` и `min` — конечные операции: принимают компаратор и отвечают
`Optional`. У Ивана заказов нет, значит, и наибольшего нет. Как
доставать ответ из коробки, ты знаешь из статьи 2.

💡 В интернете ты увидишь `sorted(…).findFirst()` вместо `min(…)`.
Ответ тот же, работы больше. `min` идёт по элементам один раз и помнит
лучший. А `sorted` должен увидеть все элементы, прежде чем отдать
дальше первый: отсортировать, не видя всех, нельзя. В статье 2
конвейер останавливался рано — `sorted` в этом месте всегда дочитывает
источник до конца.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Почему в естественном порядке «Эспрессо-тоник» встал раньше
   «американо», а «ёлочный раф» — после «раф»? Как отсортировать
   по-русски?
2. Что будет, если вызвать `sorted()` без аргументов на стриме заказов?
   Почему код при этом компилируется?
3. Чем `comparingInt(Order::total)` лучше `comparing(Order::total)`,
   если ответ одинаковый?
4. Заказы отсортировали только по гостю. В каком порядке окажутся два
   заказа Анны — и почему на это можно рассчитывать?
5. Почему `comparing(Order::guest).thenComparingInt(Order::total).reversed()`
   развернул и гостей? Как развернуть только сумму?
6. Почему `Comparator.comparing(order -> order.total()).reversed()`
   не компилируется, а без `reversed()` — компилируется? Назови два
   способа починить.
7. Почему `sorted()` падает на списке с `null` и что с этим делать?
8. Чем `max(…)` лучше `sorted(…)` с `findFirst()`? Что `max` ответит,
   если элементов нет?

---

## Реши в кузнице

Задачи на то же самое — `sorted`, компараторы, `thenComparing`,
`reversed`, `min` и `max` — в кузнице Stream Forge на платформе
Hammerhall, на фильмах и странах мира. Первые задачи бесплатны, нужен
только вход:

* [«Получить список названий всех стран, отсортированный в алфавитном порядке»](https://hammerhall.io/forge/stream-forge/task/WldCode0003);
* [«Получить список всех фильмов, отсортированных по году выхода»](https://hammerhall.io/forge/stream-forge/task/MovCode0009);
* [«Найти самый ранний фильм в базе»](https://hammerhall.io/forge/stream-forge/task/MovCode0011);
* [«Получить список стран, отсортированный сначала по континенту, затем по названию»](https://hammerhall.io/forge/stream-forge/task/WldCode0013);
* [«Найти страну с наибольшей площадью»](https://hammerhall.io/forge/stream-forge/task/WldCode0006).

## Что дальше

Статья 4 — `flatMap`: у каждого заказа внутри свой список позиций; как
собрать позиции всех заказов в один стрим и убрать повторы —
`distinct` и множество.

## Первоисточники

* [Interface Comparator — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Comparator.html) —
  `comparing`, `comparingInt`, `thenComparing`, `reversed`,
  `reverseOrder`, `naturalOrder`, `nullsLast`.
* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  `sorted`: устойчивость и `ClassCastException`; `min` и `max`.
* [String.compareTo — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/String.html#compareTo(java.lang.String)) —
  почему строки сравниваются по кодам символов.
* [Interface Comparable — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Comparable.html) —
  что такое естественный порядок.
* [Class Collator — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/text/Collator.html) —
  сравнение строк по правилам языка.

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
// Coffee.java — учебный пример статьи 3 серии «Стримы по шагам».
// Запуск: java Coffee.java (нужен JDK 25)

import java.text.Collator;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.function.Function;

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

    // 1. Естественный порядок строк: заглавные раньше строчных, «ё» после «я»
    List<String> menu = List.of("раф", "латте", "ёлочный раф", "Эспрессо-тоник", "американо");
    IO.println(menu.stream().sorted().toList());
    IO.println((int) 'Э' + " " + (int) 'а' + " " + (int) 'я' + " " + (int) 'ё');

    // 2. По правилам русского языка — Collator
    Collator russian = Collator.getInstance(Locale.of("ru"));
    IO.println(menu.stream().sorted(russian).toList());

    // 3. Компаратор лямбдой: от мелких заказов к крупным
    List<Integer> byLambda = orders.stream()
            .sorted((a, b) -> Integer.compare(a.total(), b.total()))
            .map(Order::number)
            .toList();
    IO.println(byLambda);

    // 4. То же — Comparator.comparingInt
    List<Integer> byTotal = orders.stream()
            .sorted(Comparator.comparingInt(Order::total))
            .map(Order::number)
            .toList();
    IO.println(byTotal);

    // 5. Сортировка устойчивая: у одного гостя — порядок источника
    Function<Order, String> label = order -> order.guest() + " " + order.total();
    Comparator<Order> byGuest = Comparator.comparing(Order::guest);
    IO.println(orders.stream().sorted(byGuest).map(label).toList());

    // 6. Второй ключ: у одного гостя — по сумме
    Comparator<Order> byGuestThenTotal = Comparator.comparing(Order::guest)
            .thenComparingInt(Order::total);
    IO.println(orders.stream().sorted(byGuestThenTotal).map(label).toList());

    // 7. reversed: три самых крупных заказа
    List<String> topThree = orders.stream()
            .sorted(Comparator.comparingInt(Order::total).reversed())
            .limit(3)
            .map(label)
            .toList();
    IO.println(topThree);

    // 8. Ловушка: reversed() в конце разворачивает всю цепочку
    Comparator<Order> wrong = Comparator.comparing(Order::guest)
            .thenComparingInt(Order::total)
            .reversed();
    IO.println(orders.stream().sorted(wrong).map(label).toList());

    // 9. Правильно: развернуть только второй ключ
    Comparator<Order> right = Comparator.comparing(Order::guest)
            .thenComparing(Comparator.comparingInt(Order::total).reversed());
    IO.println(orders.stream().sorted(right).map(label).toList());

    // 10. reverseOrder: естественный порядок наоборот
    IO.println(menu.stream().sorted(Comparator.reverseOrder()).toList());

    // 11. null в списке: nullsLast
    List<String> favourites = Arrays.asList("раф", null, "какао", "латте");
    List<String> nullLast = favourites.stream()
            .sorted(Comparator.nullsLast(Comparator.naturalOrder()))
            .toList();
    IO.println(nullLast);

    // 12. min и max отвечают Optional
    Optional<Order> veraMax = orders.stream()
            .filter(order -> order.guest().equals("Вера"))
            .max(Comparator.comparingInt(Order::total));
    Optional<Order> ivanMax = orders.stream()
            .filter(order -> order.guest().equals("Иван"))
            .max(Comparator.comparingInt(Order::total));
    IO.println(veraMax.map(Order::number) + " " + ivanMax.map(Order::number));

    // Сделай руками — раскомментируй по одной строке и запусти:
    // Collections.sort(menu);                                 // UnsupportedOperationException
    // orders.stream().sorted().toList();                      // ClassCastException
    // favourites.stream().sorted().toList();                  // NullPointerException
}
```

Сделай руками:

1. Запусти файл. Первая строка — меню в естественном порядке,
   `[Эспрессо-тоник, американо, латте, раф, ёлочный раф]`, третья — оно же
   через `Collator`.
2. Найди четыре строки с гостями: по гостю, по гостю и сумме, `wrong`
   и `right`. Сравни, где Анна и где Жанна.
3. В блоке `// 8.` убери `.reversed()` (точку с запятой перенеси
   на строку выше). Строка `wrong` станет такой же, как в блоке `// 6.`
   Верни как было.
4. В блоке `// 7.` замени `Comparator.comparingInt(Order::total)`
   на `Comparator.comparing(order -> order.total())` и прочитай ошибку
   компилятора. Потом напиши `(Order order)` вместо `order` в начале
   лямбды — заработает. Верни как было.
5. В блоке `// 11.` замени `nullsLast` на `nullsFirst`: `null` переедет
   в начало.
6. Раскомментируй по одной строке в конце `main`:
   `UnsupportedOperationException`, `ClassCastException`,
   `NullPointerException`. Каждый раз возвращай комментарий.
