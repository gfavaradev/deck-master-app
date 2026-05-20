import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class TutorialPage extends StatefulWidget {
  final VoidCallback? onComplete;
  const TutorialPage({super.key, this.onComplete});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  static const _steps = [
    _TutorialStep(
      icon: Icons.style,
      iconColor: AppColors.gold,
      title: 'Benvenuto in Deck Master!',
      subtitle: 'La tua app per gestire le collezioni di carte',
      description: 'Tieni traccia di tutte le tue carte, monitora i prezzi di mercato e organizza la tua collezione in un unico posto.',
    ),
    _TutorialStep(
      icon: Icons.lock_open_outlined,
      iconColor: Color(0xFF4FC3F7),
      title: 'Sblocca le Collezioni',
      subtitle: 'Yu-Gi-Oh!, Pokémon, One Piece, Magic e altre ancora',
      description: 'Dalla schermata Home tocca una collezione per sbloccarla. La prima è sempre gratuita!\n\nCon il piano Pro sblocchi tutto senza pubblicità.',
    ),
    _TutorialStep(
      icon: Icons.add_card,
      iconColor: AppColors.success,
      title: 'Aggiungi le tue Carte',
      subtitle: 'Manualmente o tramite fotocamera',
      description: 'Dentro una collezione usa il tasto "+" per aggiungere carte. Puoi anche scansionarle con la fotocamera.\n\nSpecifica la quantità, condizione e lingua di ogni carta.',
    ),
    _TutorialStep(
      icon: Icons.search,
      iconColor: AppColors.purple,
      title: 'Esplora il Catalogo',
      subtitle: 'Tutte le carte disponibili al tuo fianco',
      description: 'Nel tab "Catalogo" trovi tutte le carte del gioco. Puoi cercare per nome, set o rarità e aggiungerle direttamente alla tua collezione.',
    ),
    _TutorialStep(
      icon: Icons.favorite_border,
      iconColor: AppColors.error,
      title: 'Wishlist & ROI',
      subtitle: 'Monitora prezzi e investimenti',
      description: 'Aggiungi le carte che vuoi alla Wishlist e ricevi un avviso quando il prezzo scende.\n\nCon la sezione ROI, inserisci il prezzo pagato per ogni carta e scopri quanto vale il tuo investimento.',
    ),
    _TutorialStep(
      icon: Icons.emoji_events,
      iconColor: AppColors.gold,
      title: 'Sei pronto!',
      subtitle: 'Inizia la tua avventura da collezionista',
      description: 'I prezzi vengono aggiornati automaticamente da CardTrader.\n\nDalle Impostazioni puoi esportare la collezione, gestire il profilo e rileggere questa guida in qualsiasi momento.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _steps.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _steps.length - 1;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(foregroundColor: AppColors.textHint),
                  child: const Text('Salta', style: TextStyle(fontSize: 14)),
                ),
              ),
            ),
            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _steps.length,
                itemBuilder: (_, i) => _StepPage(step: _steps[i]),
              ),
            ),
            // Dots + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                children: [
                  _DotsIndicator(count: _steps.length, current: _page),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Text(isLast ? 'Inizia!' : 'Avanti'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single step page ──────────────────────────────────────────────────────────

class _StepPage extends StatelessWidget {
  final _TutorialStep step;
  const _StepPage({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: step.iconColor.withValues(alpha: 0.12),
              border: Border.all(color: step.iconColor.withValues(alpha: 0.35), width: 2),
              boxShadow: [
                BoxShadow(
                  color: step.iconColor.withValues(alpha: 0.25),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(step.icon, size: 56, color: step.iconColor),
          ),
          const SizedBox(height: 36),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            step.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.bgMedium,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              step.description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dots indicator ────────────────────────────────────────────────────────────

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;
  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.gold : AppColors.textHint.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _TutorialStep {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String description;

  const _TutorialStep({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.description,
  });
}
