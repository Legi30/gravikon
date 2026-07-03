# Gravitační schůzkovač (Gravikon)

**Gravitační schůzkovač** je interaktivní webová aplikace postavená v Ruby on Rails. Umožňuje plánovat schůzky mezi tělesy v **galaktickém prostředí s více sluneční mi soustavami**, které obíhají kolem centrální supermasivní černé díry. Aplikace zohledňuje relativistické efekty, jako je **zpoždění signálu** (vlivem konečné rychlosti světla) a **dilatace času** (způsobená gravitačním zakřivením).

Projekt je určen pro vzdělávací nebo výzkumné účely v oblasti obecné teorie relativity a astrofyziky.

---

## 🧩 Hlavní funkce

### Galaktický systém
- **Mapa galaxie** - Vizualizace více slunečních soustav obíhajících kolem centrální černé díry
- **Správa soustav** - Vytváření, úpravy a mazání slunečních soustav
- **Interaktivní vizualizace** - Klikatelné systémy na mapě galaxie s přechodem do detailu

### Schůzky
- **Schůzky v rámci soustavy** - Mezi tělesy v jedné sluneční soustavě
- **Mezisoustavové schůzky** - Mezi tělesy z různých slunečních soustav
- Výpočet průměrného zpoždění signálu mezi účastníky
- Výpočet průměrné lokální délky schůzky s ohledem na dilataci času

### Generování systémů
- Náhodné generování slunečních soustav s realistickými fyzikálními parametry
- Možnost vlastních těles (planety, měsíce) s definovatelnými parametry (hmotnost, poloměr, hustota)
- Validace orbitalních pozic (zabránění kolizím a výstupu z plátna)

---

## ⚙️ Technické parametry

| Technologie      | Verze / Popis     |
|------------------|-------------------|
| Ruby             | 3.4.5             |
| Rails            | 8.0.2             |
| Databáze         | SQLite3 (vývoj/test), multi-database (produkce) |
| JavaScript       | Vanilla JS (žádný framework) |
| Vizualizace      | SVG (interaktivní) |
| Cache            | Solid Cache (Rails 8) |
| Jobs             | Solid Queue (Rails 8) |
| Deployment       | Docker, Kamal, Thruster |

---

## 📦 Instalace

### 1. Klonování/stažení projektu

```bash
cd gravikon
```

### 2. Instalace závislostí

Ujisti se, že máš nainstalovaný Ruby 3.4.5 a Bundler:

```bash
gem install bundler
bundle install
```

### 3. Inicializace databáze

```bash
rails db:create db:migrate
```

### 4. Migrace dat (pouze při upgrade ze starší verze)

Pokud upgradujete ze single-system verze, spusť migraci:

```bash
rake data:migrate_to_multi_system
```

Toto vytvoří:
- `data/galaxy_data.json` - Konfiguraci galaxie
- `data/systems/` - Adresář pro jednotlivé soustavy
- `public/systems/` - Adresář pro SVG vizualizace soustav
- Zálohu starých dat v `data/backup/`

### 5. Spuštění serveru

```bash
rails server
```

Otevři webový prohlížeč a navštiv:

```
http://localhost:3000
```

**Hlavní stránky:**
- `/` - Domovská stránka a přehled schůzek
- `/galaxy` - **Mapa galaxie** s přehledem všech slunečních soustav
- `/meetings` - Správa schůzek
- `/meetings/new_inter_system` - Vytvoření mezisoustavové schůzky

### Hotovo!

Aplikace je nyní připravena k použití.

---

## 🚀 Použití

### Správa slunečních soustav

1. **Zobrazení mapy galaxie**: Navštiv `/galaxy` pro zobrazení všech soustav
2. **Vytvoření nové soustavy**:
   - Klikni na "Vytvořit novou soustavu" na mapě galaxie
   - Zadej název soustavy (3-50 znaků, alfanumerické znaky, mezery, pomlčky)
   - Zvol pozici v galaxii (X, Y souřadnice 0-800)
   - Nastav počet planet (1-10) a maximální počet měsíců na planetu (0-5)
   - Nebo vytvoř vlastní tělesa s konkrétními parametry
3. **Úprava soustavy**: Klikni na soustavu a pak na "Upravit"
4. **Regenerace soustavy**: Změň parametry a regeneruj pro novou konfiguraci
5. **Smazání soustavy**: V detailu soustavy klikni na "Smazat"

### Plánování schůzek

#### Schůzka v rámci soustavy

1. Navštiv `/meetings/new`
2. Zvol sluneční soustavu
3. Vyber alespoň 2 tělesa (planety, měsíce)
4. Nastav čas začátku a konce
5. Zadej téma schůzky
6. Klikni "Naplánovat schůzku"

Aplikace vypočítá:
- Průměrnou lokální dobu trvání (s gravitační dilatací času)
- Průměrné zpoždění signálu mezi účastníky

#### Mezisoustavová schůzka

1. Navštiv `/meetings/new_inter_system`
2. Vyber účastníky z různých slunečních soustav
3. Aplikace automaticky transformuje souřadnice do galaktického rámce
4. Nastav čas a téma
5. Klikni "Naplánovat schůzku"

Mezisoustavové schůzky zohledňují:
- Vzdálenosti mezi soustavami v galaxii
- Transformaci souřadnic z lokálních do galaktických
- Relativistické efekty napříč většími vzdálenostmi

### Užitečné příkazy

```bash
# Zobrazení statistik cache
rake cache:stats

# Vyčištění všech caches
rake cache:clear_all

# Zahřátí production cache
rake cache:warm

# Rollback migrace (v případě problémů)
rake data:rollback_multi_system

# Vyčištění legacy souborů po úspěšné migraci
rake data:cleanup_legacy_files
```

---

## 📊 Datová struktura

### Databáze
- `systems` - Tabulka slunečních soustav (název, pozice, cesta k JSON)
- `meetings` - Tabulka schůzek (čas, účastníci, systém, mezisoustavový flag)

### Souborová struktura
```
data/
  ├── galaxy_data.json          # Konfigurace galaxie (černá díra + reference na soustavy)
  ├── systems/
  │   ├── default_system.json   # Data první soustavy
  │   ├── <system_id>.json      # Data dalších soustav
  │   └── ...
  └── backup/                   # Zálohy z migrace

public/
  ├── galaxy.svg                # Vizualizace mapy galaxie
  └── systems/
      ├── default_system.svg    # Vizualizace první soustavy
      ├── <system_id>.svg       # Vizualizace dalších soustav
      └── ...
```

---

### Autor

Autor: David Novák
Licence: MIT
Kontakt: novak.1113@gmail.com
