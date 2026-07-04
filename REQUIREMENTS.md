# REQUIREMENTS.md — template Spec-Driven Development

Copia questo template in un file separato per ogni feature/refactor non banale (es. `REQUIREMENTS_pro_promo_v2.md`) prima di chiedere l'implementazione. Definire prima requisiti e vincoli riduce le iterazioni e le allucinazioni sull'architettura.

## Obiettivo
<Una frase: cosa deve fare la feature e perché.>

## Contesto / stato attuale
<File e servizi coinvolti, comportamento esistente, link a issue/PR correlate.>

## Requisiti funzionali
- [ ] ...
- [ ] ...

## Vincoli tecnici
- Piattaforme target (Android/iOS/Windows/Web) e eventuali degradazioni via `PlatformHelper`.
- Servizi/livelli coinvolti (`lib/services/`, Firestore rules, ecc.) — niente accesso diretto a Firestore/SQLite dalle pagine.
- Localizzazione: serve IT/EN (`AppLocalizations`) o è una pagina admin (non localizzata)?

## Criteri di accettazione
- [ ] `flutter analyze` pulito sulle nuove modifiche.
- [ ] Test unitari/regressione aggiornati o aggiunti (`test/unit/`, `integration_test/crashes/` se pertinente).
- [ ] Verifica manuale (screenshot/simulatore) se UI.

## Fuori scope
<Cosa esplicitamente NON fare in questa iterazione.>
