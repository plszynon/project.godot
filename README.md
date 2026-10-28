# Żywy Świat

Voxelowa gra 3D (Godot 4.3) na Androida: bloki jak w Minecrafcie/Terrarii, ale świat **żyje**.

## Co już jest (v0.2)
- Świat generowany z **seeda** (ten sam seed = ten sam teren), góry, oceany, plaże, drzewa, śnieg
- **Żywy świat**: woda i lawa płyną, lawa + woda = obsydian/kamień, trawa rozrasta się na ziemię i obumiera pod blokami, cykl dnia i nocy
- **Tryb kreatywny** (lot, nieskończone bloki) i **przetrwania** (zbierasz bloki)
- **Przetrwanie**: serca (10), obrażenia od upadku, lawy i utonięcia, regeneracja, śmierć i odrodzenie
- **Moby**: świnie i krowy (dają mięso), zombie nocą (palą się w słońcu)
- **Kopanie z czasem** (przytrzymaj palec) i narzędzia: kilofy, siekiera, miecze
- **Crafting** (przycisk CRAFT): deski, patyki, narzędzia, pieczone mięso
- Tryb kreatywny: przycisk BLOKI wybiera blok do zaznaczonego slotu
- Ekran nowego świata: nazwa, seed, tryb, poziom wody, góry, lawa, szybkość zmian
- Sterowanie dotykowe, zapis/wczytywanie światów, autozapis

## Sterowanie
- Lewa strona ekranu: joystick (ruch)
- Prawa strona: przeciągnij = rozglądanie się; **tap** = uderz moba / (kreatywny) kop / (BUDUJ) postaw lub zjedz; **przytrzymaj** = kop blok (przetrwanie) albo powtarzaj
- `KOP` / `BUDUJ`: przełącznik działania tapa
- `SKOK`, `LOT` (kreatywny), `DÓŁ` (podczas lotu)
- Dolny pasek: wybór bloku (w tym woda i lawa)
- `SYM`: szybkość symulacji świata (STOP / 1x / 3x / 10x), `MENU`: pauza i zapis
- Przycisk „wstecz" w telefonie otwiera pauzę

## Budowanie APK
Każdy push na `main` odpala GitHub Actions (`.github/workflows/build-apk.yml`):
test → eksport APK → **Releases** (plik `zywy-swiat.apk` do pobrania na telefonie) i Artifacts.

## Testy lokalnie
```
godot --headless --path . res://tests/smoke.tscn
```

## Pomysły na dalej
jaskinie, więcej biomów, pory roku, erozja, sadzonki i rosnące drzewa, moby, crafting, tekstury.
