import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/data_repository.dart';
import '../theme/app_colors.dart';

// ─── Period ────────────────────────────────────────────────────────────────────

enum CollectionChartPeriod {
  week('7G', 7),
  month('30G', 30),
  year('1A', 365);

  final String label;
  final int days;
  const CollectionChartPeriod(this.label, this.days);
}

// ─── Data point ────────────────────────────────────────────────────────────────

class _ValuePoint {
  final DateTime date;
  final double euros;
  const _ValuePoint(this.date, this.euros);
}

// ─── Public widget ─────────────────────────────────────────────────────────────

/// Line chart showing total collection value over time.
/// [collection] null = global (sum of all collections).
class CollectionValueChart extends StatefulWidget {
  final String? collection;
  final Color accentColor;

  const CollectionValueChart({
    super.key,
    this.collection,
    this.accentColor = AppColors.gold,
  });

  @override
  State<CollectionValueChart> createState() => _CollectionValueChartState();
}

class _CollectionValueChartState extends State<CollectionValueChart> {
  CollectionChartPeriod _period = CollectionChartPeriod.month;
  late Future<List<_ValuePoint>> _future;
  final _repo = DataRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final from = DateTime.now().subtract(Duration(days: _period.days));
    _future = _repo
        .getCollectionValueHistory(collection: widget.collection, from: from)
        .then((rows) => rows
            .map((r) => _ValuePoint(
                  DateTime.parse(r['recorded_date'] as String),
                  (r['total_cents'] as int) / 100,
                ))
            .toList());
  }

  void _setPeriod(CollectionChartPeriod p) {
    if (_period == p) return;
    setState(() {
      _period = p;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_ValuePoint>>(
      future: _future,
      builder: (ctx, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final points = snap.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: CollectionChartPeriod.values
                  .map((p) => _PeriodBtn(p, _period, _setPeriod,
                      color: widget.accentColor))
                  .toList(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: loading
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: widget.accentColor),
                      ),
                    )
                  : points.length < 2
                      ? _EmptyState(color: widget.accentColor)
                      : _Chart(points: points, color: widget.accentColor),
            ),
          ],
        );
      },
    );
  }
}

// ─── Period button ─────────────────────────────────────────────────────────────

class _PeriodBtn extends StatelessWidget {
  final CollectionChartPeriod period;
  final CollectionChartPeriod selected;
  final void Function(CollectionChartPeriod) onTap;
  final Color color;
  const _PeriodBtn(this.period, this.selected, this.onTap,
      {required this.color});

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
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          period.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? color : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final Color color;
  const _EmptyState({required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart_rounded,
              size: 28, color: color.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text(
            'Il grafico si aggiorna ogni volta che\nvisiti questa pagina.',
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

// ─── Chart ─────────────────────────────────────────────────────────────────────

class _Chart extends StatelessWidget {
  final List<_ValuePoint> points;
  final Color color;
  const _Chart({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    final minY = points.map((p) => p.euros).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.euros).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.15 + 1.0;
    final chartMinY = (minY - pad).clamp(0.0, double.infinity);
    final chartMaxY = maxY + pad;

    final spots = points
        .map((p) =>
            FlSpot(p.date.millisecondsSinceEpoch / 86400000, p.euros))
        .toList();

    final minX = spots.first.x;
    final maxX = spots.last.x;
    final xRange = (maxX - minX).clamp(1.0, double.infinity);
    final xInterval = (xRange / 3).ceilToDouble();

    // Trend: positive = green tint, negative = red tint
    final isUp = points.last.euros >= points.first.euros;
    final lineColor = isUp ? color : Colors.redAccent;

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
            color: AppColors.divider.withValues(alpha: 0.4),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: _niceInterval(chartMinY, chartMaxY),
              getTitlesWidget: (v, _) => Text(
                '€${v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0)}',
                style:
                    const TextStyle(fontSize: 8, color: AppColors.textHint),
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
            curveSmoothness: 0.35,
            color: lineColor,
            barWidth: 2.5,
            dotData: FlDotData(
              show: points.length <= 14,
              getDotPainter: (_, p2, p3, p4) => FlDotCirclePainter(
                radius: 2.5,
                color: lineColor,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.22),
                  lineColor.withValues(alpha: 0.0),
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
                      TextStyle(
                        color: lineColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
    if (range <= 0) return 10;
    final raw = range / 3;
    final mag = _pow10((raw.abs().toString().split('.').first.length - 1)
        .clamp(0, 10));
    return (raw / mag).ceilToDouble() * mag;
  }

  static double _pow10(int exp) {
    double r = 1;
    for (var i = 0; i < exp; i++) {
      r *= 10;
    }
    return r;
  }
}
