# Redmine Issue Repeat

Fügt Redmine 6 ein Intervall-Dropdown zum Ticketformular hinzu und erstellt beim Anlegen eines Tickets automatisch eine Kopie mit entsprechend verschobenem Beginn-Datum.

## Installation

- Dieses Verzeichnis in `plugins/redmine_issue_repeat` innerhalb der Redmine-Installation ablegen.
- `bundle install` im Redmine-Hauptverzeichnis ausführen.
- Migration ausführen: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
- Redmine neu starten.

## Verhalten

- Neues Custom Field `Intervall` (Liste: täglich, wöchentlich, monatlich) für Tickets.
- Beim Erstellen eines Tickets wird eine Kopie erzeugt:
  - `assigned_to` und `estimated_hours` werden übernommen.
  - Kommentare und Dateien werden nicht übernommen.
  - Status ist Standard-Status (Neu/Angelegt).
  - Beginn-Datum ist je nach Intervall: morgen, in 1 Woche, in 1 Monat.
  - Das Feld `Intervall` der Kopie wird geleert, damit keine Endlosschleife entsteht.

