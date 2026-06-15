import '../l10n/app_localizations.dart';
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
          SnackBar(content: Text(AppLocalizations.of(context)!.msgNoEmailClient)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.supportTitle),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
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
            title: AppLocalizations.of(context)!.supportReportBugTitle,
            subtitle: AppLocalizations.of(context)!.supportReportBugSubtitle,
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
            title: AppLocalizations.of(context)!.supportMissingCardsTitle,
            subtitle: AppLocalizations.of(context)!.supportMissingCardsSubtitle,
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
            title: AppLocalizations.of(context)!.supportSuggestionTitle,
            subtitle: AppLocalizations.of(context)!.supportSuggestionSubtitle,
            onTap: () => _sendEmail(
              context,
              subject: 'Suggerimento - Deck Master',
              body:
                  'Ciao,\n\nVorrei suggerire la seguente funzionalità o miglioramento:\n\n[Descrivi il suggerimento qui]\n\n---\nAccount: $userEmail',
            ),
          ),


        ],
      ),
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
