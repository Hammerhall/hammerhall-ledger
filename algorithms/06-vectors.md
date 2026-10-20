# Векторы: косинус, расстояние, ближайшие соседи

> «Сравнить коллекции» · статья 6 · читать минут 20
>
> **Для кого.** Ты прочитал статьи 1–5 цикла: пары и их цену,
> коэффициент Жаккара. Из «Стримов по шагам» помнишь `groupingBy`
> с `flatMapping`, компараторы, `IntStream` и `double`.
>
> **Что будет.** Как превратить гостя в вектор из двенадцати чисел; чем
> угол между векторами отличается от расстояния по линейке; зачем
> приводить признаки к одному масштабу; как найти пять ближайших соседей
> одного гостя, сколько это стоит и где спотыкается `double`.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи на алгоритмы — в кузнице Stream Forge на платформе, в слое mind; здесь — теория к ним: приём, его цена и где он ломается. Примеры учебные: каждый запускается одним файлом.

---

## Зачем векторы

Данные — тот же месяц «Наковальни», что с
[первой статьи цикла](https://hammerhall.io/ledger/algorithms/1-set-algebra):
`orders(42, 300, 30)`, 2843 заказа.

Гость с картой 174 — новичок: за месяц зашёл трижды и взял три сырника,
два круассана, американо и эклер. В четвёртый раз бариста хочет
предложить ему новое — то, что понравится. Как угадать? Найти частых
гостей с похожим вкусом и посмотреть, что берут они, а он ещё нет. Так
устроены **рекомендации**: «тем, кто похож на тебя, нравится…».

Кто «похож»? Обычный [Жаккар из статьи 5](https://hammerhall.io/ledger/algorithms/5-jaccard)
видит только «брал или не брал». «Три сырника и эклер» и «сырник и три
эклера» для него — один набор, коэффициент 1, хотя вкусы
противоположные. Чтобы видеть «сколько», гостя превращают в строчку
чисел — вектор.

---

## Часть 1. Гость как вектор

### Штуки по позициям

Сначала — сколько штук каждой позиции взял каждый гость. Нужен
коллектор для группы из
[статьи 6 «Стримов»](https://hammerhall.io/ledger/streams/6-downstream-collectors) — здесь
им служит ещё один `groupingBy`:

```java
/** Сколько штук каждой позиции взял каждый гость: номер карты → (позиция → штук). */
Map<Integer, Map<String, Integer>> piecesByGuest(List<Order> orders) {
    return orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    flatMapping(order -> order.items().stream(),
                            groupingBy(Item::name, TreeMap::new, summingInt(Item::qty)))));
}
```

`flatMapping` достаёт из заказов гостя позиции, внутренний `groupingBy`
собирает их по названию, `summingInt(Item::qty)` считает штуки: два
какао в одном заказе — это 2.

```java
Map<Integer, Map<String, Integer>> pieces = piecesByGuest(orders);
IO.println("174: " + pieces.get(174));
IO.println("190: " + pieces.get(190));
```

```
174: {американо=1, круассан=2, сырник=3, эклер=1}
190: {американо=3, круассан=6, сырник=6, эклер=2}
```

Гость 190 — частый, десять визитов за месяц: позиции те же, только
каждой в два-три раза больше.

### Профиль — двенадцать чисел

Теперь каждого гостя — в строчку одной длины:

```java
/** Профиль гостя: сколько штук каждой позиции он взял — 12 чисел в порядке MENU. */
double[] profile(Map<String, Integer> pieces) {
    return MENU.stream()
            .mapToDouble(item -> pieces.getOrDefault(item.name(), 0))   // не брал — 0 штук
            .toArray();
}
```

**Вектор** — упорядоченный набор чисел, где у каждого места свой смысл.
Здесь место `i` — сколько штук гость взял позиции `MENU.get(i)`. Такой
вектор назовём **профилем** гостя. `profilesOf` собирает профили всех
гостей в карту «номер карты → профиль» — его код в «Примере целиком».

```java
Map<Integer, double[]> profiles = profilesOf(pieces);
double[] newcomer = profiles.get(174);
double[] profile190 = profiles.get(190);
IO.println(Arrays.toString(newcomer));
IO.println(Arrays.toString(profile190));
```

```
[0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 3.0, 1.0]
[0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 0.0, 6.0, 0.0, 6.0, 2.0]
```

Американо — место 3 (счёт с нуля), круассан — 8, сырник — 10,
эклер — 11, на остальных местах нули.

🔑 Порядок мест — один для всех гостей, иначе сравнишь эспрессо одного
с какао другого. У нас это порядок `MENU`, общий для всей серии.

Массив `double[]` — потому что профили будут умножать и делить, а простые
числа считаются без обёрток
([статья 8 «Стримов»](https://hammerhall.io/ledger/streams/8-number-streams)).

---

## Часть 2. Линейка и угол

### Расстояние по линейке

Возьмём две позиции, эспрессо и круассан, и трёх выдуманных гостей:

| гость | эспрессо | круассан |
|---|---|---|
| А | 6 | 8 |
| Б | 3 | 4 |
| В | 4 | 0 |

У А и Б вкус один: на три эспрессо — четыре круассана, просто Б заходит
вдвое реже. В берёт только эспрессо.

**Евклидово расстояние** — школьное расстояние между точками: по каждой
позиции разность в квадрат, квадраты сложить, из суммы корень.
А–Б: (6−3)² + (8−4)² = 25, корень — 5. Б–В: (3−4)² + (4−0)² = 17,
корень — примерно 4,123. По линейке Б ближе к В, чем к А, хотя вкус
у Б — как у А: линейка мерит не только вкус, но и объём.

### Угол: косинус

Представь вектор стрелкой из нуля в точку. Стрелки А и Б лежат на одной
прямой: Б короче, но смотрит туда же. Направление — это пропорции
вкуса, длина — объём. Значит, вкус сравнивают по углу.

Угол меряют **косинусом**: **скалярное произведение**, делённое
на произведение длин. Скалярное произведение — перемножить числа
на одних местах и сложить. **Длина** вектора — корень из суммы
квадратов его чисел, расстояние по линейке от нуля.

* А·Б = 6·3 + 8·4 = 50; длина А = √(36 + 64) = 10, длина Б = 5;
  косинус = 50 / (10 · 5) = 1.
* Б·В = 3·4 + 4·0 = 12; длина В = 4; косинус = 12 / (5 · 4) = 0,6.

Косинус 1 — стрелки смотрят в одну сторону: пропорции одинаковые,
сколько бы штук ни было. Косинус 0 — прямой угол: общих позиций нет.
Штуки не отрицательны, так что косинус профилей — от 0 до 1.

### Кодом

Каждая формула — проход по местам вектора:

```java
/** Скалярное произведение: сумма произведений чисел, стоящих на одних местах. */
double dot(double[] a, double[] b) {
    return IntStream.range(0, a.length)
            .mapToDouble(i -> a[i] * b[i])
            .sum();
}

/** Длина вектора: корень из его скалярного произведения на себя. */
double length(double[] a) {
    return Math.sqrt(dot(a, a));
}

/** Косинус угла между векторами: 1 — пропорции те же, 0 — ни одной общей позиции. */
double cosine(double[] a, double[] b) {
    distanceCalls++;
    return dot(a, b) / (length(a) * length(b));
}

/** Евклидово расстояние: корень из суммы квадратов разностей. */
double euclid(double[] a, double[] b) {
    distanceCalls++;
    return Math.sqrt(IntStream.range(0, a.length)
            .mapToDouble(i -> (a[i] - b[i]) * (a[i] - b[i]))
            .sum());
}
```

`distanceCalls` — поле-счётчик, как сравнения в
[статье 9 «Стримов»](https://hammerhall.io/ledger/streams/9-two-collections): по нему
в части 4 увидим цену. Сверим с ручным счётом (`show` — печать
с тремя знаками, о ней ниже):

```java
double[] a = {6, 8};
double[] b = {3, 4};
double[] c = {4, 0};
IO.println("линейка: А–Б " + show(euclid(a, b)) + ", Б–В " + show(euclid(b, c)));
IO.println("косинус: А–Б " + show(cosine(a, b)) + ", Б–В " + show(cosine(b, c)));
```

```
линейка: А–Б 5.000, Б–В 4.123
косинус: А–Б 1.000, Б–В 0.600
```

### Гости 174 и 190

Теперь настоящие гости: вкус один, частота разная.

```java
double far = euclid(newcomer, profile190);
IO.println("косинус " + show(cosine(newcomer, profile190)) + ", расстояние " + show(far));
long closer = profiles.keySet().stream()
        .filter(guest -> guest != 174 && guest != 190)
        .filter(guest -> euclid(newcomer, profiles.get(guest)) < far)
        .count();
IO.println("ближе к 174 по линейке, чем 190: " + closer + " гостей из " + (profiles.size() - 1));
```

```
косинус 0.980, расстояние 5.477
ближе к 174 по линейке, чем 190: 79 гостей из 293
```

По косинусу 190 — почти копия новичка. По линейке 79 гостей стоят
ближе, и все заходили меньше десяти раз, 63 — от одного
до четырёх: маленький вектор по линейке близок ко всем маленьким.

🔑 Косинус сравнивает пропорции — вкус. Линейка — вкус вместе
с объёмом. Меру выбирает вопрос: «что ему понравится» — косинус,
«кто берёт столько же» — линейка.

💡 Взвешенный Жаккар из статьи 5 штуки видит, но, как линейка,
наказывает за объём: у 174 и 190 он 7/17, около 0,412.

### double: печать и сравнение

Напечатаем косинус без округления:

```java
IO.println(cosine(newcomer, profile190));
IO.println(cosine(newcomer, newcomer));
IO.println(cosine(newcomer, newcomer) == 1.0);
```

```
0.9801960588196069
0.9999999999999999
false
```

Шестнадцать знаков, из которых важны три. Поэтому печатает помощник
`show` — `String.format(Locale.ROOT, "%.3f", x)`, как в
[статье 5](https://hammerhall.io/ledger/algorithms/5-jaccard).

⚠️ Вторая строка важнее: косинус гостя с самим собой — не единица.
Что вычисленные `double` не сравнивают через `==`, ты знаешь по
статье 5. Отсюда ещё одно правило: гостя исключают из его же соседей
по номеру карты, а не по «расстояние равно нулю» — до самого себя оно
здесь не ноль.

---

## Часть 3. Признаки разного масштаба

### Привычки гостя

Другой вопрос: кто похож на 174 не тем, что берёт, а тем, как ходит:
как часто, сколько тратит за визит, любит ли сладкое. Это три
**признака** — числа разной природы:

```java
/** Десерты меню — всё, что не пьют. */
static final Set<String> DESSERTS = Set.of("круассан", "чизкейк", "сырник", "эклер");

/** Привычки гостя: визитов за месяц, средний чек в рублях, доля десертов среди всех штук. */
double[] habitsOf(List<Order> visits) {
    double check = visits.stream().mapToInt(Order::total).average().orElseThrow();
    int all = visits.stream()
            .flatMap(order -> order.items().stream())
            .mapToInt(Item::qty)
            .sum();
    int sweet = visits.stream()
            .flatMap(order -> order.items().stream())
            .filter(item -> DESSERTS.contains(item.name()))
            .mapToInt(Item::qty)
            .sum();
    return new double[] {visits.size(), check, (double) sweet / all};
}
```

Визит здесь — заказ: генератор даёт гостю не больше одного заказа
в день. `(double)` до деления — как в статье 5.

Ближайшего ищет один проход: расстояние до каждого, наименьшее —
`min`. Гостя и расстояние держит запись:

```java
/** Гость и его расстояние до того, с кем сравниваем. */
record Neighbor(int guest, double distance) {}
```

```java
/** Ближайший к гостю query по евклидову расстоянию: один проход по всем остальным. */
Neighbor closest(int query, Map<Integer, double[]> vectors) {
    double[] target = vectors.get(query);
    return vectors.keySet().stream()
            .filter(guest -> guest != query)                      // себя — по номеру карты
            .map(guest -> new Neighbor(guest, euclid(target, vectors.get(guest))))
            .min(Comparator.comparingDouble(Neighbor::distance)
                    .thenComparingInt(Neighbor::guest))
            .orElseThrow();
}
```

Расстояние считается один раз на гостя, в `map`. При равных побеждает
меньший номер карты — зачем, в части 4.

### Без нормализации

```java
Map<Integer, double[]> habits = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                collectingAndThen(toList(), this::habitsOf)));
IO.println("174: " + show(habits.get(174)));
Neighbor raw = closest(174, habits);
IO.println("без нормализации: " + raw.guest() + " " + show(habits.get(raw.guest()))
        + ", расстояние " + show(raw.distance()));
IO.println("    он брал: " + pieces.get(raw.guest()));
```

```
174: [3.000, 450.000, 0.857]
без нормализации: 245 [3.000, 450.000, 0.125], расстояние 0.732
    он брал: {латте=2, чай=3, эклер=1, эспрессо=2}
```

`this::habitsOf` — ссылка на метод этого же файла, как `Order::guest` —
на метод записи.

У гостя 245 те же три визита и тот же чек, 450 ₽. Но десертов у него
12,5 % против 86 %: он пьёт чай и кофе, новичок ест сладкое. Вся эта
разница — 0,732 — весит меньше рубля чека. Чек у гостей от 150 до 710 ₽,
визитов от 1 до 24, доля от 0 до 1: признак с большими числами забирает
расстояние себе.

### z-оценка

Чтобы признаки весили честно, их приводят к одному масштабу — это
**нормализация**. Частый способ — **z-оценка**: из признака вычесть его
среднее по всем гостям и поделить на **стандартное отклонение** —
типичный разброс вокруг среднего. z = 2 — «на два разброса выше
среднего», в любых единицах.

Отклонение считают так: разности со средним — в квадрат, квадраты
усреднить, из среднего — корень. Если перед тобой все, о ком вопрос
(**генеральная совокупность**), сумму делят на n. Если **выборка**,
по которой судят обо всех, — на n−1: отклонения меряют от среднего
самой выборки, поэтому разброс в среднем выходит меньше настоящего,
и n−1 это поправляет. У нас все 294 гостя месяца — делим на n.

```java
double[] mean = IntStream.range(0, 3)
        .mapToDouble(k -> habits.values().stream().mapToDouble(v -> v[k]).average().orElseThrow())
        .toArray();
double[] spread = IntStream.range(0, 3)
        .mapToDouble(k -> Math.sqrt(habits.values().stream()
                .mapToDouble(v -> (v[k] - mean[k]) * (v[k] - mean[k]))
                .sum() / habits.size()))                   // делим на n: это все гости
        .toArray();
```

`k` — номер признака. Метод `zScore` переводит вектор:
`(vector[k] - mean[k]) / spread[k]` для каждого `k`. Правило статьи 5
«видишь деление — спроси про ноль» работает и здесь: у признака без
разброса z-оценка ломается, а у гостя без заказов профиль из нулей
и косинус — `NaN`.

```java
IO.println("среднее " + show(mean) + ", отклонение " + show(spread));
Map<Integer, double[]> scaled = habits.entrySet().stream()
        .collect(toMap(Map.Entry::getKey, entry -> zScore(entry.getValue(), mean, spread)));
IO.println("174 в z-оценках: " + show(scaled.get(174)));
Neighbor fair = closest(174, scaled);
IO.println("с нормализацией: " + fair.guest() + " " + show(habits.get(fair.guest()))
        + ", расстояние " + show(fair.distance()));
IO.println("    он брал: " + pieces.get(fair.guest()));
```

```
среднее [9.670, 414.973, 0.332], отклонение [5.674, 92.359, 0.220]
174 в z-оценках: [-1.176, 0.379, 2.383]
с нормализацией: 187 [3.000, 443.333, 1.000], расстояние 0.653
    он брал: {круассан=2, сырник=1, эклер=4}
```

Новичок ходит реже среднего (−1,18), чек чуть выше (+0,38), десертов
намного больше (+2,38). Ближайший теперь 187: три визита, чек на 7 ₽
меньше, одни десерты.

💡 Раздели на n−1 — ближайший не изменится: все z-оценки умножатся
на одно число, а с ними и все расстояния. Проверишь в «Сделай руками».

🔑 Прежде чем считать расстояние, приведи признаки к одному масштабу.
Профиль мы не нормализовали: там все числа — штуки, а объём убирает
косинус.

---

## Часть 4. k ближайших соседей

### Один запрос

**k ближайших соседей** (k nearest neighbors, kNN) одного гостя —
расстояние до каждого кандидата, сортировка по возрастанию, первые k.
Кандидаты — частые гости, от 10 визитов за месяц (`regularsOf`).
Мера — **косинусное расстояние** 1−cos: 0 при одинаковых пропорциях,
1 — без общих позиций. Не линейка: частые гости заходят от 10 до 24 раз,
новичок — 3. Не путай с соседями после сортировки из
[статьи 3](https://hammerhall.io/ledger/algorithms/3-all-pairs): там соседи по одному числу,
здесь — по расстоянию между векторами.

```java
/** k кандидатов, ближайших к гостю query по косинусному расстоянию 1 − cos. */
List<Neighbor> nearest(int query, List<Integer> candidates, Map<Integer, double[]> profiles, int k) {
    double[] target = profiles.get(query);
    return candidates.stream()
            .filter(guest -> guest != query)                      // себя — по номеру карты
            .map(guest -> new Neighbor(guest, 1 - cosine(target, profiles.get(guest))))
            .sorted(Comparator.comparingDouble(Neighbor::distance)
                    .thenComparingInt(Neighbor::guest))           // ничья — меньший номер карты
            .limit(k)
            .toList();
}
```

Это `closest`, только вместо `min` — сортировка и `limit(k)`.

```java
List<Integer> regulars = regularsOf(orders);
distanceCalls = 0;
List<Neighbor> five = nearest(174, regulars, profiles, 5);
five.forEach(n -> IO.println(n.guest() + "  " + show(n.distance()) + "  " + pieces.get(n.guest())));
IO.println("частых гостей: " + regulars.size() + ", расстояний посчитано: " + distanceCalls);
```

```
190  0.020  {американо=3, круассан=6, сырник=6, эклер=2}
91  0.078  {американо=2, капучино=1, круассан=7, латте=1, сырник=9, чизкейк=3}
30  0.087  {американо=3, капучино=1, круассан=8, латте=2, раф=2, сырник=6, чизкейк=1, эклер=3}
287  0.120  {какао=2, круассан=7, матча=1, сырник=9, чизкейк=2, эклер=2, эспрессо=4}
178  0.174  {какао=2, круассан=8, латте=1, сырник=4, эклер=3}
частых гостей: 142, расстояний посчитано: 142
```

Первый — 190 из части 2. Все пятеро едят круассаны и сырники.

### Что посоветовать

```java
Map<String, Integer> tried = pieces.get(174);
Map<String, Integer> advice = five.stream()
        .flatMap(n -> pieces.get(n.guest()).entrySet().stream())     // позиции соседей со штуками
        .filter(entry -> !tried.containsKey(entry.getKey()))          // он такого ещё не брал
        .collect(groupingBy(Map.Entry::getKey, summingInt(Map.Entry::getValue)));
List<Map.Entry<String, Integer>> ranked = advice.entrySet().stream()
        .sorted(Map.Entry.<String, Integer>comparingByValue().reversed()
                .thenComparing(Map.Entry.comparingByKey()))
        .toList();
IO.println("совет: " + ranked);
```

```
совет: [чизкейк=6, какао=4, латте=4, эспрессо=4, капучино=2, раф=2, матча=1]
```

Что новичок уже брал, отсеивает `containsKey`; остальное складывается
по названию и сортируется по штукам, ничьи — по алфавиту, как в
[статье 7 «Стримов»](https://hammerhall.io/ledger/streams/7-streams-over-maps). Чизкейк
брали трое из пяти — его бариста и предложит. Сбылось ли — проверишь
в «Сделай руками».

### Цена

Один запрос — 142 расстояния, каждое — три прохода по двенадцати
числам. А если гостей больше?

```java
for (int n : List.of(1000, 2000, 4000, 8000)) {
    List<Order> month = orders(42, n, 30);
    Map<Integer, Map<String, Integer>> monthPieces = piecesByGuest(month);
    long guests = monthPieces.size();                      // гости с заказами
    distanceCalls = 0;
    nearest(174, regularsOf(month), profilesOf(monthPieces), 5);
    IO.println(n + " гостей, с заказами " + guests + ": расстояний " + distanceCalls
            + ", пар «все со всеми» " + guests * (guests - 1) / 2);
}
```

```
1000 гостей, с заказами 982: расстояний 517, пар «все со всеми» 481671
2000 гостей, с заказами 1950: расстояний 1021, пар «все со всеми» 1900275
4000 гостей, с заказами 3916: расстояний 2019, пар «все со всеми» 7665570
8000 гостей, с заказами 7821: расстояний 4045, пар «все со всеми» 30580110
```

Гостей вдвое больше — расстояний тоже вдвое: число расстояний растёт
как n. «Соседи для всех» — это пары из статьи 3, n·(n−1)/2 по гостям
с заказами: при 8000 гостей 30,6 миллиона против 4045. Поэтому
рекомендацию считают для одного гостя — того, кто сейчас у кассы.

⚠️ Расстояние легко спрятать прямо в компаратор:

```java
distanceCalls = 0;
List<Integer> slow = regulars.stream()
        .sorted(Comparator
                .comparingDouble((Integer guest) -> 1 - cosine(newcomer, profiles.get(guest)))
                .thenComparingInt(guest -> guest))
        .limit(5)
        .toList();
IO.println(slow + ", расстояний посчитано: " + distanceCalls);
```

```
[190, 91, 30, 287, 178], расстояний посчитано: 1686
```

Ответ тот же, работы в двенадцать раз больше: сортировка 142 гостей
сделала 843 сравнения, и на каждом ключ считается для обоих. С записью
`Neighbor` их было 142. `(Integer guest)` — подсказка типа, как
в [статье 3 «Стримов»](https://hammerhall.io/ledger/streams/3-sorting): без неё лямбда перед `thenComparingInt` теряет тип
и код не компилируется.

### Ничьи

Хвост того же списка — все 142 частых гостя по порядку:

```java
List<Neighbor> all = nearest(174, regulars, profiles, regulars.size());
IO.println(all.subList(all.size() - 8, all.size()).stream()
        .map(n -> n.guest() + "=" + show(n.distance()))
        .toList());
```

```
[101=0.987, 39=1.000, 88=1.000, 95=1.000, 193=1.000, 202=1.000, 280=1.000, 292=1.000]
```

У семерых нет с новичком ни одной общей позиции: скалярное произведение
ровно 0, расстояние ровно 1 — настоящая ничья, а не совпадение после
округления. Кто из них первый, решает второй ключ — меньший номер карты.

Убери его — сегодня ничего не изменится: сортировка в стримах
устойчивая (статья 3 «Стримов»), равные остаются в порядке источника,
а `regularsOf` отдаёт номера по возрастанию. Но подай кандидатов
в другом порядке — и ничьи переставятся. Второй ключ делает порядок правилом, а не
случайностью источника.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что такое профиль гостя и почему для Жаккара «три сырника и эклер»
   и «сырник и три эклера» — одно, а для профилей нет?
2. Что в числителе и знаменателе косинуса? Почему у (6, 8) и (3, 4) он
   равен 1, хотя по линейке между ними 5?
3. Почему гости 174 и 190 близки по косинусу и далеки по линейке? Для
   какого вопроса нужна каждая мера?
4. Почему без нормализации ближайшим вышел гость с тем же чеком? Что
   делает z-оценка и почему мы делим на n, а не на n−1?
5. Сколько расстояний считает один запрос и сколько пар — «соседи для
   всех»? Почему расстояние не считают в компараторе?
6. Почему косинус гостя с самим собой — не 1 и как поэтому исключать
   гостя из его соседей?
7. Откуда семь гостей с расстоянием ровно 1 и кто из них первый? Что
   будет без второго ключа?

---

## Что дальше

Это последняя статья цикла А «Сравнить коллекции»: множества, ключи,
пары, индекс, Жаккар — и векторы. Следующий цикл — «Порядок и соседи»:
сортировка и сканирование, серии, окна. Он готовится.

## Первоисточники

* [Introduction to Information Retrieval, 6.3.1 Dot products](https://nlp.stanford.edu/IR-book/html/htmledition/dot-products-1.html) —
  косинус и почему разность векторов обманывает на документах разной
  длины.
* [J. Leskovec. Recommender Systems — Stanford CS246](https://web.stanford.edu/class/cs246/slides/07-recsys1.pdf) —
  рекомендации по k самым похожим пользователям и цена их поиска.
* [Online Statistics Education: z score](https://onlinestatbook.com/2/glossary/z_score.html)
  и [Measures of Variability](https://onlinestatbook.com/2/summarizing_distributions/variabilityC.html) —
  z-оценка, стандартное отклонение, поправка для выборки.
* [Class Double — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Double.html) —
  равенство и сравнение `double`.
* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  `sorted`: устойчивая сортировка упорядоченных стримов.

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
не нужно. Последний блок генерирует месяцы до 8000 гостей — подожди
пару секунд. Если вместо русских букв в выводе вопросы или
кракозябры, запусти с явной кодировкой — аргументы в кавычках, так их
поймёт и PowerShell: `java "-Dstdout.encoding=UTF-8" "-Dstderr.encoding=UTF-8" Coffee.java`;
в командной строке Windows перед этим выполни `chcp 65001`.

```java
// Coffee.java — учебный пример статьи 6 серии «Алгоритмы на стримах».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeMap;
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

/** Гость и его расстояние до того, с кем сравниваем. */
record Neighbor(int guest, double distance) {}

long distanceCalls = 0;   // сколько раз посчитали расстояние — чтобы увидеть цену

/** Сколько штук каждой позиции взял каждый гость: номер карты → (позиция → штук). */
Map<Integer, Map<String, Integer>> piecesByGuest(List<Order> orders) {
    return orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    flatMapping(order -> order.items().stream(),
                            groupingBy(Item::name, TreeMap::new, summingInt(Item::qty)))));
}

/** Профиль гостя: сколько штук каждой позиции он взял — 12 чисел в порядке MENU. */
double[] profile(Map<String, Integer> pieces) {
    return MENU.stream()
            .mapToDouble(item -> pieces.getOrDefault(item.name(), 0))   // не брал — 0 штук
            .toArray();
}

/** Профили всех гостей: номер карты → вектор. */
Map<Integer, double[]> profilesOf(Map<Integer, Map<String, Integer>> pieces) {
    return pieces.entrySet().stream()
            .collect(toMap(Map.Entry::getKey, entry -> profile(entry.getValue())));
}

/** Частые гости — от 10 визитов за месяц, по возрастанию номера карты. */
List<Integer> regularsOf(List<Order> orders) {
    return orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new, counting()))
            .entrySet().stream()
            .filter(entry -> entry.getValue() >= 10)
            .map(Map.Entry::getKey)
            .toList();
}

/** Скалярное произведение: сумма произведений чисел, стоящих на одних местах. */
double dot(double[] a, double[] b) {
    return IntStream.range(0, a.length)
            .mapToDouble(i -> a[i] * b[i])
            .sum();
}

/** Длина вектора: корень из его скалярного произведения на себя. */
double length(double[] a) {
    return Math.sqrt(dot(a, a));
}

/** Косинус угла между векторами: 1 — пропорции те же, 0 — ни одной общей позиции. */
double cosine(double[] a, double[] b) {
    distanceCalls++;
    return dot(a, b) / (length(a) * length(b));
}

/** Евклидово расстояние: корень из суммы квадратов разностей. */
double euclid(double[] a, double[] b) {
    distanceCalls++;
    return Math.sqrt(IntStream.range(0, a.length)
            .mapToDouble(i -> (a[i] - b[i]) * (a[i] - b[i]))
            .sum());
}

/** Число для печати: три знака после точки. Locale.ROOT — точка на любом компьютере. */
String show(double x) {
    return String.format(Locale.ROOT, "%.3f", x);
}

/** Вектор для печати: каждое число — с тремя знаками. */
String show(double[] vector) {
    return Arrays.stream(vector)
            .mapToObj(this::show)
            .collect(joining(", ", "[", "]"));
}

/** Десерты меню — всё, что не пьют. */
static final Set<String> DESSERTS = Set.of("круассан", "чизкейк", "сырник", "эклер");

/** Привычки гостя: визитов за месяц, средний чек в рублях, доля десертов среди всех штук. */
double[] habitsOf(List<Order> visits) {
    double check = visits.stream().mapToInt(Order::total).average().orElseThrow();
    int all = visits.stream()
            .flatMap(order -> order.items().stream())
            .mapToInt(Item::qty)
            .sum();
    int sweet = visits.stream()
            .flatMap(order -> order.items().stream())
            .filter(item -> DESSERTS.contains(item.name()))
            .mapToInt(Item::qty)
            .sum();
    return new double[] {visits.size(), check, (double) sweet / all};
}

/** z-оценки: на сколько стандартных отклонений каждый признак выше или ниже среднего. */
double[] zScore(double[] vector, double[] mean, double[] spread) {
    return IntStream.range(0, vector.length)
            .mapToDouble(k -> (vector[k] - mean[k]) / spread[k])
            .toArray();
}

/** Ближайший к гостю query по евклидову расстоянию: один проход по всем остальным. */
Neighbor closest(int query, Map<Integer, double[]> vectors) {
    double[] target = vectors.get(query);
    return vectors.keySet().stream()
            .filter(guest -> guest != query)                      // себя — по номеру карты
            .map(guest -> new Neighbor(guest, euclid(target, vectors.get(guest))))
            .min(Comparator.comparingDouble(Neighbor::distance)
                    .thenComparingInt(Neighbor::guest))
            .orElseThrow();
}

/** k кандидатов, ближайших к гостю query по косинусному расстоянию 1 − cos. */
List<Neighbor> nearest(int query, List<Integer> candidates, Map<Integer, double[]> profiles, int k) {
    double[] target = profiles.get(query);
    return candidates.stream()
            .filter(guest -> guest != query)                      // себя — по номеру карты
            .map(guest -> new Neighbor(guest, 1 - cosine(target, profiles.get(guest))))
            .sorted(Comparator.comparingDouble(Neighbor::distance)
                    .thenComparingInt(Neighbor::guest))           // ничья — меньший номер карты
            .limit(k)
            .toList();
}

void main() {
    List<Order> orders = orders(42, 300, 30);

    // 1. Сколько штук каждой позиции взял каждый гость
    Map<Integer, Map<String, Integer>> pieces = piecesByGuest(orders);
    IO.println("174: " + pieces.get(174));
    IO.println("190: " + pieces.get(190));

    // 2. Профиль — вектор из 12 чисел в порядке меню
    Map<Integer, double[]> profiles = profilesOf(pieces);
    double[] newcomer = profiles.get(174);
    double[] profile190 = profiles.get(190);
    IO.println(Arrays.toString(newcomer));
    IO.println(Arrays.toString(profile190));

    // 3. Пример руками: А = (6, 8), Б = (3, 4), В = (4, 0)
    double[] a = {6, 8};
    double[] b = {3, 4};
    double[] c = {4, 0};
    IO.println("линейка: А–Б " + show(euclid(a, b)) + ", Б–В " + show(euclid(b, c)));
    IO.println("косинус: А–Б " + show(cosine(a, b)) + ", Б–В " + show(cosine(b, c)));

    // 4. Гости 174 и 190: вкус один, частота разная
    double far = euclid(newcomer, profile190);
    IO.println("косинус " + show(cosine(newcomer, profile190)) + ", расстояние " + show(far));
    long closer = profiles.keySet().stream()
            .filter(guest -> guest != 174 && guest != 190)
            .filter(guest -> euclid(newcomer, profiles.get(guest)) < far)
            .count();
    IO.println("ближе к 174 по линейке, чем 190: " + closer + " гостей из " + (profiles.size() - 1));

    // 5. double: печать без округления и сравнение
    IO.println(cosine(newcomer, profile190));
    IO.println(cosine(newcomer, newcomer));
    IO.println(cosine(newcomer, newcomer) == 1.0);

    // 6. Привычки: визиты, средний чек, доля десертов — и ближайший без нормализации
    Map<Integer, double[]> habits = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    collectingAndThen(toList(), this::habitsOf)));
    IO.println("174: " + show(habits.get(174)));
    Neighbor raw = closest(174, habits);
    IO.println("без нормализации: " + raw.guest() + " " + show(habits.get(raw.guest()))
            + ", расстояние " + show(raw.distance()));
    IO.println("    он брал: " + pieces.get(raw.guest()));

    // 7. z-оценки: среднее и стандартное отклонение каждого признака по всем гостям
    double[] mean = IntStream.range(0, 3)
            .mapToDouble(k -> habits.values().stream().mapToDouble(v -> v[k]).average().orElseThrow())
            .toArray();
    double[] spread = IntStream.range(0, 3)
            .mapToDouble(k -> Math.sqrt(habits.values().stream()
                    .mapToDouble(v -> (v[k] - mean[k]) * (v[k] - mean[k]))
                    .sum() / habits.size()))                   // делим на n: это все гости
            .toArray();
    IO.println("среднее " + show(mean) + ", отклонение " + show(spread));
    Map<Integer, double[]> scaled = habits.entrySet().stream()
            .collect(toMap(Map.Entry::getKey, entry -> zScore(entry.getValue(), mean, spread)));
    IO.println("174 в z-оценках: " + show(scaled.get(174)));
    Neighbor fair = closest(174, scaled);
    IO.println("с нормализацией: " + fair.guest() + " " + show(habits.get(fair.guest()))
            + ", расстояние " + show(fair.distance()));
    IO.println("    он брал: " + pieces.get(fair.guest()));

    // 8. Пять частых гостей, ближайших к новичку 174
    List<Integer> regulars = regularsOf(orders);
    distanceCalls = 0;
    List<Neighbor> five = nearest(174, regulars, profiles, 5);
    five.forEach(n -> IO.println(n.guest() + "  " + show(n.distance()) + "  " + pieces.get(n.guest())));
    IO.println("частых гостей: " + regulars.size() + ", расстояний посчитано: " + distanceCalls);

    // 9. Что они берут, чего он ещё не пробовал
    Map<String, Integer> tried = pieces.get(174);
    Map<String, Integer> advice = five.stream()
            .flatMap(n -> pieces.get(n.guest()).entrySet().stream())     // позиции соседей со штуками
            .filter(entry -> !tried.containsKey(entry.getKey()))          // он такого ещё не брал
            .collect(groupingBy(Map.Entry::getKey, summingInt(Map.Entry::getValue)));
    List<Map.Entry<String, Integer>> ranked = advice.entrySet().stream()
            .sorted(Map.Entry.<String, Integer>comparingByValue().reversed()
                    .thenComparing(Map.Entry.comparingByKey()))
            .toList();
    IO.println("совет: " + ranked);

    // 10. Ничьи: хвост списка всех частых гостей
    List<Neighbor> all = nearest(174, regulars, profiles, regulars.size());
    IO.println(all.subList(all.size() - 8, all.size()).stream()
            .map(n -> n.guest() + "=" + show(n.distance()))
            .toList());

    // 11. Расстояние прямо в компараторе — считается на каждом сравнении
    distanceCalls = 0;
    List<Integer> slow = regulars.stream()
            .sorted(Comparator
                    .comparingDouble((Integer guest) -> 1 - cosine(newcomer, profiles.get(guest)))
                    .thenComparingInt(guest -> guest))
            .limit(5)
            .toList();
    IO.println(slow + ", расстояний посчитано: " + distanceCalls);

    // 12. Цена одного запроса при росте данных
    for (int n : List.of(1000, 2000, 4000, 8000)) {
        List<Order> month = orders(42, n, 30);
        Map<Integer, Map<String, Integer>> monthPieces = piecesByGuest(month);
        long guests = monthPieces.size();                      // гости с заказами
        distanceCalls = 0;
        nearest(174, regularsOf(month), profilesOf(monthPieces), 5);
        IO.println(n + " гостей, с заказами " + guests + ": расстояний " + distanceCalls
                + ", пар «все со всеми» " + guests * (guests - 1) / 2);
    }
}
```

Сделай руками:

1. Запусти файл. Найди строки `косинус 0.980, расстояние 5.477`,
   `с нормализацией: 187 …` и `совет: [чизкейк=6, …]`.
2. В методе `nearest` замени `1 - cosine(target, profiles.get(guest))`
   на `euclid(target, profiles.get(guest))`. Пятёрка станет
   `190, 178, 54, 112, 77`, а совет начнётся с `какао=8`: линейка тянет
   к самым редким из частых гостей — у всех пятерых по 10–11 визитов.
   Верни как было.
3. В блоке `// 7.` замени `/ habits.size()` на `/ (habits.size() - 1)`.
   Отклонения подрастут — `[5.684, 92.516, 0.221]`, — ближайшим
   останется 187, расстояние станет `0.652`. Верни как было.
4. В методе `nearest` замени две строки
   `.sorted(Comparator.comparingDouble(Neighbor::distance)` и
   `.thenComparingInt(Neighbor::guest))` одной:
   `.sorted(Comparator.comparingDouble(Neighbor::distance))`. Хвост
   не изменится. Теперь в блоке `// 10.` замени `nearest(174, regulars,`
   на `nearest(174, regulars.reversed(),` — семеро с `1.000` выйдут
   в обратном порядке: `292, 280, 202, 193, 95, 88, 39`. Верни второй
   ключ — порядок снова `39, 88, …`, хотя источник перевёрнут. Верни
   всё как было.
5. Проверь совет. Добавь в конец `main`:

   ```java
   orders(42, 300, 60).stream()
           .filter(order -> order.guest() == 174 && order.day() > 30)
           .forEach(order -> IO.println(order.day() + ": " + order.items()));
   ```

   Генератор берёт случайные числа из одного зерна по порядку: сначала
   вкусы гостей, потом день за днём. Число дней не влияет на случайные
   числа первых 30 дней, поэтому дни 1–30 из 60 — ровно наш месяц,
   а дни 31–60 — следующий. Гость 174 придёт четыре раза, и в трёх
   заказах будет чизкейк.
6. Добавь в конец `main` строку
   `IO.println(show(cosine(profiles.get(97), profiles.get(23))) + " " + show(euclid(profiles.get(97), profiles.get(23))));`
   — выйдет `0.955 18.628`. Напечатай `pieces.get(97)` и `pieces.get(23)`:
   у обоих главное — латте, раф и матча, но 97 заходил 20 раз, а 23 —
   дважды.
