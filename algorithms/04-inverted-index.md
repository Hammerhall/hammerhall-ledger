# Пары внутри записи и обратный индекс

> «Сравнить коллекции» · статья 4 · читать минут 20
>
> **Для кого.** Ты прочитал статьи 1–3 цикла: операции над множествами,
> множество как ключ карты, перебор пар «все со всеми» и его цену
> n·(n−1)/2. Из «Стримов по шагам» помнишь `flatMap`, `groupingBy`
> с коллектором для группы, `Map.entry` и индекс-карту из статьи 9 «Стримов».
>
> **Что будет.** Пары внутри одного заказа — и почему их мало; каким
> должен быть ключ пары, чтобы «латте + эклер» и «эклер + латте» не стали
> двумя парами; обратный индекс «позиция → гости», как у поисковика,
> и вопрос «кто брал и то, и другое» без опроса всех гостей; блокинг —
> и почему на нашем меню он работу не сокращает, а умножает.
>
> **Откуда серия.** Её пишет команда платформы Hammerhall. Задачи на алгоритмы — в кузнице Stream Forge на платформе, в слое mind; здесь — теория к ним: приём, его цена и где он ломается. Примеры учебные: каждый запускается одним файлом.

---

## Зачем пары без перебора

В [статье 3](https://hammerhall.io/ledger/algorithms/3-all-pairs) ты перебрал все пары гостей:
294 гостя с заказами — 43 071 пара, вдвое больше гостей — вчетверо
больше работы. Там же был совет: прежде чем перебирать пары, спроси,
нельзя ли без них. Равенство решает группировка, близость чисел —
сортировка. Эта статья — про третий случай: «общее».

Приёмов два. Первый — **пары внутри записи**: не все заказы со всеми,
а позиции одного заказа между собой. Таких пар мало, и вдвое больше
данных даёт вдвое больше пар, а не вчетверо. Второй — **обратный
индекс** (inverted index): карта «позиция → гости, которые её брали».
С ним на вопрос «кто брал и латте, и эклер» отвечают, не опрашивая
каждого гостя, — так поисковик находит страницы по двум словам. Из того же индекса вырастает
**блокинг**: сравнивать не всех со всеми, а только тех, у кого есть
что-то общее.

Данные — месяц «Наковальни» из [статьи 1](https://hammerhall.io/ledger/algorithms/1-set-algebra):
`orders(42, 300, 30)`, 2843 заказа 294 гостей за 30 дней.

---

## Часть 1. Пары внутри заказа

### Три позиции — три пары

Возьми заказ 10: эспрессо, чай и капучино. Пары: эспрессо с чаем,
эспрессо с капучино, чай с капучино — три. Формула та же, что
в статье 3: из k штук выходит k·(k−1)/2 пар. Только k здесь — не число
гостей, а число позиций в заказе, а их у нас от одной до трёх. Одна
позиция — 0 пар, две — 1, три — 3.

Пары одного заказа перебирает тот же двойной `range`, что в статье 3,
только по позициям внутри заказа:

```java
/** Пары позиций одного заказа: каждая с каждой следующей. */
List<List<String>> pairs(Order order) {
    List<String> names = order.items().stream().map(Item::name).toList();
    return IntStream.range(0, names.size()).boxed()
            .flatMap(i -> IntStream.range(i + 1, names.size())
                    .mapToObj(j -> List.of(names.get(i), names.get(j))))
            .toList();
}
```

```
заказ 10: [[эспрессо, чай], [эспрессо, капучино], [чай, капучино]]
```

Пара пока — список из двух названий в том порядке, в каком они стоят
в заказе. `i + 1` и `boxed()` — как в статье 3: позиция не встаёт в пару
сама с собой, и каждая пара выходит один раз.

### За месяц пар меньше, чем заказов

```java
long inOrders = orders.stream().mapToLong(order -> pairs(order).size()).sum();
```

```
заказов 2843, пар внутри заказов 2595
```

Пар меньше, чем заказов: в заказе из одной позиции пар нет вовсе.
Сравни с 43 071 парой гостей из статьи 3. Теперь рост — тот же опыт
с `orders(42, n, 30)`:

```java
for (int n : List.of(1000, 2000, 4000, 8000)) {
    List<Order> month = orders(42, n, 30);
    long count = month.stream().mapToLong(order -> pairs(order).size()).sum();
    IO.println("n = " + n + ": заказов " + month.size() + ", пар внутри заказов " + count);
}
```

```
n = 1000: заказов 9834, пар внутри заказов 8618
n = 2000: заказов 19568, пар внутри заказов 16970
n = 4000: заказов 38969, пар внутри заказов 33814
n = 8000: заказов 78239, пар внутри заказов 68118
```

Гостей вдвое больше — пар вдвое больше, а не вчетверо. При n = 8000
пар гостей в статье 3 было больше 30 миллионов, здесь — 68 тысяч.
Каждый заказ приносит не больше трёх пар, поэтому работа растёт как
число записей.

💡 Дёшево это, пока запись маленькая. Будь в записи не три элемента,
а тысяча, как слов в статье, — одна такая запись дала бы
1000·999/2 = 499 500 пар.

### Ключ-список считает пару дважды

Хозяйка думает о скидке на сочетания и спрашивает: есть ли пары позиций,
которых за месяц никто ни разу не взял вместе? Позиций в меню 12,
значит, возможных пар 12·11/2 = 66 — формула из статьи 3 теперь живёт
в методе:

```java
/** Сколько пар можно составить из k штук: k·(k−1)/2. */
long pairCount(long k) {
    return k * (k - 1) / 2;
}
```

Соберём все пары месяца в множество — повторы уйдут, останутся разные:

```java
Set<List<String>> asLists = orders.stream()
        .flatMap(order -> pairs(order).stream())
        .collect(toSet());
IO.println("возможных пар " + pairCount(MENU.size()) + ", разных ключей-списков " + asLists.size());
```

```
возможных пар 66, разных ключей-списков 132
```

Разных пар вышло вдвое больше, чем вообще возможно. Виноват
`equals` у списка: два списка равны, только если в них те же элементы
**в том же порядке**. Помнишь статью 2: ключ-список различает порядок,
ключ-множество — нет.

```java
IO.println(List.of("латте", "эклер").equals(List.of("эклер", "латте")));
IO.println(Set.of("латте", "эклер").equals(Set.of("эклер", "латте")));
```

```
false
true
```

В одном заказе эклер пробит после латте, в другом — до. Для списка это
две разные пары, и каждое сочетание попало в множество дважды:
66·2 = 132.

### Set.of(a, b) или запись с порядком внутри

Ключу пары нужно одно: не зависеть от порядка. Первый способ — множество
из двух, `Set.of(a, b)`:

```java
Set<Set<String>> asSets = orders.stream()
        .flatMap(order -> pairs(order).stream())
        .map(pair -> Set.of(pair.get(0), pair.get(1)))
        .collect(toSet());
```

`Set.of` неизменяемо, а это ключу и нужно: изменённый после вставки
ключ карта теряет (статья 2).

⚠️ У `Set.of` два подвоха. Первый — повтор он не прощает: если `a`
и `b` равны, будет `IllegalArgumentException`. В наших заказах названия
не повторяются — генератор за этим следит. Но напиши в `pairs`
`range(i, …)` вместо `range(i + 1, …)` — и пара «чай с чаем» уронит
программу:

```
Exception in thread "main" java.lang.IllegalArgumentException: duplicate element: чай
```

Второй — печать: порядок в `Set.of` не обещан, это было в статье 2.

Есть и второй способ — своя запись, которая сама ставит названия
по алфавиту.

```java
/** Пара позиций без порядка: первой всегда стоит та, что раньше по алфавиту. */
record ItemPair(String first, String second) {
    ItemPair {
        if (first.compareTo(second) > 0) {     // пришли не по алфавиту — меняем местами
            String swap = first;
            first = second;
            second = swap;
        }
    }
}
```

`ItemPair { … }` без списка параметров — **компактный конструктор**, он
бывает только у записей. Параметры у него те же, что у записи, —
`first` и `second`, — их не пишут. Тело выполняется до того, как
значения лягут в поля, и может их поправить, а присваивания
`this.first = first` Java добавит в конце сама. `compareTo` сравнивает
строки по кодам символов (статья 3 «Стримов»); для наших названий —
строчных и без «ё» — это алфавит. В [статье 3](https://hammerhall.io/ledger/algorithms/3-all-pairs)
порядок в паре гостей наводил метод `pair` через `Math.min` и `Math.max`; здесь его наводит
сама запись, и мимо конструктора пару «не по алфавиту» не создать.

💡 Пару «чай с чаем» `ItemPair` примет молча. Если это ошибка — брось
исключение в том же компактном конструкторе, как делает `Set.of`.

```java
IO.println(new ItemPair("эклер", "латте"));
Set<ItemPair> asRecords = orders.stream()
        .flatMap(order -> pairs(order).stream())
        .map(pair -> new ItemPair(pair.get(0), pair.get(1)))
        .collect(toSet());
IO.println("разных ключей: Set " + asSets.size() + ", ItemPair " + asRecords.size());
```

```
ItemPair[first=латте, second=эклер]
разных ключей: Set 66, ItemPair 66
```

`equals` записи сравнивает все поля, `hashCode` считается по ним же
([статья 4 «Стримов»](https://hammerhall.io/ledger/streams/4-flatmap)), поля записи —
`final`, а порядок в них наводит конструктор. Ключ неизменяемый,
не зависит от порядка и печатается одинаково. Ответ хозяйке: все 66
сочетаний за месяц кто-то брал — «мёртвых» пар нет.

🔑 Ключ пары без порядка — `Set.of(a, b)` или запись, которая сама
упорядочивает свои поля. Список годится, только если порядок наведён
заранее.

---

## Часть 2. Обратный индекс

### Латте-эклер: опросить каждого гостя

Повар придумал новинку — латте-эклер. Хозяйка хочет сначала предложить
её тем, кто брал и латте, и эклер.

Карта «гость → его позиции» тебе знакома: это `itemsOf` из статьи 1,
только сразу для всех гостей. Назовём её **прямым индексом**: по гостю сразу видно,
что он брал. Самое прямое решение — пройти по всем гостям и спросить
каждого:

```java
Map<Integer, Set<String>> positionsByGuest = orders.stream()
        .collect(groupingBy(Order::guest, TreeMap::new,
                flatMapping(order -> order.items().stream().map(Item::name), toSet())));
checks = 0;
List<Integer> byGuests = positionsByGuest.entrySet().stream()
        .filter(entry -> {
            checks++;
            return entry.getValue().contains("латте");
        })
        .filter(entry -> {
            checks++;
            return entry.getValue().contains("эклер");
        })
        .map(Map.Entry::getKey)
        .toList();
```

`checks` — поле-счётчик, как `comparisons` в
[статье 9 «Стримов»](https://hammerhall.io/ledger/streams/9-two-collections): только чтобы
увидеть работу.

```
перебором: гостей 294, подошли 79, проверок 447
```

Про латте спросили всех 294 гостей с заказами, про эклер — только тех,
кто брал латте: 294 + 153 = 447 проверок. Новинку предложим 79 гостям.
Ответ верный, но завтра повар придумает чизкейк с матчей — и снова
опрос всех 294.

### Как ищет поисковик

Поисковик не просматривает все страницы на каждый запрос. Он заранее
составил для каждого слова список страниц, где это слово встречается. Запрос из двух слов — это два готовых списка и их
пересечение: страницы, которые есть в обоих. Такая карта «слово → где
оно есть» и есть обратный индекс. «Обратный» — потому что
переворачивает прямой: не «страница → её слова», а «слово → его
страницы».

Наш поисковик ищет гостей: «позиция → гости, которые её брали».
Строим за один проход по заказам:

```java
Map<String, Set<Integer>> index = orders.stream()
        .flatMap(order -> order.items().stream()
                .map(item -> Map.entry(item.name(), order.guest())))     // пара (позиция, гость)
        .collect(groupingBy(Map.Entry::getKey, TreeMap::new,
                mapping(Map.Entry::getValue, toSet())));
```

После `flatMap` по конвейеру едут позиции, а позиция не знает, чей это
заказ, — помнишь эту ошибку из
[статьи 6 «Стримов»](https://hammerhall.io/ledger/streams/6-downstream-collectors). Поэтому
пару «позиция, гость» делаем сразу, пока гость под рукой, —
`Map.entry` из [статьи 7 «Стримов»](https://hammerhall.io/ledger/streams/7-streams-over-maps). Дальше —
группировка по позиции, а внутри группы номера карт ложатся
во множество: гость, бравший эклер десять раз, встанет в список один раз.

```java
IO.println(index.keySet());
IO.println("раф: " + index.get("раф").stream().sorted().limit(8).toList() + " … всего "
        + index.get("раф").size());
IO.println("сумма длин списков: " + index.values().stream().mapToInt(Set::size).sum());
```

```
[американо, какао, капучино, круассан, латте, матча, раф, сырник, чай, чизкейк, эклер, эспрессо]
раф: [1, 4, 5, 6, 12, 13, 14, 18] … всего 125
сумма длин списков: 1683
```

`TreeMap` держит позиции по алфавиту — печать одна и та же. Списки гостей — обычные множества из `toSet()`, на JDK 25 это
`HashSet`. От списка нужен быстрый `contains`, а у `HashSet` он занимает
постоянное время, сколько бы гостей ни было в списке. Порядка он
не обещает — список рафа для печати отсортирован.

### Пересечение: идём по короткому списку

Кто брал и латте, и эклер — это гости, которые есть в обоих списках.
Пересечение ты знаешь по статье 1: идём по одному множеству и у другого
спрашиваем `contains`. Важно только, по какому идти:

```java
/** Гости, которые есть в обоих списках: идём по короткому, длинный спрашиваем contains. */
List<Integer> both(Set<Integer> shorter, Set<Integer> longer) {
    if (shorter.size() > longer.size()) {
        return both(longer, shorter);              // перепутали — меняем местами
    }
    return shorter.stream()
            .filter(guest -> {
                checks++;
                return longer.contains(guest);
            })
            .sorted()                              // по номеру карты — только для печати
            .toList();
}
```

```java
Set<Integer> latte = index.get("латте");
Set<Integer> eclair = index.get("эклер");
checks = 0;
List<Integer> byIndex = both(latte, eclair);
```

```
по индексу: латте 153, эклер 145, подошли 79, проверок 145
первые десять: [4, 9, 10, 12, 20, 21, 28, 30, 33, 35]; ответ тот же: true
```

Те же 79 гостей — `equals` списков это подтвердил, — а проверок 145
вместо 447: по одной на каждого, кто брал эклер. Общих гостей не может
быть больше, чем в коротком списке, поэтому его и обходим. Так же
поступают поисковики: начинают с самых коротких списков, и промежуточный
ответ никогда не больше самого короткого.

### Сколько это стоит

Индекс строится один раз — проходом по всем позициям всех заказов,
как и прямой. Дальше вопрос «кто брал X и Y» стоит
столько проверок, сколько гостей в коротком списке, а не сколько гостей
вообще.

У нас выигрыш — втрое, не больше: списки длинные. Сумма их длин — 1683
на 294 гостя, в среднем 5,7 позиции из 12 на гостя, почти полменю.
Будь эклер редкостью — бери его трое гостей, — проверок было бы три,
а опрос по-прежнему начинался бы с 294.

🔑 Обратный индекс платит один раз, при постройке. Потом вопрос «у кого
есть X и Y» трогает только списки X и Y — и чем они короче, тем дешевле
ответ.

⚠️ Позиции, которую никто не брал, нет и в индексе: `index.get("пончик")`
вернёт `null`, как в статье 9 «Стримов», и `both` упадёт
с `NullPointerException`. Для вопросов «с улицы» бери
`index.getOrDefault("пончик", Set.of())`: пустой список — пустой ответ
и ноль проверок.

---

## Часть 3. Блокинг: кого с кем сравнивать

### Кандидаты — только из одного списка

Когда понадобится мерить сходство двоих (мера — в статье 5), сравнивать
всех со всеми — те же 43 071 пара, что в статье 3. Но у двух
гостей без единой общей позиции мерить нечего: общего у них ноль.
Сравнивать стоит только тех, кто вместе стоит хоть в одном списке
индекса.

Это и есть блокинг (blocking): записи раскладывают по блокам с общим
ключом и ищут пары только внутри блока. Как на почте: письма
раскладывают по городам и сверяют адреса только внутри стопки одного
города. Пары, которые прошли такой отбор, называют **кандидатами**.

Посмотрим на самый короткий список индекса:

```java
IO.println("все пары гостей: " + pairCount(positionsByGuest.size()));
Map.Entry<String, Set<Integer>> rarest = index.entrySet().stream()
        .min(Comparator.comparingInt(entry -> entry.getValue().size()))
        .orElseThrow();
IO.println("самая редкая — " + rarest.getKey() + ": гостей " + rarest.getValue().size()
        + ", пар " + pairCount(rarest.getValue().size()));
```

```
все пары гостей: 43071
самая редкая — раф: гостей 125, пар 7750
```

`min` с компаратором по длине списка — стрим по `Map` из статьи 7
«Стримов». Блок рафа — 7750 пар вместо 43 071, в пять с половиной раз
меньше. Но в нём только любители рафа.

### ⚠️ Когда блокинг хуже перебора

Чтобы сравнить всех, кому есть что сравнивать, нужны все двенадцать
списков:

```java
long everyList = index.values().stream().mapToLong(guests -> pairCount(guests.size())).sum();
```

```
по всем спискам: пар 117454
```

117 454 — в 2,7 раза больше, чем полный перебор. Блоки у нас огромные:
даже самую редкую позицию брали 125 гостей из 294, больше двух пятых.
И блоки перекрываются: гость стоит в среднем в 5,7 списка, так что пара
гостей с четырьмя общими позициями посчитана четырежды.

Блокинг работает, когда ключи редкие и блоки маленькие. В нашем меню
общее есть почти у любых двоих: кандидатов без повторов — 40 048
из 43 071, 93 %.

💡 Позиций всегда двенадцать, поэтому вдвое больше гостей — вдвое длиннее
каждый список и вчетверо больше пар в нём. Пока ключей не прибавляется,
блокинг делит работу на число, а n² остаётся n²: проверишь в «Сделай
руками». Рост меняется, только когда с данными растёт число ключей,
а блоки остаются маленькими.

---

## Проверь себя

Ответь своими словами — вслух или на бумаге. Не получается — перечитай
раздел.

1. Сколько пар даёт заказ из k позиций? Почему с ростом гостей пар
   внутри заказов вдвое больше, а не вчетверо — и когда пары внутри
   записи перестают быть дешёвыми?
2. Почему с ключом-списком разных пар вышло 132, хотя возможных всего 66?
3. Чем рискуешь, когда берёшь ключом пары `Set.of(a, b)`? Что делает
   компактный конструктор `ItemPair`?
4. Что такое обратный индекс и почему он «обратный»? Как поисковик
   отвечает на запрос из двух слов?
5. Откуда 447 проверок у опроса гостей и 145 — у индекса? Почему
   пересечение идёт по короткому списку?
6. Почему у нас индекс выиграл только втрое? При каких списках выигрыш
   был бы огромным?
7. Что такое блокинг? Почему один блок рафа в пять с половиной раз
   меньше перебора, а все блоки вместе — больше?
8. Почему у нас блокинг не спасает от роста n²? Когда спас бы?

---

## Что дальше

Индекс нашёл тех, у кого есть общее. Но гость, бравший всё меню, делит
что-нибудь с каждым — «общее» ещё не значит «похожи».
[Статья 5](https://hammerhall.io/ledger/algorithms/5-jaccard) — коэффициент Жаккара: насколько
похожи два множества, одним числом от 0 до 1.

## Первоисточники

* [Interface Set — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/Set.html) —
  раздел Unmodifiable Sets: `Set.of` неизменяемо, повтор — `IllegalArgumentException`,
  порядок обхода не обещан; `equals` множеств — без порядка.
* [Interface List — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/List.html) —
  `equals`: те же элементы в том же порядке.
* [Record Classes — Java SE 25](https://docs.oracle.com/en/java/javase/25/language/records.html) —
  компактный конструктор и `final`-поля записи.
* [Class HashSet — Java SE 25](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/HashSet.html) —
  `contains` за постоянное время.
* Manning, Raghavan, Schütze. *Introduction to Information Retrieval*,
  глава 1: [1.1](https://nlp.stanford.edu/IR-book/html/htmledition/an-example-information-retrieval-problem-1.html) —
  что такое обратный индекс и почему без него каждый запрос — проход
  по всем текстам; [1.3](https://nlp.stanford.edu/IR-book/html/htmledition/processing-boolean-queries-1.html) —
  запрос из двух слов как пересечение списков и правило «начинай
  с самых коротких».
* [CS246: Mining Massive Datasets, лекция о поиске похожих документов (Stanford)](https://snap.stanford.edu/class/cs246-2025/WWW/slides/03-lsh.pdf) —
  кандидаты: сравнивают только пары, попавшие в одну «корзину».
* Steorts, Ventura, Sadinle, Fienberg. [A Comparison of Blocking Methods for Record Linkage](https://arxiv.org/pdf/1407.3191) —
  что такое блокинг и почему слишком большие блоки его не спасают.

---

## Пример целиком

Учебный пример — один файл. Нужен JDK 25: проверь командой
`java -version`, первая строка должна начинаться с `openjdk version "25`
(или `java version "25`). С JDK из курса, 17 или 21, файл
не запустится.

Записи, меню и генератор заказов стоят вверху файла — они одинаковые
во всех статьях серии, генератор читать не обязательно. Под ними — новое
этой статьи: запись `ItemPair`, поле `checks` и методы `pairCount`, `pairs`
и `both`. Методы и `main` — без класса вокруг: в Java 25 такой файл сам
становится классом, а `void main()` без `public static` и без
параметров — точкой входа. Сохрани файл как `Coffee.java` и запусти
из его папки:

```bash
java Coffee.java
```

Java сама скомпилирует файл и выполнит `main` — ни Maven, ни проекта
не нужно. Если вместо русских букв в выводе вопросы или кракозябры,
запусти с явной кодировкой — аргументы в кавычках, так их поймёт
и PowerShell: `java "-Dstdout.encoding=UTF-8" "-Dstderr.encoding=UTF-8" Coffee.java`;
в командной строке Windows перед этим выполни `chcp 65001`.

```java
// Coffee.java — учебный пример статьи 4 серии «Алгоритмы на стримах».
// Запуск: java Coffee.java (нужен JDK 25)

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
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

/** Пара позиций без порядка: первой всегда стоит та, что раньше по алфавиту. */
record ItemPair(String first, String second) {
    ItemPair {
        if (first.compareTo(second) > 0) {     // пришли не по алфавиту — меняем местами
            String swap = first;
            first = second;
            second = swap;
        }
    }
}

long checks = 0;   // сколько раз спросили contains — только чтобы увидеть работу

/** Сколько пар можно составить из k штук: k·(k−1)/2. */
long pairCount(long k) {
    return k * (k - 1) / 2;
}

/** Пары позиций одного заказа: каждая с каждой следующей. */
List<List<String>> pairs(Order order) {
    List<String> names = order.items().stream().map(Item::name).toList();
    return IntStream.range(0, names.size()).boxed()
            .flatMap(i -> IntStream.range(i + 1, names.size())
                    .mapToObj(j -> List.of(names.get(i), names.get(j))))
            .toList();
}

/** Гости, которые есть в обоих списках: идём по короткому, длинный спрашиваем contains. */
List<Integer> both(Set<Integer> shorter, Set<Integer> longer) {
    if (shorter.size() > longer.size()) {
        return both(longer, shorter);              // перепутали — меняем местами
    }
    return shorter.stream()
            .filter(guest -> {
                checks++;
                return longer.contains(guest);
            })
            .sorted()                              // по номеру карты — только для печати
            .toList();
}

void main() {
    List<Order> orders = orders(42, 300, 30);

    // 1. Пары одного заказа: три позиции — три пары
    Order tenth = orders.get(9);
    IO.println("заказ " + tenth.number() + ": " + pairs(tenth));

    // 2. Пары внутри заказов за месяц
    long inOrders = orders.stream().mapToLong(order -> pairs(order).size()).sum();
    IO.println("заказов " + orders.size() + ", пар внутри заказов " + inOrders);

    // 3. Сколько разных пар встретилось: ключ — список из двух
    Set<List<String>> asLists = orders.stream()
            .flatMap(order -> pairs(order).stream())
            .collect(toSet());
    IO.println("возможных пар " + pairCount(MENU.size()) + ", разных ключей-списков " + asLists.size());

    // 4. Список помнит порядок, множество — нет
    IO.println(List.of("латте", "эклер").equals(List.of("эклер", "латте")));
    IO.println(Set.of("латте", "эклер").equals(Set.of("эклер", "латте")));

    // 5. Ключ без порядка: Set.of(a, b) или запись ItemPair
    Set<Set<String>> asSets = orders.stream()
            .flatMap(order -> pairs(order).stream())
            .map(pair -> Set.of(pair.get(0), pair.get(1)))
            .collect(toSet());
    IO.println(new ItemPair("эклер", "латте"));
    Set<ItemPair> asRecords = orders.stream()
            .flatMap(order -> pairs(order).stream())
            .map(pair -> new ItemPair(pair.get(0), pair.get(1)))
            .collect(toSet());
    IO.println("разных ключей: Set " + asSets.size() + ", ItemPair " + asRecords.size());

    // 6. Рост: вдвое больше гостей — вдвое больше пар внутри заказов
    for (int n : List.of(1000, 2000, 4000, 8000)) {
        List<Order> month = orders(42, n, 30);
        long count = month.stream().mapToLong(order -> pairs(order).size()).sum();
        IO.println("n = " + n + ": заказов " + month.size() + ", пар внутри заказов " + count);
    }

    // 7. Прямой индекс «гость → позиции»: кто брал и латте, и эклер — перебором гостей
    Map<Integer, Set<String>> positionsByGuest = orders.stream()
            .collect(groupingBy(Order::guest, TreeMap::new,
                    flatMapping(order -> order.items().stream().map(Item::name), toSet())));
    checks = 0;
    List<Integer> byGuests = positionsByGuest.entrySet().stream()
            .filter(entry -> {
                checks++;
                return entry.getValue().contains("латте");
            })
            .filter(entry -> {
                checks++;
                return entry.getValue().contains("эклер");
            })
            .map(Map.Entry::getKey)
            .toList();
    IO.println("перебором: гостей " + positionsByGuest.size() + ", подошли " + byGuests.size()
            + ", проверок " + checks);

    // 8. Обратный индекс «позиция → гости»
    Map<String, Set<Integer>> index = orders.stream()
            .flatMap(order -> order.items().stream()
                    .map(item -> Map.entry(item.name(), order.guest())))     // пара (позиция, гость)
            .collect(groupingBy(Map.Entry::getKey, TreeMap::new,
                    mapping(Map.Entry::getValue, toSet())));
    IO.println(index.keySet());
    IO.println("раф: " + index.get("раф").stream().sorted().limit(8).toList() + " … всего "
            + index.get("раф").size());
    IO.println("сумма длин списков: " + index.values().stream().mapToInt(Set::size).sum());

    // 9. Латте и эклер — пересечение двух списков
    Set<Integer> latte = index.get("латте");
    Set<Integer> eclair = index.get("эклер");
    checks = 0;
    List<Integer> byIndex = both(latte, eclair);
    IO.println("по индексу: латте " + latte.size() + ", эклер " + eclair.size() + ", подошли "
            + byIndex.size() + ", проверок " + checks);
    IO.println("первые десять: " + byIndex.subList(0, 10) + "; ответ тот же: " + byIndex.equals(byGuests));

    // 10. Блокинг: пары только внутри одного списка
    IO.println("все пары гостей: " + pairCount(positionsByGuest.size()));
    Map.Entry<String, Set<Integer>> rarest = index.entrySet().stream()
            .min(Comparator.comparingInt(entry -> entry.getValue().size()))
            .orElseThrow();
    IO.println("самая редкая — " + rarest.getKey() + ": гостей " + rarest.getValue().size()
            + ", пар " + pairCount(rarest.getValue().size()));
    long everyList = index.values().stream().mapToLong(guests -> pairCount(guests.size())).sum();
    IO.println("по всем спискам: пар " + everyList);
}
```

Сделай руками:

1. Запусти файл. Первая строка — `заказ 10: [[эспрессо, чай], [эспрессо, капучино], [чай, капучино]]`;
   дальше найди `разных ключей-списков 132`, `Set 66, ItemPair 66`,
   `проверок 447` и `проверок 145`.
2. Удали из записи `ItemPair` компактный конструктор — блок
   `ItemPair { … }` целиком. Выйдет `ItemPair[first=эклер, second=латте]`
   и `ItemPair 132`: без
   перестановки запись помнит порядок, как список. Верни как было.
3. В методе `pairs` замени `IntStream.range(i + 1, names.size())`
   на `IntStream.range(i, names.size())`. В первой строке появятся пары
   вроде `[эспрессо, эспрессо]`, пар внутри заказов станет 7577, разных
   ключей-списков — 144, а на блоке `// 5.` программа упадёт
   с `IllegalArgumentException: duplicate element: чай`. Верни как было.
4. В методе `both` удали `if` с перестановкой. Ответ не изменится,
   но выйдет `проверок 153`: обошли длинный список латте. Верни как было.
5. В начале `main` замени `orders(42, 300, 30)` на `orders(42, 1000, 30)`.
   Гостей с заказами станет 982 — в 3,3 раза больше, а `по всем спискам` —
   1335162 пары против 117454, в 11,4 раза больше: это примерно 3,3².
   Позиций по-прежнему двенадцать, и блокинг рост n² не меняет. Верни
   как было.
