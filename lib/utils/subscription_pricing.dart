/// Calcoli sui prezzi degli abbonamenti Pro.
///
/// Vivono qui, separati dalla UI, perché il paywall deve poterli derivare dai
/// prezzi reali del negozio invece di mostrare percentuali scritte a mano: le
/// costanti valevano solo per l'Italia e restavano indietro a ogni cambio di
/// listino su Play Console e App Store Connect.
library;

/// Sconto percentuale di un piano pluri-mensile rispetto al costo equivalente
/// pagato mese per mese, troncato all'intero.
///
/// [monthlyPrice] è il prezzo del piano mensile, [planPrice] quello del piano
/// da confrontare e [months] la sua durata in mesi. Restituisce 0 quando il
/// mensile non è disponibile o quando il piano non conviene: uno sconto
/// negativo non va mostrato come tale.
///
/// Il troncamento è voluto: 27,59% diventa 27, non 28. Su una cifra
/// pubblicizzata è meglio promettere meno del reale che il contrario.
int savingsPercent({
  required double monthlyPrice,
  required double planPrice,
  required int months,
}) {
  if (monthlyPrice <= 0 || months <= 0) return 0;
  final perMonth = planPrice / months;
  final saving = (1 - perMonth / monthlyPrice) * 100;
  return saving <= 0 ? 0 : saving.floor();
}
