# Demo na stoisko ElixirConf — koncept: **Station VOY‑1**

> **Dokument źródłowy, zachowany bez zmian.** Stacja jest zbudowana i w kilku
> miejscach odbiega od tego, co tu napisano — bo coś nie zadziałało tak, jak
> zakładaliśmy. Lista różnic jest w `README.md`, sekcja *Where this differs from
> the concept*. Gdy README i ten dokument się nie zgadzają, prawdą jest README.

Status: sam koncept. Bez szczegółów implementacyjnych, bez kodu.
Wszystkie nazwy modułów, procesów i teksty w UI: **po angielsku**.

---

## 1. Co Voyager realnie potrafi pokazać (audyt możliwości)

Sprawdzone w kodzie, żeby demo opierało się na faktycznych funkcjach, a nie na życzeniach.

### Dostępne dzisiaj

| Obszar | Co daje | Źródło |
| --- | --- | --- |
| Połączenie z node'em | Zwykła dystrybucja (nazwa node'a + cookie) **albo** tunel SSH z proxowanym EPMD. Jedna aktywna sesja naraz. | `lib/voyager/node_session/`, `lib/voyager/proxy_epmd/` |
| Node Info | System info, rozbicie pamięci, **limity (procesy / porty / atomy / ETS vs. max)**, schedulery, run queues, skumulowane reductions + IO bytes, uruchomione aplikacje, eksport snapshotu do JSON. Refresh 1 s … 60 s. | `lib/voyager/services/node_info/` |
| Supervision Tree | Graf cytoscape + dagre, wybór aplikacji, kontrola głębokości, lazy expand stubów, krawędzie relacji link / monitor / monitored-by, **auto-refresh z diffem delt** (node'y animują się przy pojawieniu i zniknięciu), podświetlenie ścieżki po zaznaczeniu. | `lib/voyager_web/live/supervision_tree_live.ex`, `assets/js/hooks/supervision_tree/` |
| Panel szczegółów procesu | `initial_call`, `current_function`, registered name, status, **`message_queue_len`**, priority, `trap_exit`, reductions, memory / heap / stack, linki, ustawienia GC. | `lib/voyager/services/process_info.ex` |
| Serwer MCP | Introspekcja node'a wystawiona agentom (dziś narzędzie `node_info`). | `lib/voyager/mcp/` |

### Dojdzie przed ElixirConf

- **Przeglądanie ETS** (lista tabel + zawartość).
- **Lista procesów + szczegóły procesu**, w tym **stan procesu** — potwierdzone jako pewne, więc koncept może się na tym oprzeć.

### Ograniczenia, które demo musi uszanować

1. **Polling, nie push.** Drzewo i Node Info odświeżają się z timera (min ~1 s). → efekty muszą trwać tak długo, jak ktoś klika, a nie błyskać przez pół sekundy.
2. **Walk jest ograniczony**: 5 s deadline, ~`6 + 2 × depth` round-tripów RPC. → **rozwinięta** część drzewa: płytka (≤ 4–5 poziomów), ~150 procesów. Reszta żyje na node'cie zwinięta do stubów z licznikiem (sekcja 8).
3. **Etykiety** to registered name, w razie braku pid. → statki **muszą** być procesami nazwanymi.
4. **Brak tracingu i message flow.** Nie zobaczymy latających wiadomości — zobaczymy **długość kolejki** i reductions odbiorcy. Demo opowiada o message passingu **przez skutki**.
5. **Jeden node naraz.**

---

## 2. Koncept

> **Station VOY‑1.** Node BEAM *jest* stacją, a stacja to **jedna aplikacja, jedno drzewo superwizji, jeden system**. Odwiedzający skanuje QR, rejestruje statek (nazwa + rodzaj ładunku) i **jego statek dołącza do tego drzewa jako nazwany proces**. Wszystko, co dalej robi, to zwykły message passing między procesami — a Voyager pokazuje to jako fakty o żywym node'cie.

Mechanika sprowadza się do czterech miejsc, w których żyją dane, i tego, co przeżywa co:

| Gdzie | Co | Przeżywa restart procesu | Przeżywa restart node'a |
| --- | --- | --- | --- |
| stan procesu statku (`ship_falcon`) | ładunek jeszcze nieprzesłany | nie | nie |
| stan procesu magazynu (`Station.Warehouse`) | ładunek przyjęty od wszystkich | nie | nie |
| ETS (`station_leaderboard`) | ile kontenerów dostarczył każdy statek | **tak** | nie |
| plik na dysku | zrzut leaderboardu | **tak** | **tak** |

To jest cała „gra”. Nie ma poziomów, punktacji ani celu — jest tylko te cztery pudełka i pytanie, co zostaje po restarcie.

### Stoisko — dwa ekrany

- **Ekran A — laptop z Voyagerem.** Bohater, celowo hands-on: zachęcamy odwiedzających, żeby sami klikali. Obsługa steruje pytaniami, nie myszką.
- **Ekran B — telewizor ze „Station Ops”.** Pixel-artowy widok stacji: doki ze statkami, sunące kontenery, kolejka przed magazynem, leaderboard, log zdarzeń.

Telewizor to *narracja*, laptop to *prawda*. Ten ruch głowy lewo–prawo to jest właśnie to demo.

---

## 3. Rejestracja i panel statku

### Rejestracja (jeden ekran, dwa pola)

1. **Ship name** — dowolna nazwa wpisana przez odwiedzającego, przepuszczona przez filtr wulgaryzmów, z limitem długości i ograniczonym zestawem znaków. Nazwa trafia do drzewa superwizji jako registered name (`ship_millennium_falcon`), więc każdy znajduje się na dużym ekranie po swojemu.
2. **Cargo type** — wybór z presetów, i to nie jest ozdoba: **każdy ładunek ma inny koszt przyjęcia i inny rozmiar kontenera**.

| Cargo | Rozmiar kontenera | Koszt inspekcji | Efekt w Voyagerze |
| --- | --- | --- | --- |
| `ICE` | mały | niski | dużo lekkich wiadomości — rośnie długość kolejki, nie pamięć |
| `ORE` | średni | średni | zrównoważony, domyślny wybór |
| `MACHINERY` | duży | średni | pamięć magazynu rośnie najszybciej |
| `ANTIMATTER` | mały | **bardzo wysoki** | jeden kontener potrafi zająć magazyn na chwilę — reductions lecą, kolejka puchnie |

To najtańszy sposób, żeby dwie osoby obok siebie zobaczyły **inny** profil obciążenia i same zapytały dlaczego. Obsługa ma gotową puentę: *„on wiezie lód, ty wieziesz antymaterię — spójrz na reductions magazynu”*.

### Panel statku (jeden ekran, jeden główny przycisk)

Stały badge na górze: **„YOUR SHIP: `ship_millennium_falcon` · `#PID<0.842.0>`”** — to jest string, którego odwiedzający szuka na dużym ekranie.

| Akcja | Co się dzieje w systemie | Co widać w Voyagerze |
| --- | --- | --- |
| **Rejestracja** | Pod `Station.DockingBay` startuje GenServer zarejestrowany pod nazwą statku, z ładownią pełną kontenerów w stanie procesu | Nowy node **wjeżdża z animacją w drzewo**, podpisany nazwą statku. Pierwsze „wow”: *„ta kropka to ty”*. Przy okazji w Node Info **rośnie licznik atomów** — patrz niżej |
| **TRANSFER CARGO** (cookie clicker, główny przycisk) | Każde kliknięcie to **jedna wiadomość** `ship_* → Station.Warehouse` z jednym kontenerem. Statek usuwa go ze swojego stanu, magazyn **liczy checksumę zawartości** i dokłada kontener do swojego stanu, a po przyjęciu podbija wiersz w ETS | **Pamięć statku maleje**, **pamięć magazynu rośnie**, **reductions magazynu lecą**, a przy szybkim klikaniu piętrzy się **`message_queue_len`** magazynu |
| **UNDOCK** (wyjście) | Statek normalnie kończy pracę i znika z drzewa. Bez dramatu, bez crasha | Node **znika z drzewa** z animacją. Wiersz w leaderboardzie zostaje |

Nie ma przycisku awarii ani losowych katastrof. Jedyne, co może usunąć czyjś statek poza nim samym, to **ręczne wyrzucenie z `/ops`** — narzędzie obsługi na wypadek nazwy, która przeszła przez filtr, a nie powinna.

### Licznik atomów jako feature, nie bug

Nazwy statków są rejestrowane jako atomy, więc każda nowa nazwa **realnie powiększa tablicę atomów** — i to widać w Node Info w sekcji limitów (`atoms: 14 203 / 1 048 576`). Zamiast to chować, pokazujemy: *„każda wasza nazwa to jeden atom więcej, i tego się nie da cofnąć — dlatego w prawdziwym systemie nigdy nie robi się atomów z inputu użytkownika”*.

Przy skali stoiska (setki nazw przez dwa dni) to zero ryzyka, a jako lekcja działa lepiej niż jakikolwiek slajd. Higiena i tak zostaje: limit długości nazwy, ograniczony zestaw znaków, ta sama nazwa nie tworzy drugiego atomu, plus górny limit różnych nazw na sesję z fallbackiem do nazwy generowanej.

---

## 4. Ruch w tle: producenci i konsumenci

Stacja **nie czeka na ludzi**. W tle pracuje automatyczna flota — i to ona wprowadza do dema klasyczny problem **producentów i konsumentów**.

- **Freighters (producenci, dużo).** Dokują, wysyłają kontenery do magazynu, odlatują. Robią dokładnie to samo, co odwiedzający, tylko bez kciuka.
- **Haulers (konsumenci, mało).** Proszą magazyn o ładunek, dostają go i wywożą. Każde odebranie to kolejna wiadomość **do tego samego procesu** i kolejne zdjęcie danych z jego stanu.

Konsumentów jest **celowo za mało**. Efekt jest widoczny w Voyagerze bez tłumaczenia: **pamięć magazynu rośnie w długim trendzie**, bo wpływa więcej, niż wypływa. Gdy dołączają odwiedzający, tempo przyrostu skacze.

Obsługa ma na to jedną gałkę w `/ops`: **`Dispatch extra haulers`**. Dodanie konsumentów sprawia, że pamięć magazynu zaczyna **spadać** na oczach. To druga — obok przełącznika trybu — naprawa wykonywana na żywo i potwierdzana w Voyagerze.

Trzy rzeczy jednym mechanizmem:

1. **Metryki mają tło.** Node stojący na zerze i node robiący nagle coś to zły kontrast. Stacja pracująca spokojnie na ~20–30% i wchodząca na 90% widać z drugiego końca alejki.
2. **Attract loop.** Oba ekrany żyją, gdy nikogo nie ma, a obsługa może ćwiczyć demo o ósmej rano.
3. **Tryb awaryjny.** Gdy padnie sieć i nikt nie dołączy, sama flota wystarcza, żeby pokazać całe demo z narracją.

Natężenie ruchu (`quiet / normal / rush hour`) też siedzi w `/ops`.

---

## 5. Trzy numery popisowe

Wszystkie trzy to ten sam schemat: **problem widoczny w Voyagerze → diagnoza w Voyagerze → naprawa jednym kliknięciem obsługi → potwierdzenie w Voyagerze.** To jest dokładnie to, do czego narzędzie służy w pracy.

### 5.1 Wąskie gardło na jednym GenServerze

Wszyscy wysyłają do **jednego** magazynu, a ten liczy checksumy po kolei. Trzy klikające osoby wystarczą, żeby `message_queue_len` poszedł w setki, przy jednym scheduleru pod sufitem i reszcie rdzeni bezczynnych.

**Diagnoza:** lista procesów posortowana po reductions → `Station.Warehouse` → panel szczegółów → kolejka na 1200.

**Naprawa — przełącznik trybu magazynu w `/ops`:**

- **`SINGLE CLERK`** — magazyn liczy checksumy sam, w swoim procesie.
- **`INSPECTION CREW`** — magazyn zleca liczenie puli workerów i tylko scala wyniki.

Przełączone w trakcie klikania: kolejka drenuje się na oczach, obciążenie rozlewa się na wszystkie schedulery, liczba procesów skacze. Cała rozmowa o serializacji na GenServerze dzieje się sama.

### 5.2 Producent szybszy od konsumenta

Pamięć magazynu rośnie w trendzie, bo haulerów jest za mało. Widać to jako powoli pełzający w górę wykres pamięci procesu i całego node'a.

**Naprawa:** `Dispatch extra haulers` → pamięć zaczyna spadać.

### 5.3 Gruby proces

Po kilku minutach magazyn to jeden GenServer z setkami MB w stanie, długą kolejką i sporym heapem — czyli dokładnie ten patologiczny obiekt, którego wszyscy szukamy na produkcji. Voyager pokazuje jego pamięć, heap, stack, kolejkę i reductions w jednym panelu, a obok stoją setki chudych statków dla porównania.

---

## 6. Skala obciążenia

**Dwadzieścia pięć bezczynnych GenServerów to na BEAM-ie dosłownie nic**, więc obciążenie musi być zaprojektowane.

### 6.1 Skąd bierze się koszt

| Źródło | Mechanizm | Metryka |
| --- | --- | --- |
| Kliknięcie „transfer” | wiadomość + checksuma po stronie magazynu | reductions i pamięć magazynu w górę, pamięć statku w dół |
| Szybkie klikanie / kilka osób | magazyn nie nadąża | `message_queue_len` w setkach–tysiącach |
| Tryb `INSPECTION CREW` | pula workerów | liczba procesów, wszystkie run queues |
| Freighters (producenci) | stały strumień kontenerów | tło ~20–30% schedulerów |
| Haulers (konsumenci) | odbiór ładunku | odciążenie pamięci, dodatkowe wiadomości do magazynu |
| Wybór `ANTIMATTER` | droga checksuma | skok reductions z jednego kliknięcia |

### 6.2 Cztery gałki strojenia

1. **Koszt inspekcji na kontener** (per rodzaj ładunku) — decyduje, czy jedno kliknięcie w ogóle widać.
2. **Rozmiar kontenera** — decyduje, jak szybko rośnie pamięć magazynu.
3. **Natężenie ruchu w tle** — poziom morza, na którym widać fale od ludzi.
4. **Stosunek freighterów do haulerów** — tempo pełzania pamięci w górę.

Wszystkie w configu. **Strojenie odbywa się na miejscu**, pierwszego dnia.

### 6.3 Większy node — świadoma decyzja

Bierzemy **maszynę z zapasem** (4+ vCPU), żeby mieć pewność, że nic nie padnie przy tłumie, a telefony pozostaną responsywne. To nie osłabia dema, a wręcz wzmacnia jego główny numer: **wąskie gardło na jednym procesie jest tym bardziej wymowne, im więcej rdzeni obok się nudzi.** Kolejka rośnie, a trzy czwarte maszyny stoi — i dokładnie to widać w run queues.

Kosztem jest to, że tło musi być odpowiednio większe (więcej freighterów), a checksuma odpowiednio droższa, żeby liczby w ogóle drgały. To kwestia strojenia, nie architektury.

### 6.4 Żeby demo nie zjadło własnego ogona

Phoenix serwujący telefony siedzi na tym samym node'cie:

- inspekcje (i workerzy) na `priority: :low` — LiveView się przepycha,
- **rate limit liczony po stronie serwera**, sufit ~10 kliknięć/s na statek — cookie clicker zaprasza autoklikery, więc bez tego jedna osoba wyłącza stoisko,
- globalny limit pojemności magazynu: po przekroczeniu magazyn **zrzuca najstarszy ładunek** i ogłasza to na telewizorze jako zdarzenie,
- watchdog na `run_queue` i pamięć.

---

## 7. Pixel art — prosto, ale estetycznie

Cała warstwa wizualna to **pixel art**, na obu ekranach, z jedną spójną zasadą: **mało kolorów, duże piksele, żadnego bitmapowego chaosu**.

- **Paleta:** 4–6 kolorów na scenę, wyprowadzone z tokenów DaisyUI, żeby motyw jasny i ciemny działały same z siebie. Kolory znaczą: statki neutralne, magazyn akcentowy, ostrzeżenia w `warning`/`error`.
- **Siatka:** wszystko na 8 px, sprite'y 16×16 (kontener, statek, ikona ładunku) i 32×32 (magazyn, dok). `image-rendering: pixelated`, skalowanie tylko całkowitymi wielokrotnościami — inaczej piksele się rozmyją i cały efekt znika.
- **Animacja:** klatkowa, 4–6 klatek, sterowana CSS `steps()` — kontener sunący po taśmie, mrugająca lampka doku, pulsujący magazyn, gdy kolejka rośnie. Żadnych bibliotek, żadnego canvasu; sprite'y inline jako SVG albo data URI, bo wolno nam tylko `app.js` i `app.css`.
- **Typografia:** font pikselowy **hostowany lokalnie** (bundlowany do `priv/static/fonts`, jak obecne fonty Voyagera) — na nagłówki i liczniki. Do dłuższych tekstów zwykły monospace, bo font pikselowy w małym rozmiarze jest nieczytelny na telefonie.
- **Telewizor** to jedna szeroka scena stacji: doki po bokach, magazyn w środku, taśma z kontenerami, wizualna kolejka przed magazynem (im dłuższa, tym więcej pikselowych skrzynek stoi w rzędzie), pasek zdarzeń na dole.
- **Telefon** to kokpit: ładownia jako siatka skrzynek ubywających z każdym kliknięciem, wielki przycisk `TRANSFER`, licznik i wskaźniki. Główny przycisk musi być **satysfakcjonujący w dotyku** — odbicie, dźwięk wyłączony domyślnie, haptyka `navigator.vibrate`.
- Gdy magazyn się zatyka, telefon **czuje opór**: kontenery wychodzą wolniej, zapala się `STATION CONGESTED — QUEUE: 847`. Backpressure jako doznanie, nie liczba na cudzym ekranie.
- **Leaderboard** wygląda jak surowy dump ETS: monospace, `ship | cargo | containers | last delivery`. Bo nim jest — to samo widać potem w przeglądarce ETS w Voyagerze.

Estetyka pixel-art ma dodatkowy zysk: rysowanie jej jest tanie, a wygląda celowo. Ładny pixel art z sześcioma kolorami zrobi lepsze wrażenie niż półśrodkowa grafika „prawie 3D”.

---

## 8. Jak to zbudować (z lotu ptaka)

**Osobna, mała aplikacja Phoenix** (`station`), w oddzielnym repo, bez Ecto. Cały stan w procesach, jedna tabela ETS na leaderboard, jeden plik na dysku jako jego trwały zrzut.

**Jedna aplikacja = jedno drzewo superwizji = jeden system.** Nazwy dobrane tak, żeby drzewo w Voyagerze czytało się jak schemat stacji, bez legendy:

```
station (app)
└─ Station.Supervisor
   ├─ Station.Warehouse             – GenServer: cały przyjęty ładunek w stanie procesu
   │                                  (gruby proces + kolejka = bohater dema)
   ├─ Station.InspectionCrew        – Supervisor puli workerów liczących checksumy
   │                                  (aktywna tylko w trybie INSPECTION CREW)
   ├─ Station.Leaderboard           – właściciel tabeli ETS + zapis do pliku
   ├─ Station.ShipRegistry          – Registry: nazwa statku → pid
   ├─ Station.DockingBay            – DynamicSupervisor: statki odwiedzających
   │  ├─ ship_millennium_falcon
   │  ├─ ship_nostromo
   │  └─ …                          (~25 max — to jest ta czytelna część)
   ├─ Station.TrafficControl        – Supervisor floty automatycznej
   │  ├─ Station.FreighterLine      – DynamicSupervisor: producenci
   │  │  └─ freighter_01 …          (zwinięte do licznika)
   │  └─ Station.HaulerLine         – DynamicSupervisor: konsumenci
   │     └─ hauler_01 …             (kilka sztuk, celowo za mało)
   └─ Station.OpsPanel              – GenServer trzymający ustawienia obsługi
                                      (tryb magazynu, natężenie ruchu)
```

Górna część drzewa jest płytka i samotłumacząca się — każdy `ship_*` to ktoś obecny w sali. `Station.FreighterLine` i `Station.InspectionCrew` są w Voyagerze **domyślnie stubami z liczbą dzieci**, więc drzewo zostaje czytelne, a licznik przy nich skacze po przełączeniu trybu.

To rozwiązuje pozorną sprzeczność z ograniczeniem nr 2 z sekcji 1: limit „~150 procesów” dotyczy tego, co **rozwinięte**, a nie tego, co żyje na node'cie.

### Leaderboard: ETS + plik

- `Station.Leaderboard` jest właścicielem tabeli ETS `station_leaderboard` (`ship | cargo | containers | last_delivery`).
- Zrzut do pliku cyklicznie (np. co 30 s) i przy zamykaniu aplikacji; wczytanie przy starcie.
- Dzięki temu leaderboard **przeżywa restart node'a**, deploy i wieczorne wyłączenie stoiska — a rano wstaje z wynikami z poprzedniego dnia.
- Historia dla publiczności robi się trzypoziomowa i domyka temat trwałości: **stan procesu → ETS → plik**.
- `/ops` ma osobno `Reset leaderboard` (czyści ETS i plik), na wypadek gdybyśmy chcieli zacząć dzień od zera.

### Guardrails

- **Nazwy statków**: filtr wulgaryzmów (angielski + polski), limit długości, ograniczony zestaw znaków, normalizacja do slug, dedup. Ręczne `Remove ship` w `/ops` jako ostatnia linia obrony.
- Sufit kliknięć na sekundę, pojemność magazynu, TTL bezczynnego statku (~5 min).
- **Panel `/ops`**: tryb magazynu, natężenie ruchu, `Dispatch extra haulers`, `Remove ship`, `Reset leaderboard`, reset stacji.
- `/ops` pod **osobną, nieodgadywalną ścieżką z hasłem**.

### Ile statków naraz?

~300–400 osób na konferencji, przy stoisku realnie do ~20 naraz, plus 3–5 niesprzątniętych jeszcze przez TTL → **cap ~25 żywych statków**. Ważniejszy argument niż wydajność: 25 to już gęste drzewo na dużym ekranie, a czytelność jest tu produktem. Powyżej capu nowi wchodzą w **tryb obserwatora**.

BEAM uniesie 25 000 statków — cap jest dla ludzkiego oka, nie dla runtime'u. Warto to powiedzieć na głos, bo sama ta różnica jest puentą.

### Deployment

- Stacja na VPS-ie (4+ vCPU) za HTTPS, publiczny URL z QR — telefony po wifi konferencyjnym albo po komórce. Pod QR-em drukujemy URL dla kogoś na 5G.
- **VPS możliwie blisko venue**: walk drzewa to ~`6 + 2 × depth` round-tripów w 5 s deadline, więc RTT mnoży się ×14 przy depth 4. Przy 30–50 ms walk kończy się w ~1 s; przy 150 ms ociera się o deadline.
- **Voyager łączy się connectorem SSH** (tunel + proxowany EPMD) — porty dystrybucji zamknięte, a przy okazji demo funkcji SSH.
- Strojenie pod WAN: refresh drzewa **2 s**, **depth ≤ 4**, relacje off. Node Info 1–2 s.
- Laptop: wifi konferencyjne, **tethering z telefonu obsługi jako stały backup**.
- Tryby awaryjne: laptop offline → tethering; wszystko offline → lokalna kopia stacji na laptopie i demo na samej flocie; puste stoisko → flota trzyma ekrany przy życiu.
- **Presety Voyagera**: zakładka otwierająca dokładnie ten widok drzewa (`apps`, `depth`, relacje w query params) i zapamiętane połączenie SSH — reset widoku jednym kliknięciem, bo laptopa dotykają odwiedzający.
- Credentiale traktujemy jako spalone: **jednorazowy VPS, dedykowane cookie, dedykowany klucz SSH**, wszystko rotowane po konferencji. VPS hostuje tylko stację, jako nieuprzywilejowany użytkownik, wystawia 443 i 22.

---

## 9. Ryzyka i przeciwdziałania

| Ryzyko | Przeciwdziałanie |
| --- | --- |
| Przeglądarka ETS nie zdąży | Leaderboard pokazujemy tylko na telewizorze; reszta dema bez zmian. |
| Lista procesów nie zdąży | Diagnozę robimy w drzewie: klikamy `Station.Warehouse` i czytamy kolejkę w panelu szczegółów. |
| Metryki się nie ruszają | Sekcja 6: koszt inspekcji, rozmiar kontenera, ruch w tle, stosunek producentów do konsumentów — wszystko strojone na miejscu. |
| Za duża maszyna → wszystko wygląda płasko | Więcej freighterów i droższa checksuma; kolejka na jednym procesie i tak rośnie niezależnie od liczby rdzeni. |
| Telefony przestają odpowiadać pod obciążeniem | `priority: :low`, sufit kliknięć/s, limit pojemności magazynu, watchdog. |
| Autokliker / skrypt w konsoli | Rate limit po stronie serwera, nie w JS. |
| Wulgarna nazwa statku | Filtr + limit znaków + `Remove ship` w `/ops`. |
| Tablica atomów rośnie | Świadoma decyzja i element narracji; limit długości, dedup, górny limit różnych nazw na sesję z fallbackiem. |
| Za dużo statków → nieczytelne drzewo | Cap ~25, TTL, tryb obserwatora, flota i workerzy zwinięci do stubów. |
| Wifi na venue blokuje SSH albo zrywa | Tethering jako stały backup; lokalna kopia stacji w ostateczności. |
| Latencja WAN wpycha walk w 5 s deadline | VPS blisko venue, depth ≤ 4, refresh 2 s, relacje off. |
| Odwiedzający rozkonfigurują Voyagera | Zakładki resetujące widok, zapamiętane połączenie. |
| Credentiale na publicznym laptopie | Jednorazowy VPS, dedykowane cookie i klucz, rotacja po konferencji. |
| Pixel art rozmyty na dużym telewizorze | Skalowanie wyłącznie całkowitymi wielokrotnościami, `image-rendering: pixelated`, sprite'y projektowane pod docelową rozdzielczość. |

---

## 10. Scenariusz stoiskowy na 90 sekund

Nie sekwencja do przejścia, tylko kolejność, którą obsługa proponuje. Można wejść i wyjść w dowolnym miejscu.

1. „Zarejestruj statek — nazwa i ładunek.” → `ship_*` wjeżdża w drzewo superwizji. *(supervision tree)*
2. „Klikaj, nie przestawaj.” → **pamięć statku maleje, pamięć magazynu rośnie**, reductions magazynu lecą. *(szczegóły procesu, dwa procesy naraz)*
3. „On wiezie lód, ty antymaterię — porównaj.” → różny koszt tego samego kliknięcia. *(reductions)*
4. „Teraz wszyscy naraz.” → kolejka magazynu w setkach, telefon stawia opór. *(bottleneck i backpressure)*
5. „Znajdź wąskie gardło.” → lista procesów po reductions → `Station.Warehouse`. *(diagnoza)*
6. Obsługa przełącza na `INSPECTION CREW` → kolejka drenuje się na oczach. *(naprawa i potwierdzenie)*
7. „Zobacz, dlaczego pamięć rośnie mimo to.” → za mało haulerów → `Dispatch extra haulers` → pamięć spada. *(producent/konsument)*
8. „A twój wynik?” → przeglądarka ETS, twój wiersz w `station_leaderboard`, który przeżyje wszystko. *(ETS + plik)*
9. „Zapytaj o coś.” → MCP odpowiada normalnym zdaniem. *(MCP)*

Punkty 5–7 to serce dema: **problem → diagnoza → naprawa → potwierdzenie, wszystko w Voyagerze, w minutę.**

---

## 11. Decyzje podjęte

- **Bez celu gry, bez awarii.** Żadnych misji, poziomów, wygranej ani katastrof. Statek albo pracuje, albo odlatuje (`UNDOCK`). Jedyne wymuszone usunięcie to `Remove ship` w `/ops`.
- **Stacja to jedna aplikacja, jedno drzewo superwizji, jeden system.** Statek dołącza do niego jako **proces nazwany**.
- **Bez pośredników**: statek ↔ magazyn, message passing, koniec.
- **Ładunek żyje w stanie procesów** po obu stronach. **W ETS jest wyłącznie leaderboard**, dodatkowo **zrzucany do pliku**, żeby przeżył restart node'a.
- **Rejestracja: własna nazwa statku + wybór ładunku z presetów.** Nazwa staje się atomem — i robimy z tego lekcję zamiast problemu.
- **Magazyn liczy checksumę** przyjmowanego ładunku — stąd realne obciążenie i naturalny bottleneck.
- **Boty w dwóch rolach:** freightery (producenci, dużo) i haulery (konsumenci, mało) → problem producenta i konsumenta widoczny jako pełzająca pamięć magazynu.
- **Dwa numery „naprawy na żywo”:** przełącznik `SINGLE CLERK / INSPECTION CREW` oraz `Dispatch extra haulers`.
- **Pixel art** na obu ekranach: mała paleta, siatka 8 px, animacja `steps()`, font pikselowy hostowany lokalnie.
- **Wszystko po angielsku.**
- **Sieć:** wyłącznie publiczny internet, VPS **4+ vCPU** blisko venue, Voyager przez SSH, tethering jako backup.
- **Skala:** cap **~25 statków**, powyżej tryb obserwatora.
- **Branding na telefonie:** link do repo i strony Voyagera, opcjonalny zapis na listę — **bez CTA „pobierz”**, bo Voyager jest aplikacją desktopową i nikt nie zainstaluje jej z telefonu.
- **Repo:** osobne. **Ekrany:** laptop (Voyager) + telewizor (Station Ops).

## 12. Wciąż otwarte

- Czy zostawiamy obsłudze możliwość **restartu magazynu z `/ops`** (pokazuje restart supervisora i to, że leaderboard w ETS przeżywa, a ładunek nie)? Awarie wypadły z konceptu, ale to jedyna rzecz, która pokazuje restart w drzewie — do decyzji, czy warto trzymać jako narzędzie obsługi.
- Czy kontener ma być **dużym binary** (współdzielonym przy wysyłce) czy **strukturą termów** (kopiowaną do skrzynki odbiorcy)? Zmienia profil obciążenia i jest niezłą ciekawostką przy stoisku.
- Ile dokładnie haulerów na starcie i jak agresywny ma być `Dispatch extra haulers`, żeby spadek pamięci był widoczny w ciągu ~10 s.
- Czy leaderboard resetujemy codziennie rano, czy niech rośnie przez całą konferencję?
