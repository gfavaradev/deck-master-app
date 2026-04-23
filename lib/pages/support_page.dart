import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  Future<void> _sendEmail(
      BuildContext context, {
      required String subject,
      required String body,
    }) async {
    final uri = Uri.parse(
      'mailto:g.favara.dev@gmail.com?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) { // ignore: empty_catches
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessun client email trovato')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supporto'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.bgLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.support_agent, size: 48, color: AppColors.gold),
                const SizedBox(height: 12),
                const Text(
                  'Come possiamo aiutarti?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
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

          // Section label
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'CONTATTACI',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                letterSpacing: 1.0,
              ),
            ),
          ),

          // Bug report
          _SupportTile(
            icon: Icons.bug_report_outlined,
            iconColor: Colors.orangeAccent,
            title: 'Segnala un Problema',
            subtitle: 'Hai riscontrato un bug o un comportamento inatteso?',
            onTap: () => _sendEmail(
              context,
              subject: 'Segnalazione Problema - Deck Master',
              body:
                  'Ciao,\n\nHo riscontrato il seguente problema:\n\n[Descrivi il problema qui]\n\n---\nAccount: $userEmail',
            ),
          ),
          const SizedBox(height: 8),

          // Missing cards
          _SupportTile(
            icon: Icons.style_outlined,
            iconColor: AppColors.blue,
            title: 'Carte Mancanti',
            subtitle: 'Segnala carte assenti o con dati errati nel catalogo.',
            onTap: () => _sendEmail(
              context,
              subject: 'Carte Mancanti - Deck Master',
              body:
                  'Ciao,\n\nVorrei segnalare le seguenti carte mancanti/errate:\n\nCollezione: [Yu-Gi-Oh! / One Piece / ...]\nCarta: [Nome carta]\nSet: [Numero Codice]\nMotivo: [Mancante / Dati errati / Immagine sbagliata]\n\n---\nAccount: $userEmail',
            ),
          ),
          const SizedBox(height: 8),

          // Generic suggestion
          _SupportTile(
            icon: Icons.lightbulb_outline,
            iconColor: AppColors.gold,
            title: 'Suggerimento',
            subtitle: 'Hai un\'idea per migliorare l\'app? Scrivici!',
            onTap: () => _sendEmail(
              context,
              subject: 'Suggerimento - Deck Master',
              body:
                  'Ciao,\n\nVorrei suggerire la seguente funzionalità o miglioramento:\n\n[Descrivi il suggerimento qui]\n\n---\nAccount: $userEmail',
            ),
          ),

          const SizedBox(height: 32),

          // ── Donate section ──────────────────────────────────────
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'SUPPORTA IL PROGETTO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.gold,
                letterSpacing: 1.0,
              ),
            ),
          ),

          _DonateCard(),

        ],
      ),
    );
  }
}

class _DonateCard extends StatelessWidget {
  static const String _donationUrl = 'https://ko-fi.com/deckmaster';

  Future<void> _openDonation(BuildContext context) async {
    final uri = Uri.parse(_donationUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) { // ignore: empty_catches
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire il link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6B35).withValues(alpha: 0.15),
            const Color(0xFFFFB347).withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.coffee, color: Color(0xFFFF6B35), size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offrimi un caffe!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Deck Master è gratuita e sviluppata nel tempo libero. Se ti piace, puoi supportarmi con una piccola donazione.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openDonation(context),
              icon: const Icon(Icons.favorite, size: 16),
              label: const Text('Supporta il progetto'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Completamente facoltativo — grazie di cuore!',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
