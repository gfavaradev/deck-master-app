import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import 'app_guide_page.dart';
import 'tutorial_page.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  Future<void> _sendEmail(BuildContext context, {required String subject, required String body}) async {
    final uri = Uri.parse(
      'mailto:g.favara.dev@gmail.com?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.msgNoEmailClient)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(l10n.supportTitle),
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Column(
                children: [
                  const Icon(Icons.support_agent, size: 52, color: AppColors.gold),
                  const SizedBox(height: 12),
                  const Text(
                    'Come possiamo aiutarti?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Contattaci per qualsiasi problema o suggerimento.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Contattaci ────────────────────────────────────────────────────
            _SectionLabel(label: 'CONTATTACI', color: AppColors.gold),
            const SizedBox(height: 8),
            _SupportCard(children: [
              _SupportTile(
                icon: Icons.bug_report_outlined,
                iconColor: Colors.orangeAccent,
                title: l10n.supportReportBugTitle,
                subtitle: l10n.supportReportBugSubtitle,
                onTap: () => _sendEmail(context,
                  subject: 'Segnalazione Problema - Deck Master',
                  body: 'Ciao,\n\nHo riscontrato il seguente problema:\n\n[Descrivi il problema qui]\n\n---\nAccount: $userEmail',
                ),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.style_outlined,
                iconColor: AppColors.blue,
                title: l10n.supportMissingCardsTitle,
                subtitle: l10n.supportMissingCardsSubtitle,
                isLast: true,
                onTap: () => _sendEmail(context,
                  subject: 'Carte Mancanti - Deck Master',
                  body: 'Ciao,\n\nVorrei segnalare le seguenti carte mancanti/errate:\n\nCollezione: [Yu-Gi-Oh! / One Piece / ...]\nCarta: [Nome carta]\nSet: [Numero Codice]\nMotivo: [Mancante / Dati errati / Immagine sbagliata]\n\n---\nAccount: $userEmail',
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── La tua opinione conta ─────────────────────────────────────────
            const _SectionLabel(label: 'LA TUA OPINIONE CONTA', color: Colors.redAccent),
            const SizedBox(height: 8),
            _SupportCard(children: [
              _SupportTile(
                icon: Icons.star_outline,
                iconColor: AppColors.gold,
                title: 'Lascia una recensione',
                subtitle: 'Hai apprezzato l\'app? Aiutaci con una valutazione sullo store',
                onTap: () => _sendEmail(context,
                  subject: 'Recensione - Deck Master',
                  body: 'Ciao,\n\nVorrei lasciare il seguente feedback sull\'app:\n\nValutazione: [⭐⭐⭐⭐⭐]\n\n[Scrivi qui la tua opinione]\n\n---\nAccount: $userEmail',
                ),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.share_outlined,
                iconColor: AppColors.blue,
                title: 'Condividi Deck Master',
                subtitle: 'Consiglia l\'app ad altri collezionisti',
                onTap: () => SharePlus.instance.share(
                  ShareParams(
                    text: '🃏 Gestisco la mia collezione di carte con Deck Master!\n\nSupporta Yu-Gi-Oh!, Pokémon, One Piece, Magic e molti altri TCG. Prezzi aggiornati, scanner, deck builder e tanto altro.\n\nScaricalo su App Store e Google Play: cerca "Deck Master TCG"',
                  ),
                ),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.lightbulb_outline,
                iconColor: AppColors.gold,
                title: 'Suggerimenti',
                subtitle: 'Hai idee per migliorare l\'app? Scrivici',
                isLast: true,
                onTap: () => _sendEmail(context,
                  subject: 'Suggerimenti - Deck Master',
                  body: 'Ciao,\n\nVorrei suggerire la seguente funzionalità o miglioramento:\n\n[Descrivi il suggerimento qui]\n\n---\nAccount: $userEmail',
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Domande frequenti ─────────────────────────────────────────────
            const _SectionLabel(label: 'DOMANDE FREQUENTI', color: AppColors.blue),
            const SizedBox(height: 8),
            _FaqCard(items: const [
              _FaqItem(
                question: 'Come aggiungo una carta alla mia collezione?',
                answer: 'Puoi aggiungere carte in tre modi: cerca dal Catalogo e tocca "Aggiungi", usa lo Scanner per fotografare la carta, oppure tocca una carta nel dettaglio del set. Specifica la quantità e conferma.',
              ),
              _FaqItem(
                question: 'Come funziona la Wishlist?',
                answer: 'Tocca il ❤ su qualsiasi carta per aggiungerla alla Wishlist. Puoi impostare un prezzo obiettivo: riceverai una notifica push quando il prezzo scende sotto la soglia impostata.',
              ),
              _FaqItem(
                question: 'Come costruisco un deck?',
                answer: 'Vai nella raccolta della tua collezione, seleziona la tab "Deck" e tocca + per creare un nuovo mazzo. Apri il deck e aggiungi le carte dalla sezione "Carte Possedute" in basso.',
              ),
              _FaqItem(
                question: 'Come sincronizzo i dati su più dispositivi?',
                answer: 'La sincronizzazione avviene automaticamente quando sei connesso. Accedi con lo stesso account su ogni dispositivo. Puoi anche forzarla manualmente da Impostazioni → Sincronizzazione.',
              ),
              _FaqItem(
                question: 'Cos\'è il piano Pro?',
                answer: 'Il piano Pro sblocca: esportazione Excel, statistiche avanzate, ROI, condivisione deck, costruttore AI per Yu-Gi-Oh! e nessuna pubblicità. Lo trovi in Impostazioni → Passa a Pro.',
              ),
              _FaqItem(
                question: 'Come funziona lo scanner?',
                answer: 'Tocca l\'icona scanner in alto. Inquadra la carta con la fotocamera in buona illuminazione e tienila ferma. L\'app la riconosce automaticamente e ti propone di aggiungerla alla raccolta.',
              ),
              _FaqItem(
                question: 'I prezzi sono aggiornati?',
                answer: 'Sì, i prezzi vengono sincronizzati ogni giorno da CardTrader. Se vuoi aggiornare manualmente, vai in Impostazioni → Sincronizzazione e tocca "Aggiorna Prezzi".',
              ),
            ]),
            const SizedBox(height: 24),

            // ── Altro ─────────────────────────────────────────────────────────
            const _SectionLabel(label: 'ALTRO', color: AppColors.textHint),
            const SizedBox(height: 8),
            _SupportCard(children: [
              _SupportTile(
                icon: Icons.menu_book_outlined,
                iconColor: Color(0xFF9B59B6),
                title: 'Guida alle funzionalità',
                subtitle: 'Scopri passo per passo come usare ogni funzione dell\'app',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppGuidePage())),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.play_circle_outline,
                iconColor: AppColors.gold,
                title: 'Rivedi il tutorial',
                subtitle: 'Guarda di nuovo la presentazione iniziale dell\'app',
                isLast: true,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TutorialPage())),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 0),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ─── Support card wrapper ─────────────────────────────────────────────────────

class _SupportCard extends StatelessWidget {
  final List<Widget> children;
  const _SupportCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.5),
        child: Column(children: children),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 64));
}

// ─── Support tile ─────────────────────────────────────────────────────────────

class _SupportTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLast;

  const _SupportTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(13.5))
          : BorderRadius.zero,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── FAQ card ─────────────────────────────────────────────────────────────────

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

class _FaqCard extends StatefulWidget {
  final List<_FaqItem> items;
  const _FaqCard({required this.items});

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  int? _openIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.5),
        child: Column(
          children: widget.items.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            final isOpen = _openIndex == i;
            final isLast = i == widget.items.length - 1;
            return Column(
              children: [
                if (i > 0)
                  Container(height: 0.5, color: AppColors.divider, margin: const EdgeInsets.only(left: 16)),
                InkWell(
                  borderRadius: isLast && !isOpen
                      ? const BorderRadius.vertical(bottom: Radius.circular(13.5))
                      : BorderRadius.zero,
                  onTap: () => setState(() => _openIndex = isOpen ? null : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.question,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isOpen ? AppColors.blue : AppColors.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: isOpen ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            color: isOpen ? AppColors.blue : AppColors.textHint,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isOpen)
                  Container(
                    width: double.infinity,
                    color: AppColors.bgLight,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      item.answer,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
