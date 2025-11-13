import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Using custom painters instead of fl_chart for compatibility
class SimpleBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  const SimpleBarChart({super.key, required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _BarChartPainter(values: values, labels: labels, color: Theme.of(context).colorScheme.primary),
      );
    });
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;
  _BarChartPainter({required this.values, required this.labels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bg = Paint()..color = Colors.grey.shade200;
    // draw background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);
    // draw background grid
    final stepY = size.height / 5;
    final gridPaint = Paint()..color = Colors.grey.withOpacity(0.2);
    for (int i = 0; i <= 5; i++) {
      canvas.drawLine(Offset(0, stepY * i), Offset(size.width, stepY * i), gridPaint);
    }

    if (values.isEmpty) return;
    final maxY = 100.0;
    final barWidth = size.width / (values.length * 2 + 1);
    for (int i = 0; i < values.length; i++) {
      final x = barWidth * (1 + i * 2);
      final h = (values[i] / maxY) * (size.height - 20);
      final rect = Rect.fromLTWH(x, size.height - h - 20, barWidth, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);
      // label
      final tp = TextPainter(text: TextSpan(text: labels[i].split('-').last, style: const TextStyle(fontSize: 12, color: Colors.black)), textDirection: TextDirection.ltr);
      tp.layout(maxWidth: barWidth * 2);
      tp.paint(canvas, Offset(x - (tp.width - barWidth) / 2, size.height - 18));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SimplePieChart extends StatelessWidget {
  final double percent; // 0-100
  final Color color;
  const SimplePieChart({super.key, required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(140, 140),
      painter: _PieChartPainter(percent: percent, color: color),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final double percent;
  final Color color;
  _PieChartPainter({required this.percent, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paintBg = Paint()..color = Colors.grey.shade300;
    final paint = Paint()..color = color;
    final center = rect.center;
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, paintBg);
    final sweep = (percent / 100) * 2 * 3.141592653589793;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -3.141592653589793 / 2, sweep, true, paint);
    // inner circle
    final inner = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius * 0.5, inner);
    // text
    final tp = TextPainter(text: TextSpan(text: '${percent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)), textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Map<String, double> _weekData = {}; // date -> compliance percent (0-100)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // show mock data immediately so UI doesn't spin when no real data exists
    _setMockData();
    // fetch real data in background and update when available
    _loadWeekData();
  }

  Future<void> _loadWeekData() async {
    setState(() {
      _loading = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // fall back to mock data
      _setMockData();
      return;
    }

    try {
      final now = DateTime.now();
      // build 7-day keys yyyy-MM-dd
      final keys = List.generate(7, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
      final db = FirebaseDatabase.instance.ref();
      final Map<String, double> tmp = {};
      for (final d in keys.reversed) {
        final key = d.toIso8601String().substring(0, 10);
        final snap = await db.child('compliance').child(user.uid).child('week').child(key).get();
        if (snap.exists) {
          final val = snap.value;
          double percent = 0;
          if (val is num) percent = (val as num).toDouble();
          else if (val is Map && val['percent'] is num) percent = (val['percent'] as num).toDouble();
          tmp[key] = percent.clamp(0, 100);
        } else {
          tmp[key] = 0;
        }
      }
      setState(() {
        _weekData = tmp;
      });
    } catch (e) {
      // fallback
      _setMockData();
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _setMockData() {
    final now = DateTime.now();
    final Map<String, double> tmp = {};
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      tmp[d.toIso8601String().substring(0, 10)] = (50 + (i * 5)) % 100 + 10; // some mock
    }
    setState(() {
      _weekData = tmp;
      // keep loading flag as-is; UI will show mock immediately regardless
    });
  }

  @override
  Widget build(BuildContext context) {
    // Always render charts immediately (with mock data if real data hasn't loaded yet)
    final labels = _weekData.keys.toList();
    final values = _weekData.values.toList();
    final totalAvg = values.isNotEmpty ? (values.reduce((a, b) => a + b) / values.length) : 0.0;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Thống kê tuân thủ (7 ngày gần nhất)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              flex: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SimpleBarChart(values: values, labels: labels),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 1,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tỷ lệ tuân thủ trung bình', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text('${totalAvg.toStringAsFixed(1)}%'),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: SimplePieChart(percent: totalAvg, color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
