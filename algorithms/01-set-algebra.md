# Множества как алгебра: пересечение, разность, подмножество

> «Сравнить коллекции» · статья 1 · читать минут 20
>
> **Для кого.** Ты прошёл «Стримы по шагам» или знаешь то же сам:
> `flatMap` и `HashSet`, `groupingBy`, стрим по карте, `reduce`, индекс
> вместо стрима в стриме. Множества из математики знать не нужно.
>
> **Что будет.** Новые данные серии — месяц кофейни. Пересечение,
> объединение, разность; подмножество, равенство, «нет общего». Почему
> перед `retainAll` нужна копия, как пересечь сразу много множеств
> и почему `contains` у списка и у `HashSet` стоит по-разному.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи на алгоритмы — в кузнице Stream Forge на платформе, в слое mind; здесь — теория к ним: приём, его цена и где он ломается. Примеры учебные: каждый запускается одним файлом.

---

## Зачем множества

В «Стримах по шагам» у кофейни «Наковальня» был один день — десять
заказов. Теперь — месяц: 300 гостей, 30 дней, 2843 заказа; заказы есть
у 294 гостей. Их порождает генератор случайных чисел с постоянным
**зерном** — числом, с которого он начинает, — поэтому на любом
компьютере заказы выходят одни и те же. У заказа появились день месяца
и номер карты гостя — `int guest` вместо имени; генератор одинаковый
во всех статьях серии и стоит в начале «Примера целиком».

```java
IO.println(orders(42, 300, 30).get(0));
```

```
Order[number=1, day=1, guest=2, items=[Item[name=чай, price=120, qty=1], Item[name=какао, price=200, qty=2]]]
```

Зерно 42, 300 гостей, 30 дней; первый заказ — первое число, гость
с картой 2, чай и два какао. Дальше в примерах `orders` — этот месяц:
`List<Order> orders = orders(42, 300, 30);`.

Хозяйка присматривается к гостю 17. За месяц он заходил десять раз;
15-го взял эклер — и больше ни разу. Что гость перестал брать, что
начал, что брал и до, и после, брал ли что-нибудь, кроме напитков?

Списком отвечать неудобно. В дни 1–15 в его заказах шесть позиций:
эспрессо, капучино, капучино, капучино, эспрессо, эклер — повторов
полно. На каждый вопрос — свой фильтр с `contains` и `distinct`,
и каждый раз вспоминай, в каком списке искать.

У этих вопросов давно есть имена. Множество — набор без повторов
и без порядка, а «что общего», «что пропало» — действия над
множествами, как сложение и вычитание над числами. Отсюда **алгебра
множеств**: свои действия и свои правила. В Java у каждого действия
есть метод интерфейса `Set`.

🔑 Вопрос «что общего», «чего не хватает» или «всё ли входит» — это
вопрос о множествах. Сначала назови действие, потом выбирай метод.

---

## Часть 1. Множество гостя

### Из заказов — в множество

Что брал гость за несколько дней — это множество названий. Метод
собирает его стримом:

```java
/** Что брал гость с дня from по день to включительно: названия позиций без повторов, по алфавиту. */
Set<String> itemsOf(List<Order> orders, int guest, int from, int to) {
    return orders.stream()
            .filter(order -> order.guest() == guest && order.day() >= from && order.day() <= to)
            .flatMap(order -> order.items().stream())
            .map(Item::name)
            .collect(Collectors.toCollection(TreeSet::new));
}
```

Начало знакомо: отобрать заказы, `flatMap` — из заказов в позиции
([статья 4 «Стримов»](https://hammerhall.io/ledger/streams/4-flatmap)), `map` — в названия. Новое —
в конце. `Collectors.toCollection` складывает элементы в коллекцию,
которую создаст фабрика, — здесь ссылка на конструктор `TreeSet::new`,
как `TreeMap::new` в [статье 5 «Стримов»](https://hammerhall.io/ledger/streams/5-grouping).
**`TreeSet`** — множество, которое держит элементы по порядку; у строк
это алфавит. Повторов в нём нет: каждое название хранится один раз.

```java
Set<String> before = itemsOf(orders, 17, 1, 15);
Set<String> after = itemsOf(orders, 17, 16, 30);
IO.println("дни 1–15: " + before + ", дни 16–30: " + after);
```

```
дни 1–15: [капучино, эклер, эспрессо], дни 16–30: [какао, капучино, эспрессо]
```

Шесть позиций первой половины сжались в три названия, восемь второй —
тоже в три.

### Множество, заданное руками

Напитки меню не собирают из заказов, а перечисляют:

```java
/** Напитки меню, остальное — десерты. Set.of — неизменяемое множество. */
static final Set<String> DRINKS = Set.of("латте", "капучино", "эспрессо", "американо", "раф", "какао", "матча", "чай");
```

`Set.of` — множество из перечисленного. Оно неизменяемое: ни
добавить, ни убрать элемент нельзя — как в списке из `toList()`
([статья 1 «Стримов»](https://hammerhall.io/ledger/streams/1-stream-instead-of-loop)).

⚠️ Не печатай такое множество в ответ. `HashSet` порядок не обещает
([статья 4 «Стримов»](https://hammerhall.io/ledger/streams/4-flatmap)), а у `Set.of` он
меняется от запуска к запуску. Два запуска `IO.println(DRINKS)` подряд:

```
[капучино, американо, матча, раф, какао, чай, латте, эспрессо]
[латте, чай, какао, раф, матча, американо, капучино, эспрессо]
```

Документация `Set`: порядок обхода не определён и может меняться.
Ответ, который сверяют глазами или как строку, печатай из `TreeSet`.

---

## Часть 2. Пересечение, объединение, разность

### Пересечение — что есть в обоих

**Пересечение** A ∩ B (читается «A пересечь B») — то, что есть
и в A, и в B. Руками для гостя 17: идём по
A = {капучино, эклер, эспрессо} и про каждое спрашиваем, есть ли оно
в B = {какао, капучино, эспрессо}: капучино — да, эклер — нет,
эспрессо — да. A ∩ B = {капучино, эспрессо}.

В Java пересечение делает `retainAll(b)` — «оставь только то, что есть
в b»; документация `Set` так его и называет — пересечение. Но делает
**на месте**: меняет множество, у которого вызван. Поэтому сначала
копия:

```java
/** Пересечение: что есть и в a, и в b. Ответ — новое множество, a и b не меняются. */
Set<String> intersection(Set<String> a, Set<String> b) {
    Set<String> result = new TreeSet<>(a);   // копия: retainAll меняет множество, у которого вызван
    result.retainAll(b);
    return result;
}
```

`new TreeSet<>(a)` — новое множество с теми же элементами, дальше оно
живёт отдельно от `a`.

```java
IO.println("осталось:        " + intersection(before, after));
IO.println("осталось, стрим: " + before.stream().filter(after::contains).toList());
```

```
осталось:        [капучино, эспрессо]
осталось, стрим: [капучино, эспрессо]
```

Вторая строка — то же пересечение стримом: `filter` оставляет из
`before` то, что `contains` находит в `after`. `after::contains` —
то же, что `item -> after.contains(item)`, как `IO::println`
в [статье 2 «Стримов»](https://hammerhall.io/ledger/streams/2-filter-map-optional). Стрим ничего
не меняет. Запомни эту строку — в части 4 она покажет цену.

### Объединение и разность

**Объединение** A ∪ B («A объединить B») — то, что есть хотя бы в одном
из двух: метод `addAll`. **Разность** A \ B («A без B») — то, что есть
в A, но нет в B: метод `removeAll`. Оба тоже меняют множество на месте —
значит, копия и одно действие.

```java
/** Объединение: что есть хотя бы в одном из двух. */
Set<String> union(Set<String> a, Set<String> b) {
    Set<String> result = new TreeSet<>(a);
    result.addAll(b);
    return result;
}

/** Разность: что есть в a, но нет в b. */
Set<String> difference(Set<String> a, Set<String> b) {
    Set<String> result = new TreeSet<>(a);
    result.removeAll(b);
    return result;
}
```

```java
IO.println("всё за месяц:    " + union(before, after));
IO.println("перестал брать:  " + difference(before, after));
IO.println("начал брать:     " + difference(after, before));
```

```
всё за месяц:    [какао, капучино, эклер, эспрессо]
перестал брать:  [эклер]
начал брать:     [какао]
```

У пересечения и объединения от перестановки A и B ответ не меняется:
A ∩ B = B ∩ A. У разности меняется: «до без после» — что гость
перестал брать, «после без до» — что начал. Перепутаешь — компилятор
не заметит.

### Симметрическая разность

**Симметрическая разность** A Δ B («A дельта B») — то, что есть ровно
в одном из двух: всё, что сменилось. Своего метода у неё нет — она
складывается из других: объединение без пересечения.

```java
IO.println("сменилось:       " + difference(union(before, after), intersection(before, after)));
```

```
сменилось:       [какао, эклер]
```

| действие | что это | в Java | у гостя 17 |
|---|---|---|---|
| A ∩ B, пересечение | есть в обоих | `retainAll` | [капучино, эспрессо] |
| A ∪ B, объединение | есть хотя бы в одном | `addAll` | [какао, капучино, эклер, эспрессо] |
| A \ B, разность | есть в A, нет в B | `removeAll` | [эклер] |
| A Δ B, симметрическая разность | есть ровно в одном | (A ∪ B) \ (A ∩ B) | [какао, эклер] |

### ⚠️ Без копии

Что будет, если вызвать `retainAll` прямо у `before`:

```java
before.retainAll(after);                       // без копии — меняем само before
IO.println("осталось:       " + before);
IO.println("перестал брать: " + difference(before, after));
```

```
осталось:       [капучино, эспрессо]
перестал брать: []
```

Пересечение верное, но эклер из `before` выброшен навсегда, и разность
ответила «ничего не перестал». Исключения нет, ответ неверный.

🔑 `retainAll`, `addAll` и `removeAll` меняют множество, у которого
вызваны. Нужны исходные множества дальше — работай с копией.

### ⚠️ Неизменяемое множество

Какие напитки брал гость в дни 1–15? Хочется написать так:

```java
DRINKS.retainAll(before);   // UnsupportedOperationException
```

```
Exception in thread "main" java.lang.UnsupportedOperationException
```

Документация `Set`: у неизменяемого множества — из `Set.of` или
`Set.copyOf` — любой метод, меняющий содержимое, всегда бросает это
исключение. Лечится той же копией: `intersection(DRINKS, before)`.

---

## Часть 3. Вопросы «да или нет»

### Подмножество — всё ли входит

**Подмножество** A ⊆ B («A входит в B») — всё, что есть в A, есть
и в B. Гость брал только напитки — значит, его множество за месяц
входит в `DRINKS`. В Java это `b.containsAll(a)`: «есть ли в b всё
из a»; документация `Set` и тут говорит «подмножество».

```java
IO.println("гость 2 — только напитки:  " + DRINKS.containsAll(itemsOf(orders, 2, 1, 30)));
IO.println("гость 17 — только напитки: " + DRINKS.containsAll(itemsOf(orders, 17, 1, 30)));
```

```
гость 2 — только напитки:  true
гость 17 — только напитки: false
```

Гость 2 за месяц брал какао, капучино, матчу, чай и эспрессо — всё
напитки. Гостю 17 помешал эклер.

⚠️ Направление важно. `itemsOf(orders, 2, 1, 30).containsAll(DRINKS)` —
другой вопрос: «перепробовал ли гость 2 все напитки». Ответ — `false`.

### Равенство — одно и то же

Множества **равны**, если в них одни и те же элементы: каждое входит
в другое. Так и сравнивает `equals` у `Set` — по содержимому, не глядя
на класс. `List.equals` требует ещё и порядка:

```java
IO.println("HashSet и TreeSet: " + new HashSet<>(before).equals(before));
IO.println("до и после:        " + before.equals(after));
IO.println("два списка:        " + List.of("капучино", "эспрессо").equals(List.of("эспрессо", "капучино")));
```

```
HashSet и TreeSet: true
до и после:        false
два списка:        false
```

`HashSet` и `TreeSet` хранят элементы по-разному, но с одними
элементами равны: документация `Set` обещает это для любых реализаций.
Списки из тех же названий в другом порядке — не равны.

💡 «Набор равен такому-то», «набор содержит такой-то» и «набор входит
в такой-то» — три разных вопроса: `equals` и `containsAll` в одну
сторону и в другую. Прежде чем писать код, реши, какой из трёх тебе
задали.

### Нет общего — Collections.disjoint

Хозяйка хочет позвать гостей 17 и 7 на дегустацию одной позиции,
которую любят оба. Есть ли такая? Два множества **не пересекаются**,
если общих элементов нет: пересечение — ∅, «пустое множество».
Проверка — `Collections.disjoint`:

```java
Set<String> month17 = itemsOf(orders, 17, 1, 30);
IO.println("у 17 и 7 общего нет: " + Collections.disjoint(month17, itemsOf(orders, 7, 1, 30)));
IO.println("у 17 и 2 общего нет: " + Collections.disjoint(month17, itemsOf(orders, 2, 1, 30)));
```

```
у 17 и 7 общего нет: true
у 17 и 2 общего нет: false
```

Гость 7 за месяц брал только матчу и чай — с гостем 17 общего нет.
С гостем 2 общее есть: какао, капучино, эспрессо.

### Пересечение многих — свёртка

Что брали все самые частые гости (22 визита и больше)?
Их четверо: 86, 182, 264 и 265. Пересечь четыре — значит пересечь
первые два, ответ — с третьим, потом с четвёртым. Это свёртка `reduce`
из [статьи 8 «Стримов»](https://hammerhall.io/ledger/streams/8-number-streams): начальное
значение и действие, которое по очереди присоединяет каждый элемент.

```java
Map<Integer, Long> visits = orders.stream()
        .collect(Collectors.groupingBy(Order::guest, Collectors.counting()));
Set<String> menu = MENU.stream().map(Item::name).collect(Collectors.toCollection(TreeSet::new));
Set<String> frequentCommon = visits.entrySet().stream()
        .filter(entry -> entry.getValue() >= 22)
        .map(entry -> itemsOf(orders, entry.getKey(), 1, 30))
        .reduce(menu, (common, items) -> intersection(common, items));
IO.println("общее у самых частых: " + frequentCommon);
```

```
общее у самых частых: [какао]
```

`visits` — сколько заказов у каждого гостя (`groupingBy`
с `counting()`). Стрим по карте отбирает самых частых и превращает
каждого в его множество за месяц, `reduce` пересекает их по очереди.
Всех четверых объединяет какао.

⚠️ Начальное значение — всё меню, а не пустое множество. У суммы начало
— 0: прибавить ноль — ничего не изменить. У пересечения такое начало —
всё меню: пересечь с ним — получить то же самое. Документация `reduce`
требует именно этого. Начни с пустого `new TreeSet<>()` — и ответ всегда
будет `[]`. И действие — `intersection` с копией: `retainAll` первым же
шагом изменил бы само `menu`.

💡 Если таких гостей нет вовсе, ответом выйдет всё меню: у пустого стрима
`reduce` возвращает начальное значение. Чтобы отличить «никого нет»,
бери `reduce` без начального значения: он отвечает `Optional`.

---

## Часть 4. Цена: contains у списка и у множества

### Одно пересечение, две коллекции

Почти все действия статьи держатся на `contains` — есть ли элемент
в другой коллекции. Документация так и описывает `retainAll`: идёт
по своим элементам и про каждый спрашивает `contains` у аргумента.
На двенадцати позициях меню цены не видно — возьмём гостей.

Кто из гостей первых десяти дней вернулся в последние десять? Это
пересечение двух коллекций номеров карт:

```java
/** Гости, которые заходили с дня from по день to: номера карт без повторов, в порядке первого визита. */
List<Integer> visitors(List<Order> orders, int from, int to) {
    return orders.stream()
            .filter(order -> order.day() >= from && order.day() <= to)
            .map(Order::guest)
            .distinct()
            .toList();
}
```

```java
List<Integer> early = visitors(orders, 1, 10);
List<Integer> late = visitors(orders, 21, 30);
Set<Integer> lateSet = new HashSet<>(late);
List<Integer> backByList = early.stream().filter(late::contains).toList();      // contains списка
List<Integer> backBySet = early.stream().filter(lateSet::contains).toList();    // contains множества
IO.println("вернулись " + backBySet.size() + " из " + early.size() + ", ответы равны: " + backByList.equals(backBySet));
```

```
вернулись 233 из 254, ответы равны: true
```

Тот же `filter(…::contains)`, что в части 2. Ответ один, работа —
разная.

### Сколько сравнивает список

`contains` у списка ищет с начала: сравнивает гостя с первым
элементом, со вторым — пока не найдёт. Сколько сравнил, он не скажет,
но `indexOf` ищет так же и говорит, где остановился. Нашёл на месте
`index` — сравнений было `index + 1`; не нашёл (`-1`) — сравнил
со всеми:

```java
/** Сколько всего сравнений сделает contains списка list, если спросить его о каждом госте из who. */
long listComparisons(List<Integer> who, List<Integer> list) {
    return who.stream()
            .mapToLong(guest -> {
                int index = list.indexOf(guest);               // contains ищет так же: с начала списка
                return index >= 0 ? index + 1 : list.size();   // нашёл на месте index — index + 1 сравнений
            })
            .sum();
}
```

```java
IO.println("список: сравнений " + listComparisons(early, late)
        + "; множество: добавлений " + late.size() + ", обращений " + early.size());
```

```
список: сравнений 34252; множество: добавлений 262, обращений 254
```

В первой декаде n = 254 гостя, в последней m = 262. Сравнить всех
со всеми — n · m = 66 548; список сделал примерно половину: найденного
гостя он в среднем находит на середине, ненайденного ищет до конца.

У `HashSet` работа другая: 262 раза добавить гостя и 254 раза спросить
`contains`. Каждое обращение — не проход, а прыжок: `hashCode` ведёт
сразу к нужному крючку, как номерок в гардеробе из
[статьи 4 «Стримов»](https://hammerhall.io/ledger/streams/4-flatmap).
Документация `HashSet` обещает для `add` и `contains` постоянное время,
не зависящее от размера, если хеш раскладывает элементы равномерно.
Итого n + m = 516 шагов.

### Когда гостей вдвое больше

Генератор делает месяц для любого числа гостей — `orders(42, n, 30)`:

```java
for (int guests : List.of(1000, 2000, 4000, 8000)) {
    List<Order> month = orders(42, guests, 30);
    List<Integer> first = visitors(month, 1, 10);
    List<Integer> last = visitors(month, 21, 30);
    IO.println(guests + " гостей: список " + listComparisons(first, last)
            + ", множество " + (last.size() + first.size()));
}
```

```
1000 гостей: список 425976, множество 1794
2000 гостей: список 1674660, множество 3564
4000 гостей: список 6640572, множество 7107
8000 гостей: список 26485356, множество 14193
```

Гостей вдвое больше — у списка сравнений почти вчетверо больше,
у множества шагов вдвое. Работа списка растёт как произведение
размеров, O(n·m) — помнишь стрим в стриме из
[статьи 9 «Стримов»](https://hammerhall.io/ledger/streams/9-two-collections). Работа
множества — как сумма, O(n + m). При 8000 гостях разница — больше чем
в 1800 раз.

Время — только иллюстрация. В нашем прогоне при 8000 гостях список
справился за 20–30 мс, множество — около миллисекунды. У тебя числа
будут другие, рост — тот же.

💡 У `TreeSet` `contains` стоит log₂ n — так обещает документация;
log₂ 8000 ≈ 13 — сколько раз 8000 можно поделить пополам. Дороже
`HashSet`, но несравнимо дешевле списка.

🔑 Коллекция, у которой спрашивают `contains`, должна быть множеством:
аргумент `retainAll` и `removeAll`, сама коллекция у `containsAll`,
коллекция в `filter(…::contains)`. Список там — тот же стрим в стриме,
только спрятанный в одном вызове.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Что такое пересечение, объединение и разность? Посчитай руками для
   A = {латте, чай, эклер} и B = {чай, сырник}: A ∩ B, A ∪ B, A \ B,
   B \ A и A Δ B.
2. Почему перед `retainAll` и `removeAll` делают копию? Что сломалось
   у гостя 17, когда копии не было?
3. Почему `DRINKS.retainAll(before)` бросает
   `UnsupportedOperationException`, а `intersection(DRINKS, before)`
   работает?
4. Какой вопрос задаёт `DRINKS.containsAll(items)`, а какой —
   `items.containsAll(DRINKS)`? Чем оба отличаются от
   `items.equals(DRINKS)`?
5. Почему `HashSet` и `TreeSet` с одними элементами равны, а два списка
   из одних и тех же элементов могут быть не равны?
6. С какого множества начинать свёртку-пересечение и почему не с
   пустого? Что выйдет, если подходящих гостей нет вовсе?
7. Откуда у списка 34 252 сравнения, а у множества 516 шагов? Во
   сколько раз вырастет каждое число, если гостей станет вдвое больше?
8. Почему множество из `Set.of` не годится для ответа, который печатают
   и сверяют как строку?

---

## Реши в кузнице

Задача на то же самое — сравнение множеств — в кузнице Stream Forge
на платформе Hammerhall, на фильмах. Задача бесплатна, нужен только
вход:

* [«Найти все фильмы, у которых набор жанров строго равен набору: Drama и Comedy»](https://hammerhall.io/forge/stream-forge/task/MovMind0006).

## Что дальше

Статья 2 — [множество как ключ карты](https://hammerhall.io/ledger/algorithms/2-set-as-key).
Когда вопрос звучит «что одинаковое», пары «все со всеми» не нужны:
хватит одной группировки по множеству.

## Первоисточники

* [Interface Set — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Set.html) —
  `containsAll`, `addAll`, `retainAll`, `removeAll` словами алгебры;
  `equals` по содержимому; неизменяемые `Set.of` и `Set.copyOf`.
* [Class HashSet — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/HashSet.html) —
  постоянное время `add` и `contains`; порядок не обещан.
* [Class TreeSet — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/TreeSet.html) —
  порядок элементов; `contains` за log₂ n.
* [Class AbstractCollection — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/AbstractCollection.html) —
  как `retainAll` и `containsAll` устроены через `contains`.
* [Class Collections — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Collections.html) —
  `disjoint`.
* [Interface Stream — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/stream/Stream.html) —
  `reduce` и его начальное значение.
* [Class Random — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Random.html) —
  почему одно зерно даёт одни и те же числа на любой Java.

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
в командной строке Windows перед этим выполни `chcp 65001`.

```java
// Coffee.java — учебный пример статьи 1 серии «Алгоритмы на стримах».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;

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

/** Напитки меню, остальное — десерты. Set.of — неизменяемое множество. */
static final Set<String> DRINKS = Set.of("латте", "капучино", "эспрессо", "американо", "раф", "какао", "матча", "чай");

/** Что брал гость с дня from по день to включительно: названия позиций без повторов, по алфавиту. */
Set<String> itemsOf(List<Order> orders, int guest, int from, int to) {
    return orders.stream()
            .filter(order -> order.guest() == guest && order.day() >= from && order.day() <= to)
            .flatMap(order -> order.items().stream())
            .map(Item::name)
            .collect(Collectors.toCollection(TreeSet::new));
}

/** Пересечение: что есть и в a, и в b. Ответ — новое множество, a и b не меняются. */
Set<String> intersection(Set<String> a, Set<String> b) {
    Set<String> result = new TreeSet<>(a);   // копия: retainAll меняет множество, у которого вызван
    result.retainAll(b);
    return result;
}

/** Объединение: что есть хотя бы в одном из двух. */
Set<String> union(Set<String> a, Set<String> b) {
    Set<String> result = new TreeSet<>(a);
    result.addAll(b);
    return result;
}

/** Разность: что есть в a, но нет в b. */
Set<String> difference(Set<String> a, Set<String> b) {
    Set<String> result = new TreeSet<>(a);
    result.removeAll(b);
    return result;
}

/** Гости, которые заходили с дня from по день to: номера карт без повторов, в порядке первого визита. */
List<Integer> visitors(List<Order> orders, int from, int to) {
    return orders.stream()
            .filter(order -> order.day() >= from && order.day() <= to)
            .map(Order::guest)
            .distinct()
            .toList();
}

/** Сколько всего сравнений сделает contains списка list, если спросить его о каждом госте из who. */
long listComparisons(List<Integer> who, List<Integer> list) {
    return who.stream()
            .mapToLong(guest -> {
                int index = list.indexOf(guest);               // contains ищет так же: с начала списка
                return index >= 0 ? index + 1 : list.size();   // нашёл на месте index — index + 1 сравнений
            })
            .sum();
}

void main() {
    List<Order> orders = orders(42, 300, 30);

    // 1. Что брал гость 17 в дни 1–15 и в дни 16–30
    Set<String> before = itemsOf(orders, 17, 1, 15);
    Set<String> after = itemsOf(orders, 17, 16, 30);
    IO.println("дни 1–15: " + before + ", дни 16–30: " + after);

    // 2. Пересечение, объединение, разность — новые множества, before и after целы
    IO.println("осталось:        " + intersection(before, after));
    IO.println("осталось, стрим: " + before.stream().filter(after::contains).toList());
    IO.println("всё за месяц:    " + union(before, after));
    IO.println("перестал брать:  " + difference(before, after));
    IO.println("начал брать:     " + difference(after, before));
    IO.println("сменилось:       " + difference(union(before, after), intersection(before, after)));

    // 3. Подмножество: брал ли гость за месяц только напитки
    IO.println("гость 2 — только напитки:  " + DRINKS.containsAll(itemsOf(orders, 2, 1, 30)));
    IO.println("гость 17 — только напитки: " + DRINKS.containsAll(itemsOf(orders, 17, 1, 30)));

    // 4. Равенство: множества равны по содержимому, списки — ещё и по порядку
    IO.println("HashSet и TreeSet: " + new HashSet<>(before).equals(before));
    IO.println("до и после:        " + before.equals(after));
    IO.println("два списка:        " + List.of("капучино", "эспрессо").equals(List.of("эспрессо", "капучино")));

    // 5. Не пересекаются: есть ли у двух гостей хоть одна общая позиция
    Set<String> month17 = itemsOf(orders, 17, 1, 30);
    IO.println("у 17 и 7 общего нет: " + Collections.disjoint(month17, itemsOf(orders, 7, 1, 30)));
    IO.println("у 17 и 2 общего нет: " + Collections.disjoint(month17, itemsOf(orders, 2, 1, 30)));

    // 6. Пересечение многих: что брали все самые частые гости — 22 визита и больше
    Map<Integer, Long> visits = orders.stream()
            .collect(Collectors.groupingBy(Order::guest, Collectors.counting()));
    Set<String> menu = MENU.stream().map(Item::name).collect(Collectors.toCollection(TreeSet::new));
    Set<String> frequentCommon = visits.entrySet().stream()
            .filter(entry -> entry.getValue() >= 22)
            .map(entry -> itemsOf(orders, entry.getKey(), 1, 30))
            .reduce(menu, (common, items) -> intersection(common, items));
    IO.println("общее у самых частых: " + frequentCommon);

    // 7. Цена: кто из гостей первых десяти дней вернулся в последние десять
    List<Integer> early = visitors(orders, 1, 10);
    List<Integer> late = visitors(orders, 21, 30);
    Set<Integer> lateSet = new HashSet<>(late);
    List<Integer> backByList = early.stream().filter(late::contains).toList();      // contains списка
    List<Integer> backBySet = early.stream().filter(lateSet::contains).toList();    // contains множества
    IO.println("вернулись " + backBySet.size() + " из " + early.size() + ", ответы равны: " + backByList.equals(backBySet));
    IO.println("список: сравнений " + listComparisons(early, late)
            + "; множество: добавлений " + late.size() + ", обращений " + early.size());

    // 8. Рост: гостей вдвое больше — у списка работы вчетверо больше, у множества вдвое
    for (int guests : List.of(1000, 2000, 4000, 8000)) {
        List<Order> month = orders(42, guests, 30);
        List<Integer> first = visitors(month, 1, 10);
        List<Integer> last = visitors(month, 21, 30);
        IO.println(guests + " гостей: список " + listComparisons(first, last)
                + ", множество " + (last.size() + first.size()));
    }

    // Сделай руками — раскомментируй и запусти:
    // DRINKS.retainAll(before);   // UnsupportedOperationException
}
```

Сделай руками:

1. Запусти файл. Первая строка —
   `дни 1–15: [капучино, эклер, эспрессо], дни 16–30: [какао, капучино, эспрессо]`,
   последняя — `8000 гостей: список 26485356, множество 14193`.
2. В методе `intersection` замени `new TreeSet<>(a)` на `a` — копии
   не станет, и первое же пересечение испортит `before`. Выйдет
   `всё за месяц:    [какао, капучино, эспрессо]`,
   `перестал брать:  []` и `сменилось:       [какао]`. Верни как было.
3. Раскомментируй последнюю строку `main` — `DRINKS.retainAll(before)`.
   После всех ответов выйдет
   `Exception in thread "main" java.lang.UnsupportedOperationException`.
   Верни комментарий.
4. В блоке `// 3.` замени `DRINKS.containsAll(itemsOf(orders, 2, 1, 30))`
   на `itemsOf(orders, 2, 1, 30).containsAll(DRINKS)` — выйдет
   `гость 2 — только напитки:  false`: это уже вопрос «перепробовал ли
   он все напитки». Верни как было.
5. В блоке `// 6.` замени начальное значение `menu` на
   `new TreeSet<>()` — выйдет `общее у самых частых: []`. Верни `menu`
   и поставь порог `25` вместо `22` — выйдет всё меню, двенадцать
   названий: гостей с 25 визитами нет, и `reduce` вернул начальное
   значение. Верни как было.
6. В блоке `// 8.` добавь в список `16000` — выйдет
   `16000 гостей: список 105854286, множество 28384`: снова почти
   вчетверо и вдвое.
