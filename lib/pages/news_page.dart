import '../l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final _repo = DataRepository();
  List<Map<String, dynamic>>? _news;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final news = await _repo.getNews();
      if (!mounted) return;
      setState(() { _news = news; _loading = false; _error = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        top: false,
        bottom: true,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    }
    final l10n = AppLocalizations.of(context)!;
    if (_error != null) {
      return _buildEmptyState(
        icon: Icons.wifi_off_outlined,
        title: l10n.newsNetworkError,
        subtitle: l10n.newsNetworkErrorSubtitle,
        onRefresh: _load,
      );
    }
    if (_news == null || _news!.isEmpty) {
      return _buildEmptyState(
        icon: Icons.newspaper_outlined,
        title: l10n.newsNoNews,
        subtitle: l10n.newsNoNewsSubtitle,
        onRefresh: _load,
      );
    }

    // Pinned first, then chronological
    final pinned = _news!.where((n) => n['pinned'] == true).toList();
    final regular = _news!.where((n) => n['pinned'] != true).toList();
    final sorted = [...pinned, ...regular];

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      color: AppColors.gold,
      backgroundColor: AppColors.bgMedium,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.bgDark,
            expandedHeight: 0,
            title: Text(
              AppLocalizations.of(context)!.newsTitle,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
                onPressed: () => _load(silent: true),
                tooltip: AppLocalizations.of(context)!.newsRefreshTooltip,
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _NewsCard(news: sorted[i]),
                childCount: sorted.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onRefresh,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bgMedium,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(icon, size: 42, color: AppColors.textHint),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textHint, fontSize: 14)),
            if (onRefresh != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(AppLocalizations.of(context)!.newsRefreshTooltip),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.gold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatefulWidget {
  final Map<String, dynamic> news;
  const _NewsCard({required this.news});

  @override
  State<_NewsCard> createState() => _NewsCardState();
}

class _NewsCardState extends State<_NewsCard> {
  bool _expanded = false;

  static const _collectionColors = {
    'yugioh': Color(0xFF7B1FA2),
    'pokemon': Color(0xFFF57C00),
    'onepiece': Color(0xFFD32F2F),
    'magic': Color(0xFF7B5EA7),
    'all': AppColors.gold,
  };

  static const _collectionLabels = {
    'yugioh': 'Yu-Gi-Oh!',
    'pokemon': 'Pokémon',
    'onepiece': 'One Piece',
    'magic': 'Magic',
  };

  String _collectionLabel(String key, AppLocalizations l10n) =>
      _collectionLabels[key] ?? (key == 'all' ? l10n.newsCollectionAll : key);

  String _formatDate(dynamic ts, AppLocalizations l10n) {
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is String) {
      dt = DateTime.tryParse(ts);
    }
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return l10n.newsDateToday;
    if (diff.inDays == 1) return l10n.newsDateYesterday;
    if (diff.inDays < 7) return l10n.newsDateDaysAgo(diff.inDays);
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final n = widget.news;
    final isPinned = n['pinned'] == true;
    final title = n['title'] as String? ?? '';
    final subtitle = n['subtitle'] as String?;
    final body = n['body'] as String? ?? '';
    final imageUrl = n['imageUrl'] as String?;
    final externalUrl = n['externalUrl'] as String?;
    final rawCollections = n['collections'];
    final collections = rawCollections is List
        ? rawCollections.map((e) => e.toString()).toList()
        : <String>[];
    final dateStr = _formatDate(n['publishedAt'], l10n);
    final isLongBody = body.length > 160;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPinned
              ? AppColors.gold.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (imageUrl != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (ctx, url) => Container(
                  height: 160,
                  color: AppColors.bgLight,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textHint),
                  ),
                ),
                errorWidget: (ctx, url, err) => const SizedBox.shrink(),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: pinned badge + date
                Row(
                  children: [
                    if (isPinned) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(AppLocalizations.of(context)!.newsHighlight,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (dateStr.isNotEmpty)
                      Text(dateStr,
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 11)),
                    const Spacer(),
                    // Collection chips
                    ...collections.take(3).map((key) {
                      final color = _collectionColors[key] ?? AppColors.textHint;
                      final label = _collectionLabel(key, l10n);
                      return Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 8),

                // Title
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.3)),

                // Subtitle
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                ],

                // Body
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: (_expanded || !isLongBody)
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: Text(
                      isLongBody ? '${body.substring(0, 160)}...' : body,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                    ),
                    secondChild: Text(
                      body,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ),
                  if (isLongBody)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _expanded ? l10n.newsShowLess : l10n.newsReadAll,
                          style: const TextStyle(
                              color: AppColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],

                // External link
                if (externalUrl != null && externalUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _openUrl(externalUrl),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.open_in_new, size: 13, color: AppColors.blue),
                        const SizedBox(width: 4),
                        Text(AppLocalizations.of(context)!.newsReadMore,
                            style: const TextStyle(
                                color: AppColors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
