# Сходство множеств: коэффициент Жаккара

> «Сравнить коллекции» · статья 5 · читать минут 20
>
> **Для кого.** Ты прочитал [статью 1](https://hammerhall.io/ledger/algorithms/1-set-algebra)
> цикла — пересечение, объединение, `contains` — и «Стримы по шагам»:
> `groupingBy` с коллектором для группы, компараторы, правило ничьей.
>
> **Что будет.** Как одним числом от 0 до 1 сказать, насколько похожи
> два набора, и почему «сколько общего» не годится; что делать с пустыми
> наборами и `NaN`; как сортировать и печатать `double`; чем взвешенный
> Жаккар отличается от обычного. Вопрос статьи — у кого из постоянных
> гостей «Наковальни» за месяц изменился вкус.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи на алгоритмы — в кузнице Stream Forge на платформе, в слое mind; здесь — теория к ним: приём, его цена и где он ломается. Примеры учебные: каждый запускается одним файлом.

---

## Зачем мерить сходство числом

Хозяйка «Наковальни» спрашивает: у кого из постоянных гостей за месяц
поменялся вкус, а у кого всё по-старому? Данные — месяц заказов
из [статьи 1](https://hammerhall.io/ledger/algorithms/1-set-algebra): `orders(42, 300, 30)`,
300 гостей, 30 дней, 2843 заказа.

Статья 1 даёт половину ответа. Что гость брал в дни 1–15, — одно
множество, в дни 16–30 — другое. Разность скажет, что он бросил,
пересечение — что оставил. Но хозяйке нужен рейтинг, а для рейтинга —
одно число на гостя, чтобы гостя с тремя позициями честно поставить
рядом с гостем, который брал девять.

Первая мысль — число общих позиций: больше общего — стабильнее вкус.
В части 1 увидишь, почему так нельзя. Работает **коэффициент Жаккара**
(Jaccard index): доля общего во всём, что было.

---

## Часть 1. Общее, делённое на всё

### Формула на пальцах

Гость 17 в первой половине месяца брал капучино, эклер и эспрессо,
во второй — какао, капучино и эспрессо. Посчитаем руками:

* общее — пересечение A ∩ B, «то, что есть в обоих»: капучино
  и эспрессо, 2 позиции;
* всё — объединение A ∪ B, «то, что есть хоть в одном»: какао,
  капучино, эклер, эспрессо, 4 позиции;
* J = 2 / 4 = 0,5.

Это и есть формула: J(A, B) = |A ∩ B| / |A ∪ B|. Черты читаются
«размер»: |A| — число элементов в A. Словами: из всего, что гость брал
хоть в одной половине, какая доля — в обеих. Общего не бывает больше,
чем всего, поэтому J — от 0 до 1: единица — наборы равны, ноль — общего
нет.

### Объединение строить не нужно

В статье 1 объединение собирали через `addAll` в копию. Жаккару нужен
только размер объединения, а он считается без нового множества:

|A ∪ B| = |A| + |B| − |A ∩ B|

Сложи размеры — и каждая общая позиция посчитана дважды, по разу
в каждом множестве. Вычти общие один раз. Для гостя 17: 3 + 3 − 2 = 4.
Пересечение тоже не строим, только считаем — `filter` по `contains`:

```java
/** Коэффициент Жаккара: доля общего во всём, что было хоть в одном наборе. */
double jaccard(Set<String> a, Set<String> b) {
    long common = a.stream().filter(b::contains).count();   // |A ∩ B|: считаем, не строим
    long union = a.size() + b.size() - common;              // |A ∪ B| по формуле
    return (double) common / union;
}
```

Наборы гостей по половинам месяца собирает `groupingBy` с `flatMapping`
из [статьи 6 «Стримов»](https://hammerhall.io/ledger/streams/6-downstream-collectors):

```java
/** Что брал каждый гость в дни from…to: номер карты → множество позиций. */
Map<Integer, Set<String>> tastes(List<Order> orders, int from, int to) {
    return orders.stream()
            .filter(order -> order.day() >= from && order.day() <= to)
            .collect(groupingBy(Order::guest,
                    flatMapping(order -> order.items().stream().map(Item::name), toCollection(TreeSet::new))));
}
```

`toCollection(TreeSet::new)` — «сложи в `TreeSet`»: множество, которое
держит элементы по алфавиту, и печать одинакова на любом компьютере.

```java
Map<Integer, Set<String>> early = tastes(orders, 1, 15);
Map<Integer, Set<String>> late = tastes(orders, 16, 30);
IO.println(early.get(17) + " | " + late.get(17));
IO.println(jaccard(early.get(17), late.get(17)));
```

```
[капучино, эклер, эспрессо] | [какао, капучино, эспрессо]
0.5
```

### ⚠️ Целое деление

`(double)` в `jaccard` — не украшение. Без него `common / union` —
деление `long` на `long`, и дробная часть отбрасывается: 2 / 4 — это 0,
метод вернёт `0.0` для любых неравных наборов. Приведение стоит
до деления: `(double) common` уже дробное, и делится по-дробному.

### Почему не «сколько общего»

Гость 12 за месяц брал все 12 позиций меню. Сравним с ним набор гостя 17
за месяц, а для контроля — 17-го с самим собой:

```java
Map<Integer, Set<String>> month = tastes(orders, 1, 30);
Set<String> guest17 = month.get(17);
Set<String> guest12 = month.get(12);
long withSelf = guest17.stream().filter(guest17::contains).count();
long withAll = guest17.stream().filter(guest12::contains).count();
```

```
гость 12: 12 позиций; гость 17: [какао, капучино, эклер, эспрессо]
общих позиций: с собой — 4, с гостем 12 — 4
Жаккар: с собой — 1.0, с гостем 12 — 0.3333333333333333
```

По числу общих гость 12 похож на 17-го так же, как 17-й — сам на себя.
И так с любым гостем: у того, кто брал всё, общего с каждым — весь набор
того. Жаккар делит общее на объединение: 4 из 12 — треть.

🔑 Число общих растёт вместе с наборами: кто берёт больше, тот «похож»
на всех. Жаккар — доля, и размер он гасит.

Перевёрнутая мера — **расстояние Жаккара** 1 − J: 0 у одинаковых наборов,
1 у наборов без общего; расстояния — тема [статьи 6](https://hammerhall.io/ledger/algorithms/6-vectors).

---

## Часть 2. Пустые наборы и NaN

### Один пустой — ноль

Гость 3 заходил только в первой половине месяца:

```java
IO.println(early.get(3) + " | " + late.get(3));
IO.println(jaccard(early.get(3), late.getOrDefault(3, Set.of())));
```

```
[какао, чай] | null
0.0
```

Во второй половине гостя 3 в карте нет: `groupingBy` не заводит пустых
групп — помнишь [статью 5 «Стримов»](https://hammerhall.io/ledger/streams/5-grouping). Отдай
`null` в `jaccard` — упадёт `NullPointerException`. Поэтому
`getOrDefault(3, Set.of())`: нет записи — пустое множество. Общего 0,
объединение 2, J = 0: пустой набор ни на что не похож.

### Оба пустых — 0/0

Гость 96 не заходил ни разу. Общего 0, объединение 0, и формула делит
ноль на ноль:

```java
IO.println(jaccard(Set.of(), Set.of()));
```

```
NaN
```

**NaN** (Not a Number, «не число») — особое значение `double` для
операции без определённого ответа. Дели мы `long` на `long`, без
`(double)`, — вылетело бы исключение:

```
Exception in thread "main" java.lang.ArithmeticException: / by zero
```

Исключение хотя бы видно. NaN молчит. Сравнения `<`, `>`, `==` с ним
всегда ложны, даже `NaN == NaN` (а `!=` — истинно), поэтому фильтр
`j >= 0.0` тихо выбросит шестерых гостей без заказов — из 300 останется
294. А сортировка? Нужна запись «гость и его Жаккар»:

```java
/** Гость и Жаккар его наборов за первую и вторую половину месяца. */
record Shift(int guest, double jaccard) {}
```

И все 300 гостей по убыванию J:

```java
Comparator<Shift> stableFirst = Comparator.comparingDouble(Shift::jaccard).reversed()
        .thenComparingInt(Shift::guest);
List<String> everyone = IntStream.rangeClosed(1, 300)
        .mapToObj(guest -> new Shift(guest,
                jaccard(early.getOrDefault(guest, Set.of()), late.getOrDefault(guest, Set.of()))))
        .sorted(stableFirst)
        .limit(8)
        .map(shift -> shift.guest() + "=" + shift.jaccard())
        .toList();
```

```
[96=NaN, 120=NaN, 152=NaN, 228=NaN, 233=NaN, 299=NaN, 43=1.0, 70=1.0]
```

Шестеро без единого заказа — «самые стабильные». Компараторы —
из [статьи 3 «Стримов»](https://hammerhall.io/ledger/streams/3-sorting): по убыванию J,
при равных — по номеру карты. NaN встал после всех чисел — так
упорядочивает и `Double.compare`: по документации NaN больше любого
числа. А `reversed()` вывел его наверх.

### Договорённость

Чему равен J двух пустых наборов, формула не говорит — это назначают,
и питоновские библиотеки назначают по-разному. В SciPy расстояние двух
нулевых векторов (пустых наборов) — 0, то есть J = 1; в scikit-learn
по умолчанию 0 с предупреждением, а параметр `zero_division` даёт
выбрать. В задаче договорённость пишут в условии — ищи её там.

У нас — 1: два пустых множества равны, с этим согласен `Set.equals`
из статьи 1, а J = 1 как раз у равных. В `jaccard` перед делением —
три строки:

```java
if (union == 0) {
    return 1.0;                                      // оба пустые: договорились — равны
}
```

🔑 Видишь деление — спроси, что будет при нуле в знаменателе. Ответ —
договорённость, записанная в коде, а не NaN, который всплывёт через три
метода.

---

## Часть 3. Чей вкус изменился

### Кого считать постоянным

С договорённостью тот же список выглядит так:

```
[43=1.0, 70=1.0, 96=1.0, 120=1.0, 152=1.0, 173=1.0, 211=1.0, 228=1.0]
```

NaN нет, но наверху всё равно не те: гости 96, 120, 152 и 228 не заходили
вовсе, гость 43 заходил 2 и 4 раза. А гость 173:

```
[эспрессо] | [эспрессо]
```

Один визит в каждой половине, оба раза эспрессо. J = 1 — но это два
заказа, а не вкус. Гостей с одним визитом в каждой половине семеро, и их
J — по всей шкале: 0; 0; 0,25; 0,33; 0,5; 0,5 и 1. У того, кто зашёл
раз-другой, J — шум.

Слово «постоянный» надо определить. **Постоянный** гость у нас — от 5
визитов в каждой половине месяца, примерно раз в три дня. За пять
визитов — от 5 до 15 строк заказов, и одна случайная проба уже
не переворачивает ответ. Порог — тоже договорённость: с порогом 3
постоянных будет 188, с порогом 7 — 63.

```java
/** Постоянные гости — от minVisits визитов в каждой половине месяца. */
List<Shift> regulars(List<Order> orders, int minVisits) {
    Map<Integer, Set<String>> early = tastes(orders, 1, 15);
    Map<Integer, Set<String>> late = tastes(orders, 16, 30);
    Map<Integer, Long> visitsEarly = visits(orders, 1, 15);
    Map<Integer, Long> visitsLate = visits(orders, 16, 30);
    return visitsEarly.keySet().stream()
            .filter(guest -> visitsEarly.get(guest) >= minVisits
                    && visitsLate.getOrDefault(guest, 0L) >= minVisits)
            .map(guest -> new Shift(guest, jaccard(early.get(guest), late.get(guest))))
            .toList();
}
```

`visits` — та же группировка, что `tastes`, только с `counting()`;
`getOrDefault(guest, 0L)` — как с гостем 3.

```java
List<Shift> regular = regulars(orders, 5);
IO.println("постоянных: " + regular.size());
IO.println(regular.stream().sorted(stableFirst).limit(6).toList());
```

```
постоянных: 124
[Shift[guest=211, jaccard=1.0], Shift[guest=109, jaccard=0.8571428571428571], Shift[guest=38, jaccard=0.8], Shift[guest=112, jaccard=0.8], Shift[guest=122, jaccard=0.8], Shift[guest=178, jaccard=0.8]]
```

Гость 211 в обеих половинах брал одно и то же: какао, круассан, чизкейк,
эклер.

### Ничьи

За ним — четыре гостя с 0,8: ничья. Порядок внутри неё задаёт
`thenComparingInt(Shift::guest)`. Без него порядок зависел бы от того,
как гости вышли из `keySet()` карты, а этот порядок никто не обещает —
помнишь [статью 7 «Стримов»](https://hammerhall.io/ledger/streams/7-streams-over-maps). Возьми
пятёрку вместо шестёрки — и гость 178 выпадет, хотя ничем не хуже 122-го.

💡 Ничья по `double` здесь настоящая. Java делит с округлением
до ближайшего числа, которое умеет хранить, и равные дроби дают одно
число: 4 из 5 у всех четверых — одинаковое `0.8`. Посчитай то же другим
путём — и последний знак может уехать: `1 - 0.8` в Java —
`0.19999999999999996`.

### Печать с округлением

`0.8571428571428571` хозяйке ни к чему, хватит двух знаков. Под рукой
`String.format("%.2f", …)` — «дробное, два знака после запятой»:

```java
double j109 = jaccard(early.get(109), late.get(109));
IO.println(j109);
IO.println(String.format("%.2f", j109));
IO.println(String.format(Locale.of("ru"), "%.2f", j109));
IO.println(String.format(Locale.ROOT, "%.2f", j109));
```

```
0.8571428571428571
0.86
0,86
0.86
```

⚠️ Вторая строка зависит от компьютера. `String.format` без языка берёт
язык системы: в нашем прогоне он английский, и вышла точка; с русским
та же строка напечатает `0,86`, как третья. Та же история, что со сводкой
в [статье 8 «Стримов»](https://hammerhall.io/ledger/streams/8-number-streams). Печать, которая
везде должна быть одинаковой, — с `Locale.ROOT`, «нейтральным» языком:
там всегда точка.

`%.2f` округляет «половину вверх»: 0,857… печатается как `0.86`,
0,125 — как `0.13`.
Округляй только при печати, а сортируй по самому числу:

```java
/** Гость и его Жаккар с двумя знаками после точки — на любом компьютере. */
String show(Shift shift) {
    return String.format(Locale.ROOT, "%d: %.2f", shift.guest(), shift.jaccard());
}
```

Ответ хозяйке — две шестёрки. Для второй компаратор без `reversed()`,
по возрастанию:

```java
Comparator<Shift> changedFirst = Comparator.comparingDouble(Shift::jaccard)
        .thenComparingInt(Shift::guest);
IO.println("стабильнее всех: "
        + regular.stream().sorted(stableFirst).limit(6).map(shift -> show(shift)).toList());
IO.println("изменились сильнее всех: "
        + regular.stream().sorted(changedFirst).limit(6).map(shift -> show(shift)).toList());
```

```
стабильнее всех: [211: 1.00, 109: 0.86, 38: 0.80, 112: 0.80, 122: 0.80, 178: 0.80]
изменились сильнее всех: [297: 0.14, 14: 0.20, 142: 0.29, 267: 0.29, 36: 0.30, 197: 0.30]
```

Гость 297 в первой половине брал капучино, круассан, раф, сырник
и чизкейк, во второй — капучино, латте и матчу: общий — один капучино
из семи позиций.

💡 Честно о данных: в генераторе три любимые позиции гостя весь месяц
одни и те же, так что разница половин — случайные пробы. Поэтому
взвешенный Жаккар в части 4 и гасит разовые пробы гостя 27.

### Сколько это стоит

Один Жаккар — проход по одному набору и `contains` в другом. Идти
выгоднее по меньшему: обращений столько, сколько в нём элементов.
Объединение по формуле не стоит ничего; собрать его через `addAll` —
|A| + |B| вставок и новое множество.

Итоговый `jaccard` идёт по меньшему набору и считает обращения в поле
`checks`, как в [статье 9 «Стримов»](https://hammerhall.io/ledger/streams/9-two-collections):

```java
Set<String> small = a.size() <= b.size() ? a : b;    // идём по меньшему
Set<String> large = a.size() <= b.size() ? b : a;    // спрашиваем у большего
long common = small.stream()
        .filter(name -> {
            checks++;
            return large.contains(name);
        })
        .count();
```

Работа на нашем месяце и на `orders(42, n, 30)` с бо́льшим числом гостей:

```
300 гостей: заказов 2843, постоянных 124, обращений contains 573
1000 гостей: заказов 9834, постоянных 427, обращений contains 1992
2000 гостей: заказов 19568, постоянных 870, обращений contains 4042
4000 гостей: заказов 38969, постоянных 1639, обращений contains 7662
8000 гостей: заказов 78239, постоянных 3325, обращений contains 15528
```

Вдвое больше гостей — примерно вдвое больше работы: один Жаккар
на постоянного гостя, а наборы и визиты собраны проходами по заказам.
(`contains` у `TreeSet` — порядка log₂ n сравнений, у `HashSet` —
в среднем постоянное время; на 12 позициях разницы не видно.) А пар
«все со всеми» — n·(n−1)/2, для 294 гостей с заказами — 43 071
([статья 3](https://hammerhall.io/ledger/algorithms/3-all-pairs)). Вопрос «гость против самого
себя» дешёвый: пар в нём нет.

---

## Часть 4. Взвешенный Жаккар

### Брал или сколько брал

Обычный Жаккар видит «брал или не брал». Вот гость 292 по штукам
в каждой половине:

```
{латте=4, раф=1, чай=1, эспрессо=3} | {латте=1, раф=3, эспрессо=5}
```

Как множества — 3 общих из 4, J = 0,75, вкус почти не изменился. Но
в первой половине он больше всего пил латте, во второй — эспрессо и раф.
Привычки другие, а множество этого не видит.

**Взвешенный Жаккар** считает штуки. Для каждой позиции берём меньшее
и большее из двух количеств и делим сумму меньших на сумму больших:
Σ min / Σ max, где Σ — «сумма по всем позициям»:

| позиция | дни 1–15 | дни 16–30 | меньшее | большее |
|---|---|---|---|---|
| латте | 4 | 1 | 1 | 4 |
| раф | 1 | 3 | 1 | 3 |
| чай | 1 | 0 | 0 | 1 |
| эспрессо | 3 | 5 | 3 | 5 |
| **сумма** | | | **5** | **13** |

Взвешенный J = 5 / 13 ≈ 0,38. Будь количества только 0 и 1, сумма меньших
равнялась бы размеру пересечения, сумма больших — размеру объединения:
обычный Жаккар — частный случай взвешенного.

```java
/** Взвешенный Жаккар: сумма меньших количеств, делённая на сумму больших. */
double weightedJaccard(Map<String, Integer> a, Map<String, Integer> b) {
    int min = 0;
    int max = 0;
    for (Item item : MENU) {                             // все 12 позиций меню
        int x = a.getOrDefault(item.name(), 0);
        int y = b.getOrDefault(item.name(), 0);
        min += Math.min(x, y);
        max += Math.max(x, y);
    }
    return max == 0 ? 1.0 : (double) min / max;          // та же договорённость
}
```

Объединение ключей и здесь не строим: цикл идёт по 12 позициям меню,
а чего гость не брал, `getOrDefault` превращает в ноль. Карты «позиция →
штуки» собирает `pieces` — `groupingBy` по гостю, внутри него
`groupingBy` по позиции с `summingInt(Item::qty)`.

```
гость 292: обычный 0.75, взвешенный 0.38
```

### Расходятся в обе стороны

Гость 27 по обычному J — сразу за шестёркой «изменились сильнее всех»:

```
{американо=5, какао=1, сырник=1, чай=3, эспрессо=5} | {американо=5, капучино=1, латте=1, раф=2, чай=3, чизкейк=1, эспрессо=5}
гость 27: обычный 0.33, взвешенный 0.65
```

Основа не сдвинулась: американо, чай и эспрессо — 5, 3 и 5 штук в обеих
половинах. Но шесть других позиций он взял по одной-две штуки, и каждая
раздула объединение: обычный Жаккар считает разовую пробу наравне
с привычкой.

🔑 Какой из двух верный, решает вопрос. «Пробует ли гость новое?» —
обычный. «Изменилось ли, что и сколько он берёт?» — взвешенный.

💡 Встретишь «Жаккар для мультимножеств» — проверь формулу. В книге
*Mining of Massive Datasets* так назван другой вариант: в знаменателе —
сумма размеров обоих наборов, и самое большое значение — 1/2.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что значит J = 0,5 у гостя 17? Почему J не бывает больше 1 и когда
   он равен 1?
2. Как узнать размер объединения, не строя его? Откуда в формуле минус?
3. Почему число общих позиций плохо мерит сходство? Что не так
   с гостем 12?
4. Что вернёт `jaccard` гостя 17 без `(double)`? Что выйдет у двух
   пустых наборов в `long` и в `double`?
5. Чем опасен NaN в фильтре и в сортировке? Какую договорённость
   о пустых наборах выбрали мы и почему?
6. Зачем фильтр постоянных гостей? Почему J = 1 у гостя 173 ничего
   не говорит о вкусе?
7. Зачем `thenComparingInt(Shift::guest)`? Почему печатать —
   с `Locale.ROOT`, а сортировать — по самому числу?
8. Почему у гостя 292 взвешенный Жаккар меньше обычного, а у гостя 27 —
   больше?

---

## Что дальше

Жаккар видит «брал или не брал», а сколько раз — нет; взвешенный —
только первый шаг к количествам. В [статье 6](https://hammerhall.io/ledger/algorithms/6-vectors)
профиль гостя станет вектором из 12 чисел, а с ним придут косинус,
расстояние и ближайшие соседи.

## Первоисточники

* [CS246 Mining Massive Datasets, лекция о поиске похожих (Стэнфорд)](https://snap.stanford.edu/class/cs246-2025/WWW/slides/03-lsh.pdf) —
  сходство Жаккара и расстояние 1 − J на слайдах.
* [Manasse, McSherry, Talwar. Consistent Weighted Sampling](https://www.microsoft.com/en-us/research/publication/consistent-weighted-sampling/) —
  Σ min / Σ max как естественное обобщение сходства Жаккара.
* [scipy.spatial.distance.jaccard](https://docs.scipy.org/doc/scipy/reference/generated/scipy.spatial.distance.jaccard.html)
  и [sklearn.metrics.jaccard_score](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.jaccard_score.html) —
  две договорённости о пустых наборах.
* [Class Double — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Double.html) —
  NaN и почему `compare` ставит его после всех чисел.
* [Class Formatter](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Formatter.html)
  и [Class Locale — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Locale.html) —
  `%.2f`, округление «половину вверх», язык по умолчанию, `Locale.ROOT`.
* [JLS 25, §15.4 Floating-point Expressions](https://docs.oracle.com/javase/specs/jls/se25/html/jls-15.html#jls-15.4) —
  откуда NaN и почему `NaN == NaN` ложно; в §15.6 — исключение
  при целом делении на ноль.

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Записи, меню и генератор заказов стоят вверху файла — они одинаковые
во всех статьях серии, генератор читать не обязательно. Методы и `main` —
без класса вокруг: в Java 25 такой файл сам становится классом,
а `void main()` без `public static` и без параметров — точкой входа.
Сохрани файл как `Coffee.java` и запусти из его папки:

```bash
java Coffee.java
```

Java сама скомпилирует файл и выполнит `main` — ни Maven, ни проекта
не нужно. Если вместо русских букв в выводе вопросы или кракозябры,
запусти с явной кодировкой — аргументы в кавычках, так их поймёт
и PowerShell: `java "-Dstdout.encoding=UTF-8" "-Dstderr.encoding=UTF-8" Coffee.java`;
в командной строке Windows перед этим выполни `chcp 65001`. Последний
блок `main` пересоздаёт заказы для 8000 гостей — подожди несколько секунд.

```java
// Coffee.java — учебный пример статьи 5 серии «Алгоритмы на стримах».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.IntStream;

import static java.util.stream.Collectors.*;

/** Позиция заказа: название, цена за штуку в рублях, сколько штук. */
record Item(String name, int price, int qty) {}

/** Заказ: номер, день месяца, номер карты гостя, позиции. */
record Order(int number, int day, int guest, List<Item> items) {

    /** Сумма заказа в рублях. */
    int total() {
        return items.stream().mapToInt(item -> item.price() * item.qty()).sum();
    }
}

/** Меню кофейни «Наковальня»: название и цена в рублях, по одной штуке. */
static final List<Item> MENU = List.of(
        new Item("латте", 250, 1), new Item("капучино", 220, 1), new Item("эспрессо", 150, 1),
        new Item("американо", 170, 1), new Item("раф", 290, 1), new Item("какао", 200, 1),
        new Item("матча", 280, 1), new Item("чай", 120, 1), new Item("круассан", 180, 1),
        new Item("чизкейк", 320, 1), new Item("сырник", 210, 1), new Item("эклер", 190, 1));

/**
 * Заказы {@code guests} гостей за {@code days} дней. Одно и то же зерно —
 * одни и те же заказы на любом компьютере. Генератор — не тема статьи:
 * читать его не обязательно.
 */
List<Order> orders(long seed, int guests, int days) {
    Random random = new Random(seed);
    List<List<Item>> liked = new ArrayList<>();          // у каждого гостя три любимые позиции
    List<Double> chance = new ArrayList<>();             // и своя вероятность зайти в день
    for (int guest = 0; guest < guests; guest++) {
        List<Item> three = new ArrayList<>();
        while (three.size() < 3) {
            Item item = MENU.get(random.nextInt(MENU.size()));
            if (!three.contains(item)) {
                three.add(item);
            }
        }
        liked.add(List.copyOf(three));
        chance.add(0.05 + random.nextInt(12) * 0.05);
    }
    List<Order> orders = new ArrayList<>();
    for (int day = 1; day <= days; day++) {
        for (int guest = 0; guest < guests; guest++) {
            if (random.nextDouble() >= chance.get(guest)) {
                continue;                                 // сегодня этот гость не пришёл
            }
            List<Item> items = new ArrayList<>();
            int positions = 1 + random.nextInt(3);
            for (int i = 0; i < positions; i++) {
                Item pick = random.nextInt(4) < 3
                        ? liked.get(guest).get(random.nextInt(3))       // обычно — любимое
                        : MENU.get(random.nextInt(MENU.size()));       // иногда — что-то ещё
                int qty = random.nextInt(10) == 0 ? 2 : 1;
                if (items.stream().noneMatch(item -> item.name().equals(pick.name()))) {
                    items.add(new Item(pick.name(), pick.price(), qty));
                }
            }
            orders.add(new Order(orders.size() + 1, day, guest + 1, List.copyOf(items)));
        }
    }
    return List.copyOf(orders);
}

/** Что брал каждый гость в дни from…to: номер карты → множество позиций. */
Map<Integer, Set<String>> tastes(List<Order> orders, int from, int to) {
    return orders.stream()
            .filter(order -> order.day() >= from && order.day() <= to)
            .collect(groupingBy(Order::guest,
                    flatMapping(order -> order.items().stream().map(Item::name), toCollection(TreeSet::new))));
}

/** Сколько раз заходил каждый гость в дни from…to. */
Map<Integer, Long> visits(List<Order> orders, int from, int to) {
    return orders.stream()
            .filter(order -> order.day() >= from && order.day() <= to)
            .collect(groupingBy(Order::guest, counting()));
}

/** Сколько штук каждой позиции взял каждый гость в дни from…to. */
Map<Integer, Map<String, Integer>> pieces(List<Order> orders, int from, int to) {
    return orders.stream()
            .filter(order -> order.day() >= from && order.day() <= to)
            .collect(groupingBy(Order::guest, flatMapping(order -> order.items().stream(),
                    groupingBy(Item::name, TreeMap::new, summingInt(Item::qty)))));
}

long checks = 0;    // сколько раз спросили contains — мера работы

/** Коэффициент Жаккара: доля общего во всём, что было хоть в одном наборе. */
double jaccard(Set<String> a, Set<String> b) {
    Set<String> small = a.size() <= b.size() ? a : b;    // идём по меньшему
    Set<String> large = a.size() <= b.size() ? b : a;    // спрашиваем у большего
    long common = small.stream()
            .filter(name -> {
                checks++;
                return large.contains(name);
            })
            .count();
    long union = a.size() + b.size() - common;           // |A ∪ B| без самого объединения
    if (union == 0) {
        return 1.0;                                      // оба пустые: договорились — равны
    }
    return (double) common / union;
}

/** Взвешенный Жаккар: сумма меньших количеств, делённая на сумму больших. */
double weightedJaccard(Map<String, Integer> a, Map<String, Integer> b) {
    int min = 0;
    int max = 0;
    for (Item item : MENU) {                             // все 12 позиций меню
        int x = a.getOrDefault(item.name(), 0);
        int y = b.getOrDefault(item.name(), 0);
        min += Math.min(x, y);
        max += Math.max(x, y);
    }
    return max == 0 ? 1.0 : (double) min / max;          // та же договорённость
}

/** Гость и Жаккар его наборов за первую и вторую половину месяца. */
record Shift(int guest, double jaccard) {}

/** Постоянные гости — от minVisits визитов в каждой половине месяца. */
List<Shift> regulars(List<Order> orders, int minVisits) {
    Map<Integer, Set<String>> early = tastes(orders, 1, 15);
    Map<Integer, Set<String>> late = tastes(orders, 16, 30);
    Map<Integer, Long> visitsEarly = visits(orders, 1, 15);
    Map<Integer, Long> visitsLate = visits(orders, 16, 30);
    return visitsEarly.keySet().stream()
            .filter(guest -> visitsEarly.get(guest) >= minVisits
                    && visitsLate.getOrDefault(guest, 0L) >= minVisits)
            .map(guest -> new Shift(guest, jaccard(early.get(guest), late.get(guest))))
            .toList();
}

/** Гость и его Жаккар с двумя знаками после точки — на любом компьютере. */
String show(Shift shift) {
    return String.format(Locale.ROOT, "%d: %.2f", shift.guest(), shift.jaccard());
}

void main() {
    List<Order> orders = orders(42, 300, 30);
    Map<Integer, Set<String>> early = tastes(orders, 1, 15);
    Map<Integer, Set<String>> late = tastes(orders, 16, 30);

    // 1. Гость 17: что брал в первой и во второй половине месяца — и их Жаккар
    IO.println(early.get(17) + " | " + late.get(17));
    IO.println(jaccard(early.get(17), late.get(17)));

    // 2. Число общих против Жаккара: гость 17 с самим собой и с гостем 12
    Map<Integer, Set<String>> month = tastes(orders, 1, 30);
    Set<String> guest17 = month.get(17);
    Set<String> guest12 = month.get(12);
    long withSelf = guest17.stream().filter(guest17::contains).count();
    long withAll = guest17.stream().filter(guest12::contains).count();
    IO.println("гость 12: " + guest12.size() + " позиций; гость 17: " + guest17);
    IO.println("общих позиций: с собой — " + withSelf + ", с гостем 12 — " + withAll);
    IO.println("Жаккар: с собой — " + jaccard(guest17, guest17) + ", с гостем 12 — " + jaccard(guest17, guest12));

    // 3. Края: гость 3 приходил только в первой половине, гость 96 — ни разу
    IO.println(early.get(3) + " | " + late.get(3));
    IO.println(jaccard(early.get(3), late.getOrDefault(3, Set.of())));
    IO.println(jaccard(early.getOrDefault(96, Set.of()), late.getOrDefault(96, Set.of())));

    // 4. Все 300 гостей по убыванию Жаккара: наверху — не те, кого искали
    Comparator<Shift> stableFirst = Comparator.comparingDouble(Shift::jaccard).reversed()
            .thenComparingInt(Shift::guest);
    List<String> everyone = IntStream.rangeClosed(1, 300)
            .mapToObj(guest -> new Shift(guest,
                    jaccard(early.getOrDefault(guest, Set.of()), late.getOrDefault(guest, Set.of()))))
            .sorted(stableFirst)
            .limit(8)
            .map(shift -> shift.guest() + "=" + shift.jaccard())
            .toList();
    IO.println(everyone);
    IO.println(early.get(173) + " | " + late.get(173));

    // 5. Постоянные гости: самые стабильные и сильнее всего изменившиеся
    List<Shift> regular = regulars(orders, 5);
    IO.println("постоянных: " + regular.size());
    IO.println(regular.stream().sorted(stableFirst).limit(6).toList());
    Comparator<Shift> changedFirst = Comparator.comparingDouble(Shift::jaccard)
            .thenComparingInt(Shift::guest);
    IO.println("стабильнее всех: "
            + regular.stream().sorted(stableFirst).limit(6).map(shift -> show(shift)).toList());
    IO.println("изменились сильнее всех: "
            + regular.stream().sorted(changedFirst).limit(6).map(shift -> show(shift)).toList());

    // 6. Печать double: как есть, по языку системы, с русской запятой, с точкой всегда
    double j109 = jaccard(early.get(109), late.get(109));
    IO.println(j109);
    IO.println(String.format("%.2f", j109));
    IO.println(String.format(Locale.of("ru"), "%.2f", j109));
    IO.println(String.format(Locale.ROOT, "%.2f", j109));

    // 7. Взвешенный Жаккар против обычного: гости 292 и 27
    Map<Integer, Map<String, Integer>> piecesEarly = pieces(orders, 1, 15);
    Map<Integer, Map<String, Integer>> piecesLate = pieces(orders, 16, 30);
    for (int guest : List.of(292, 27)) {
        IO.println(piecesEarly.get(guest) + " | " + piecesLate.get(guest));
        IO.println(String.format(Locale.ROOT, "гость %d: обычный %.2f, взвешенный %.2f", guest,
                jaccard(early.get(guest), late.get(guest)),
                weightedJaccard(piecesEarly.get(guest), piecesLate.get(guest))));
    }

    // 8. Цена: сколько раз спросили contains — на месяце и при росте числа гостей
    for (int guests : List.of(300, 1000, 2000, 4000, 8000)) {
        List<Order> grown = orders(42, guests, 30);
        checks = 0;
        int count = regulars(grown, 5).size();
        IO.println(guests + " гостей: заказов " + grown.size() + ", постоянных " + count
                + ", обращений contains " + checks);
    }
}
```

Сделай руками:

1. Запусти файл. Вторая строка — `0.5`; дальше найди `постоянных: 124`
   и `гость 292: обычный 0.75, взвешенный 0.38`.
2. В `jaccard` замени `return (double) common / union;`
   на `return common / union;`. Вторая строка станет `0.0`, а в строке
   «стабильнее всех» после `211: 1.00` пойдут нули: `1: 0.00, 4: 0.00, …`.
   Верни как было.
3. Закомментируй в `jaccard` три строки `if (union == 0) { … }`. В блоке
   `// 3.` последняя строка станет `NaN`, а блок `// 4.` напечатает
   `[96=NaN, 120=NaN, 152=NaN, 228=NaN, 233=NaN, 299=NaN, 43=1.0, 70=1.0]`.
   Верни как было.
4. В блоке `// 5.` замени `regulars(orders, 5)` на `regulars(orders, 3)`:
   постоянных станет 188, а в «стабильнее всех» рядом с гостем 211
   появится гость 269, тоже `1.00`. Верни как было.
5. В `jaccard` пусти проход по большему набору: в строке `small` замени
   `? a : b` на `? b : a`, в строке `large` — `? b : a` на `? a : b`.
   Ответы не изменятся, а обращений `contains` на нашем месяце станет
   762 вместо 573. Верни как было.
6. Запусти файл с русским языком — добавь в команду `"-Duser.language=ru"`
   перед `Coffee.java`. В блоке `// 6.` вторая строка станет `0,86`,
   а строки, напечатанные через `show`, останутся с точкой.
