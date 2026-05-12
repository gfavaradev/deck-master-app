import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/cardtrader_service.dart';
import '../theme/app_colors.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class _Point {
  final DateTime date;
  final double euros;
  final bool isHistorical;
  const _Point({required this.date, required this.euros, required this.isHistorical});
}

// ─── Period enum ──────────────────────────────────────────────────────────────

enum _Period {
  week('7G', 7),
  month('30G', 30),
  year('1A', 365);

  final String label;
  final int days;
  const _Period(this.label, this.days);
}

// ─── Public widget ────────────────────────────────────────────────────────────

class CardtraderPriceHistoryChart extends StatefulWidget {
  final CardModel card;
  const CardtraderPriceHistoryChart({super.key, required this.card});

  @override
  State<CardtraderPriceHistoryChart> createState() =>
      _CardtraderPriceHistoryChartState();
}

class _CardtraderPriceHistoryChartState
    extends State<CardtraderPriceHistoryChart> {
  _Period _period = _Period.month;
  late Future<List<_Point>> _future;

  static String _expCode(String sn) =>
      sn.isEmpty ? '' : sn.split('-').first.toLowerCase();

  static String _collNum(String sn) {
    final i = sn.indexOf('-');
    return i < 0 ? '' : sn.substring(i + 1);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final c = widget.card;
    final sn = c.serialNumber;
    final from = DateTime.now().subtract(Duration(days: _period.days));
    _future = CardtraderService()
        .getCardPriceHistory(
          catalog: c.collection,
          expansionCode: _expCode(sn),
          cardName: c.name,
          language: CardtraderService.languageFromSerial(sn, c.collection),
          rarity: c.rarity.isNotEmpty ? c.rarity : null,
          collectorNumber: _collNum(sn),
          catalogId: c.catalogId,
          from: from,
        )
        .then((rows) => rows
            .map((r) => _Point(
                  date: DateTime.parse(r['recorded_date'] as String),
                  euros: (r['price_cents'] as int) / 100,
                  isHistorical: (r['listing_count'] as int) == 0,
                ))
            .toList());
  }

  void _setPeriod(_Period p) {
    if (_period == p) return;
    setState(() {
      _period = p;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Point>>(
      future: _future,
      builder: (ctx, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final points = snap.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period selector
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _Period.values
                  .map((p) => _PeriodBtn(p, _period, _setPeriod))
                  .toList(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 140,
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.cardtraderTeal),
                      ),
                    )
                  : points.length < 2
                      ? _EmptyState(hasSomeHistory: points.length == 1)
                      : _Chart(points: points),
            ),
          ],
        );
      },
    );
  }
}

// ─── Period button ────────────────────────────────────────────────────────────

class _PeriodBtn extends StatelessWidget {
  final _Period period;
  final _Period selected;
  final void Function(_Period) onTap;
  const _PeriodBtn(this.period, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    final active = period == selected;
    return GestureDetector(
      onTap: () => onTap(period),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? AppColors.cardtraderTeal.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active
                ? AppColors.cardtraderTeal
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          period.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? AppColors.cardtraderTeal : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSomeHistory;
  const _EmptyState({required this.hasSomeHistory});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart_rounded,
              size: 28,
              color: AppColors.textHint.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            hasSomeHistory
                ? 'Dati insufficienti per il periodo selezionato.'
                : 'Il grafico si popolerà ad ogni sincronizzazione prezzi.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textHint.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chart ────────────────────────────────────────────────────────────────────

class _Chart extends StatelessWidget {
  final List<_Point> points;
  const _Chart({required this.points});

  @override
  Widget build(BuildContext context) {
    final minY = points.map((p) => p.euros).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.euros).reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2 + 0.05;
    final chartMinY = (minY - padding).clamp(0.0, double.infinity);
    final chartMaxY = maxY + padding;

    // X: days since epoch
    final spots = points
        .map((p) => FlSpot(
              p.date.millisecondsSinceEpoch / 86400000,
              p.euros,
            ))
        .toList();

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final xRange = (maxX - minX).clamp(1.0, double.infinity);

    // Tick interval: show 4 labels max
    final xInterval = (xRange / 3).ceilToDouble();

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: chartMinY,
        maxY: chartMaxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.divider.withValues(alpha: 0.5),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: _niceInterval(chartMinY, chartMaxY),
              getTitlesWidget: (v, _) => Text(
                '€${v.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 8, color: AppColors.textHint),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: xInterval,
              getTitlesWidget: (v, _) {
                final d = DateTime.fromMillisecondsSinceEpoch(
                    (v * 86400000).toInt());
                return Text(
                  '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 8, color: AppColors.textHint),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: AppColors.cardtraderTeal,
            barWidth: 2,
            dotData: FlDotData(
              show: points.length <= 14,
              getDotPainter: (_, p2, p3, p4) => FlDotCirclePainter(
                radius: 2.5,
                color: AppColors.cardtraderTeal,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.cardtraderTeal.withValues(alpha: 0.25),
                  AppColors.cardtraderTeal.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.bgLight,
            tooltipRoundedRadius: 6,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '€${s.y.toStringAsFixed(2)}',
                      const TextStyle(
                        color: AppColors.cardtraderTeal,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  static double _niceInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 0) return 1;
    // 3-4 ticks
    final raw = range / 3;
    final mag = (raw == 0) ? 1.0 : pow10(raw.abs().toString().length - 2);
    return (raw / mag).ceilToDouble() * mag;
  }

  static double pow10(int exp) {
    double r = 1;
    for (var i = 0; i < exp; i++) {
      r *= 10;
    }
    return r;
  }
}
