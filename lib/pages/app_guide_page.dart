import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<_Step> steps;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.steps,
  });
}

class _Step {
  final String text;
  const _Step(this.text);
}

const _kFeatures = [
  _Feature(
    icon: Icons.collections_bookmark_outlined,
    color: Color(0xFF9B59B6),
    title: 'Le Collezioni',
    description: 'Ogni collezione rappresenta un gioco di carte (Yu-Gi-Oh!, Pokémon, ecc.). Sblocca le collezioni che possiedi per iniziare a gestirle.',
    steps: [
      _Step('Vai nelle Impostazioni → Gestione Collezioni'),
      _Step('Attiva le collezioni che possiedi'),
      _Step('Ogni collezione apparirà nel menu principale'),
      _Step('Puoi cambiare la collezione attiva dal selettore in alto'),
    ],
  ),
  _Feature(
    icon: Icons.add_circle_outline,
    color: AppColors.gold,
    title: 'Aggiungere Carte',
    description: 'Ci sono tre modi per aggiungere carte alla tua collezione: manualmente dal catalogo, tramite scanner o importando da file.',
    steps: [
      _Step('Catalogo: cerca la carta, tocca "Aggiungi" e inserisci la quantità'),
      _Step('Scanner: inquadra la carta con la fotocamera per un riconoscimento automatico'),
      _Step('Usa il filtro per cercare per nome, set o codice seriale'),
      _Step('Le carte aggiunte appaiono subito nella tua raccolta'),
    ],
  ),
  _Feature(
    icon: Icons.document_scanner_outlined,
    color: Colors.lightBlue,
    title: 'Scanner Carte',
    description: 'Fotografa una carta con la fotocamera per riconoscerla automaticamente e aggiungerla alla collezione in un tocco.',
    steps: [
      _Step('Tocca l\'icona scanner nella barra in alto'),
      _Step('Inquadra bene la carta — tieni la fotocamera ferma'),
      _Step('L\'app riconosce la carta e mostra i dettagli'),
      _Step('Conferma la quantità e aggiungi alla collezione'),
      _Step('Funziona meglio con buona illuminazione e carta non riflettente'),
    ],
  ),
  _Feature(
    icon: Icons.search,
    color: AppColors.cardtraderTeal,
    title: 'Catalogo & Prezzi',
    description: 'Il catalogo mostra tutte le carte disponibili con prezzi aggiornati da CardTrader. Puoi sfogliare, filtrare e aggiungere direttamente dalla lista.',
    steps: [
      _Step('Seleziona la collezione e tocca "Catalogo"'),
      _Step('Usa la barra di ricerca per trovare una carta specifica'),
      _Step('I prezzi si aggiornano automaticamente ogni giorno'),
      _Step('Tocca il ❤ per aggiungere alla Wishlist direttamente dal catalogo'),
      _Step('Tocca una carta per vedere il dettaglio completo e i prezzi per rarità'),
    ],
  ),
  _Feature(
    icon: Icons.book_outlined,
    color: AppColors.gold,
    title: 'Album',
    description: 'Gli album ti permettono di organizzare le carte della tua raccolta in raccoglitori virtuali, con una capacità massima personalizzabile.',
    steps: [
      _Step('Nella raccolta, vai nella tab "Album"'),
      _Step('Tocca + per creare un nuovo album e imposta nome e capacità'),
      _Step('Apri un album per vedere le carte contenute'),
      _Step('Aggiungi carte all\'album dalla raccolta principale'),
      _Step('Usa i contatori per sapere quante carte hai inserito'),
    ],
  ),
  _Feature(
    icon: Icons.style_outlined,
    color: AppColors.blue,
    title: 'Deck Builder',
    description: 'Costruisci e gestisci i tuoi mazzi da gioco. Tieni traccia di ogni carta, controlla la composizione e condividi i deck con altri giocatori.',
    steps: [
      _Step('Vai nella tab "Deck" della tua raccolta'),
      _Step('Tocca + per creare un nuovo deck'),
      _Step('Apri il deck e aggiungi carte dalla sezione "Carte Possedute"'),
      _Step('Usa il pulsante condividi per generare un link condivisibile (Pro)'),
      _Step('Per Yu-Gi-Oh! puoi usare il costruttore AI per suggerimenti automatici'),
    ],
  ),
  _Feature(
    icon: Icons.favorite_outline,
    color: Colors.redAccent,
    title: 'Wishlist & Avvisi Prezzi',
    description: 'Salva le carte che vuoi acquistare e ricevi notifiche quando il prezzo scende sotto la soglia che hai impostato.',
    steps: [
      _Step('Tocca il ❤ su qualsiasi carta per aggiungerla alla Wishlist'),
      _Step('Apri la Wishlist dal menu profilo in alto a destra'),
      _Step('Imposta un prezzo obiettivo per ogni carta'),
      _Step('Riceverai una notifica push quando il prezzo scende'),
      _Step('Rimuovi la carta dalla Wishlist una volta acquistata'),
    ],
  ),
  _Feature(
    icon: Icons.trending_up,
    color: AppColors.success,
    title: 'Statistiche & ROI',
    description: 'Monitora il valore totale della tua collezione nel tempo e calcola il rendimento del tuo investimento con grafici dettagliati.',
    steps: [
      _Step('Tocca l\'icona grafico nella barra in alto per le statistiche'),
      _Step('Visualizza il valore totale, le carte per rarità e i trend'),
      _Step('Il ROI confronta il costo stimato di acquisto con il valore attuale'),
      _Step('I dati si aggiornano automaticamente con ogni sync prezzi'),
      _Step('Disponibile solo con piano Pro'),
    ],
  ),
  _Feature(
    icon: Icons.notifications_outlined,
    color: Color(0xFFFF6D00),
    title: 'Notifiche',
    description: 'Deck Master ti avvisa quando i prezzi cambiano, quando ci sono aggiornamenti del catalogo o nuove funzionalità disponibili.',
    steps: [
      _Step('Abilita le notifiche nelle Impostazioni → Notifiche'),
      _Step('Le notifiche di prezzo arrivano quando un articolo in Wishlist scende'),
      _Step('Puoi vedere tutte le notifiche passate nella sezione Notifiche'),
      _Step('Tocca una notifica per andare direttamente alla carta'),
    ],
  ),
  _Feature(
    icon: Icons.file_download_outlined,
    color: Color(0xFF1D6F42),
    title: 'Esportazione Excel',
    description: 'Esporta tutta la tua raccolta in un file Excel (.xlsx) per analisi esterne, backup o condivisione con altri collezionisti.',
    steps: [
      _Step('Vai in Impostazioni → Esportazione'),
      _Step('Tocca "Esporta in Excel"'),
      _Step('Il file viene generato con Nome, Codice, Collezione, Rarità, Quantità e Valore'),
      _Step('Scegli dove salvare o condividere il file dal pannello di sistema'),
      _Step('Disponibile solo con piano Pro'),
    ],
  ),
  _Feature(
    icon: Icons.sync,
    color: AppColors.blue,
    title: 'Sincronizzazione Cloud',
    description: 'I tuoi dati vengono sincronizzati automaticamente su tutti i dispositivi tramite il tuo account. Non perderai mai la tua raccolta.',
    steps: [
      _Step('La sync avviene automaticamente all\'avvio e dopo ogni modifica'),
      _Step('Vai in Impostazioni → Sincronizzazione per forzarla manualmente'),
      _Step('Se vedi l\'icona ⚠️ c\'è un conflitto: scegli quale versione tenere'),
      _Step('Funziona anche offline: le modifiche si sincronizzano al ritorno della connessione'),
    ],
  ),
];

class AppGuidePage extends StatefulWidget {
  const AppGuidePage({super.key});

  @override
  State<AppGuidePage> createState() => _AppGuidePageState();
}

class _AppGuidePageState extends State<AppGuidePage> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Guida alle Funzionalità'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            ...List.generate(_kFeatures.length, (i) {
              final feature = _kFeatures[i];
              final isOpen = _expanded.contains(i);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FeatureCard(
                  feature: feature,
                  isOpen: isOpen,
                  onToggle: () => setState(() {
                    if (isOpen) {
                      _expanded.remove(i);
                    } else {
                      _expanded.add(i);
                    }
                  }),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.menu_book_outlined, color: AppColors.gold, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Come funziona Deck Master',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tocca una funzionalità per scoprire come usarla passo per passo.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  final bool isOpen;
  final VoidCallback onToggle;

  const _FeatureCard({
    required this.feature,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOpen ? feature.color.withValues(alpha: 0.4) : AppColors.border,
          width: isOpen ? 1 : 0.5,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: feature.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(feature.icon, color: feature.color, size: 22),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      feature.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isOpen ? feature.color : AppColors.textHint,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            Container(height: 0.5, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...feature.steps.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: feature.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${e.key + 1}',
                              style: TextStyle(
                                color: feature.color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.value.text,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
