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
                  Text(
                    l10n.supportHeaderTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.supportHeaderSubtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Contattaci ────────────────────────────────────────────────────
            _SectionLabel(label: l10n.supportSectionContact, color: AppColors.gold),
            const SizedBox(height: 8),
            _SupportCard(children: [
              _SupportTile(
                icon: Icons.bug_report_outlined,
                iconColor: Colors.orangeAccent,
                title: l10n.supportReportBugTitle,
                subtitle: l10n.supportReportBugSubtitle,
                onTap: () => _sendEmail(context,
                  subject: l10n.supportBugEmailSubject,
                  body: l10n.supportBugEmailBody(userEmail),
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
                  subject: l10n.supportMissingEmailSubject,
                  body: l10n.supportMissingEmailBody(userEmail),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── La tua opinione conta ─────────────────────────────────────────
            _SectionLabel(label: l10n.supportSectionOpinion, color: Colors.redAccent),
            const SizedBox(height: 8),
            _SupportCard(children: [
              _SupportTile(
                icon: Icons.star_outline,
                iconColor: AppColors.gold,
                title: l10n.supportReviewTitle,
                subtitle: l10n.supportReviewSubtitle,
                onTap: () => _sendEmail(context,
                  subject: l10n.supportReviewEmailSubject,
                  body: l10n.supportReviewEmailBody(userEmail),
                ),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.share_outlined,
                iconColor: AppColors.blue,
                title: l10n.supportShareTitle,
                subtitle: l10n.supportShareSubtitle,
                onTap: () => SharePlus.instance.share(
                  ShareParams(text: l10n.supportShareText),
                ),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.lightbulb_outline,
                iconColor: AppColors.gold,
                title: l10n.supportSuggestionsTitle,
                subtitle: l10n.supportSuggestionsSubtitle,
                isLast: true,
                onTap: () => _sendEmail(context,
                  subject: l10n.supportSuggestEmailSubject,
                  body: l10n.supportSuggestEmailBody(userEmail),
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Domande frequenti ─────────────────────────────────────────────
            _SectionLabel(label: l10n.supportSectionFaq, color: AppColors.blue),
            const SizedBox(height: 8),
            _FaqCard(items: [
              _FaqItem(question: l10n.supportFaqQ1, answer: l10n.supportFaqA1),
              _FaqItem(question: l10n.supportFaqQ2, answer: l10n.supportFaqA2),
              _FaqItem(question: l10n.supportFaqQ3, answer: l10n.supportFaqA3),
              _FaqItem(question: l10n.supportFaqQ4, answer: l10n.supportFaqA4),
              _FaqItem(question: l10n.supportFaqQ5, answer: l10n.supportFaqA5),
              _FaqItem(question: l10n.supportFaqQ6, answer: l10n.supportFaqA6),
              _FaqItem(question: l10n.supportFaqQ7, answer: l10n.supportFaqA7),
            ]),
            const SizedBox(height: 24),

            // ── Altro ─────────────────────────────────────────────────────────
            _SectionLabel(label: l10n.supportSectionOther, color: AppColors.textHint),
            const SizedBox(height: 8),
            _SupportCard(children: [
              _SupportTile(
                icon: Icons.menu_book_outlined,
                iconColor: const Color(0xFF9B59B6),
                title: l10n.supportGuideTitle,
                subtitle: l10n.supportGuideSubtitle,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppGuidePage())),
              ),
              _Divider(),
              _SupportTile(
                icon: Icons.play_circle_outline,
                iconColor: AppColors.gold,
                title: l10n.supportTutorialTitle,
                subtitle: l10n.supportTutorialSubtitle,
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
