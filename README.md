# Redmine Issue Repeat

Fügt Redmine 6 ein Intervall-Dropdown zum Ticketformular hinzu und erstellt beim Anlegen eines Tickets automatisch eine Kopie mit entsprechend verschobenem Beginn-Datum.

## Installation

- Dieses Verzeichnis in `plugins/redmine_issue_repeat` innerhalb der Redmine-Installation ablegen.
- `bundle install` im Redmine-Hauptverzeichnis ausführen.
- Migration ausführen: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
- Redmine neu starten.

## Verarbeitung der Wiederholungen

- Geplante Erstellung wird über den Task `bundle exec rake redmine_issue_repeat:process RAILS_ENV=production` durchgeführt (per Cron z. B. jede Minute ausführen).
- Zeiten konfigurierst du unter `Administration → Plugins → Redmine Issue Repeat → Konfiguration`:
  - `Uhrzeit täglich (HH:MM)`
  - `Uhrzeit wöchentlich (HH:MM)` (Wiederholung immer +7 Tage)
  - `Uhrzeit monatlich (HH:MM)` (gleiches Tagesdatum; bei fehlendem Datum letzter Tag des Monats)
  - `Minuten bei stündlich` (0 = volle Stunde)
- Die Einstellungsseite zeigt eine Liste aller Tickets mit aktivem Intervall und dem nächsten Ausführungszeitpunkt.

## Verhalten

- Neues Custom Field `Intervall` (Liste: stündlich, täglich, wöchentlich, monatlich) für Tickets.
- Beim Erstellen eines Tickets wird eine Kopie erzeugt:
  - `assigned_to` und `estimated_hours` werden übernommen.
  - Kommentare und Dateien werden nicht übernommen.
  - Status ist Standard-Status (Neu/Angelegt).
  - Beginn-Datum ist je nach Intervall: morgen, in 1 Woche, in 1 Monat.
  - Das Feld `Intervall` der Kopie wird geleert, damit keine Endlosschleife entsteht.
- Zusätzlich wird ein Zeitplan angelegt, der zukünftige Kopien zu den konfigurierten Zeiten erstellt. Für `stündlich` erfolgt keine sofortige Kopie; die nächste Kopie wird zur vollen Stunde (oder konfigurierten Minute) erzeugt.
