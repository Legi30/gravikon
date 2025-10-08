# Gravitační schůzkovač

**Gravitační schůzkovač** je interaktivní webová aplikace postavená v Ruby on Rails. Umožňuje plánovat schůzky mezi tělesy v planetárním systému s ohledem na relativistické efekty, jako je **zpoždění signálu** (vlivem konečné rychlosti světla) a **dilatace času** (způsobená gravitačním zakřivením).

Projekt je určen pro vzdělávací nebo výzkumné účely v oblasti obecné teorie relativity a astrofyziky.

---

## 🧩 Hlavní funkce

- Správa schůzek mezi planetami a měsíci
- Výpočet průměrného zpoždění signálu mezi účastníky
- Výpočet průměrné lokální délky schůzky s ohledem na dilataci času
- Uživatelské rozhraní pro vytváření, úpravu a mazání schůzek
- Čtení parametrů těles ze souboru `data/system_data.json`

---

## ⚙️ Technické parametry

| Technologie      | Verze             |
|------------------|-------------------|
| Ruby             | 3.1.2             |
| Rails            | 7.0.8             |
| Databáze         | SQLite3 (lokální) |
| JavaScript       | žádný (čisté HTML/ERB) |
| Deployment       | Lokální server (`rails server`) |

---

## 📦 Instalace

### 1. Stažení projektu

Rozbal stažený ZIP:

cd gravikon

### 2. Instalace závislostí

Ujisti se, že máš nainstalovaný Ruby a Bundler. Poté spusť:

gem install bundler
bundle install

### 3. Inicializace databáze

Aplikace používá SQLite, takže není potřeba nic instalovat navíc:

rails db:create db:migrate

### 4. Spuštění serveru

rails server

Otevři webový prohlížeč a navštiv:

http://localhost:3000

### Hotovo!

Aplikace je nyní připravena k použití.

### Autor

Autor: David Novák
Licence: MIT
Kontakt: novak.1113@gmail.com
