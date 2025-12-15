import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class StatsScreen extends StatefulWidget {
  final ValueNotifier<int>? selectedIndexNotifier;

  const StatsScreen({this.selectedIndexNotifier, super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;
  
  // Dữ liệu cho biểu đồ
  List<double> _weeklyRisks = List.filled(7, 0.0);
  List<String> _dateLabels = List.filled(7, "");
  double _averageRisk = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchWeeklyData();
  }

  // Hàm lấy dữ liệu từ Firestore
  Future<void> _fetchWeeklyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    List<double> risks = [];
    List<String> labels = [];
    double totalRisk = 0;
    int count = 0;

    DateTime now = DateTime.now();

    // Lặp 7 ngày: Từ 6 ngày trước -> Hôm nay
    for (int i = 6; i >= 0; i--) {
      DateTime date = now.subtract(Duration(days: i));
      String dateStr = DateFormat('yyyy-MM-dd').format(date);
      String label = DateFormat('dd/MM').format(date); 

      labels.add(label);

      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('medicine_times')
            .doc(user.uid)
            .collection('days')
            .doc(dateStr)
            .get();

        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          double risk = (data['prediction_risk'] ?? 0.0).toDouble();
          
          risks.add(risk * 100); 
          
          if (data.containsKey('prediction_risk')) {
             totalRisk += risk;
             count++;
          }
        } else {
          risks.add(0.0); 
        }
      } catch (e) {
        print("Lỗi lấy data ngày $dateStr: $e");
        risks.add(0.0);
      }
    }

    // Tính trung bình
    double avg = (count > 0) ? (totalRisk / count) * 100 : 0.0;

    if (mounted) {
      setState(() {
        _weeklyRisks = risks;
        _dateLabels = labels;
        _averageRisk = avg;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Thống kê & Biểu đồ")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- TIÊU ĐỀ BIỂU ĐỒ CỘT ---
                  const Text(
                    "Tỉ lệ rủi ro bỏ thuốc (7 ngày qua)",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  
                  // --- WIDGET BIỂU ĐỒ CỘT ---
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: AspectRatio(
                        aspectRatio: 1.5,
                        child: _buildBarChart(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // --- TIÊU ĐỀ BIỂU ĐỒ TRÒN ---
                  const Text(
                    "Trung bình mức độ rủi ro",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // --- WIDGET BIỂU ĐỒ TRÒN (ĐÃ CẬP NHẬT) ---
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                      child: Row(
                        children: [
                          // 1. Biểu đồ (Bên trái)
                          Expanded(
                            flex: 4, // Tỉ lệ 4
                            child: SizedBox(
                              height: 180,
                              child: _buildPieChart(),
                            ),
                          ),
                          
                          // Khoảng cách giữa biểu đồ và chữ
                          const SizedBox(width: 24),

                          // 2. Thông tin chi tiết (Bên phải)
                          Expanded(
                            flex: 5, // Tỉ lệ 5 (Rộng hơn để chứa chữ)
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Nguy cơ
                                _legendItem(
                                  Colors.redAccent, 
                                  "Nguy cơ: ${_averageRisk.toStringAsFixed(1)}%"
                                ),
                                const SizedBox(height: 12),
                                
                                // Tuân thủ (100 - nguy cơ)
                                _legendItem(
                                  Colors.green, 
                                  "Tuân thủ: ${(100 - _averageRisk).toStringAsFixed(1)}%"
                                ),
                                
                                const SizedBox(height: 20),
                                Text(
                                  "TB Rủi ro: ${_averageRisk.toStringAsFixed(1)}%",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // Helper vẽ Biểu đồ cột
  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.blueGrey, // Giữ nguyên fix lỗi version cũ
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.round()}%',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                int index = value.toInt();
                if (index >= 0 && index < _dateLabels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _dateLabels[index],
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 20,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()}', style: const TextStyle(fontSize: 10));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        barGroups: _weeklyRisks.asMap().entries.map((entry) {
          int index = entry.key;
          double value = entry.value;
          
          Color barColor = value > 50 ? Colors.redAccent : Colors.green;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: value,
                color: barColor,
                width: 16,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4), 
                  topRight: Radius.circular(4)
                ),
                backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 100, 
                    color: Colors.grey.shade100,
                 )
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // Helper vẽ Biểu đồ tròn
  Widget _buildPieChart() {
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 40,
            sections: [
              // Phần rủi ro
              PieChartSectionData(
                value: _averageRisk,
                title: '${_averageRisk.toStringAsFixed(0)}%',
                color: Colors.redAccent,
                radius: 50,
                titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              // Phần an toàn
              PieChartSectionData(
                value: 100 - _averageRisk,
                title: '',
                color: Colors.green.shade400,
                radius: 40,
              ),
            ],
          ),
        ),
        const Text("TB", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  // Helper vẽ chú thích
  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 8),
        // Flexible giúp text tự xuống dòng nếu quá dài
        Flexible(
          child: Text(
            text, 
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    );
  }
}