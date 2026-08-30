import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:intl/intl.dart' as intl; 
import 'package:flutter_map/flutter_map.dart'; 
import 'package:latlong2/latlong.dart'; 
import '../../chat/presentation/user_chat_screen.dart'; 

class HazardDetailsScreen extends StatefulWidget {
  final Map<dynamic, dynamic> alert;
  const HazardDetailsScreen({Key? key, required this.alert}) : super(key: key);

  @override
  State<HazardDetailsScreen> createState() => _HazardDetailsScreenState();
}

class _HazardDetailsScreenState extends State<HazardDetailsScreen> {
  
  // دالة لجلب الإرشادات بناءً على نوع الخطر
  List<String> _getSafetyInstructions(String type) {
    if (type.toLowerCase().contains('earthquake') || type == 'زلزال') {
      return [
        'ابتعد عن النوافذ والجدران الخارجية.',
        'انزل على الأرض واختبئ تحت طاولة متينة.',
        'لا تستخدم المصاعد أبداً.'
      ];
    } else if (type == 'حريق') {
      return [
        'ابقَ منخفضاً لتجنب الدخان.',
        'ضع قطعة قماش مبللة على أنفك.',
        'لا تستخدم المصعد، استخدم السلالم.'
      ];
    } else if (type.contains('تلوث') || type == 'تلوث غازي' || type == 'رياح مغبرة') {
      return [
        'ابق في الداخل وأغلق النوافذ والأبواب.',
        'استخدم أجهزة تنقية الهواء إن وجدت.',
        'ارتدِ كمامة مخصصة عند الخروج للضرورة.'
      ];
    } else if (type == 'فيضان') {
      return [
        'انتقل فوراً إلى الأماكن المرتفعة.',
        'تجنب المشي أو القيادة في مياه الفيضانات.',
        'افصل التيار الكهربائي عن المنزل.'
      ];
    } else if (type == 'جائحة مرضية') {
      return [
        'التزم بالتباعد الاجتماعي وتجنب التجمعات.',
        'اغسل يديك باستمرار بالماء والصابون.',
        'اتبع الإرشادات الصادرة عن وزارة الصحة.'
      ];
    } else if (type.contains('جليد') || type == 'عاصفة جليدية') {
      return [
        'تجنب القيادة إلا للضرورة القصوى.',
        'ارتد ملابس دافئة بطبقات متعددة.',
        'تأكد من وجود وسائل تدفئة آمنة وتهوية جيدة.'
      ];
    } else if (type == 'إعصار' || type.contains('رياح') || type.contains('عواصف')) {
      return [
        'ابق في الداخل وابتعد عن النوافذ والأبواب الزجاجية.',
        'قم بتثبيت الأشياء القابلة للتطاير خارج المنزل.',
        'تابع النشرات الجوية باستمرار.'
      ];
    }
    return ['يرجى توخي الحذر والابتعاد عن منطقة الخطر. اتبع تعليمات الجهات الرسمية.'];
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.alert['title'] ?? 'تفاصيل التنبيه';
    final String type = widget.alert['type'] ?? 'غير معروف';
    final String severity = widget.alert['severity'] ?? 'low';
    final String location = widget.alert['location_name'] ?? 'موقع غير معروف';
    final String source = widget.alert['source'] ?? 'غير محدد';
    
    // استخراج ومعالجة التاريخ والوقت
    String timeString = 'غير متوفر';
    if (widget.alert['timestamp'] != null) {
      try {
        DateTime dt;
        if (widget.alert['timestamp'] is Timestamp) {
          dt = (widget.alert['timestamp'] as Timestamp).toDate();
        } else {
          dt = DateTime.parse(widget.alert['timestamp'].toString());
        }
        timeString = intl.DateFormat('yyyy-MM-dd – kk:mm').format(dt);
      } catch (e) {
        timeString = 'تنسيق غير معروف';
      }
    }

    Color severityColor = Colors.green;
    if (severity == 'high') severityColor = Colors.red;
    if (severity == 'medium') severityColor = Colors.orange;

    List<String> instructions = _getSafetyInstructions(type);

    // التحقق من وجود إحداثيات
    final hasCoordinates = widget.alert['coordinates'] != null && 
                           widget.alert['coordinates']['latitude'] != null && 
                           widget.alert['coordinates']['longitude'] != null;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('تفاصيل الخطر', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: severityColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: severityColor, size: 40),
                        const SizedBox(width: 10),
                        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const Divider(height: 30),
                    _buildInfoRow(Icons.category, 'النوع:', type),
                    const SizedBox(height: 10),
                    _buildInfoRow(Icons.access_time, 'الوقت:', timeString),
                    const SizedBox(height: 10),
                    _buildInfoRow(Icons.location_on, 'الموقع:', location),
                    const SizedBox(height: 10),
                    _buildInfoRow(Icons.satellite, 'المصدر:', source),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            const Text('🛡️ إرشادات السلامة:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...instructions.map((inst) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(inst, style: const TextStyle(fontSize: 16))),
                ],
              ),
            )).toList(),

            const SizedBox(height: 30),

            // --- زر عرض الموقع على الخريطة الداخلية ---
            if (hasCoordinates)
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green[800],
                      side: BorderSide(color: Colors.green[800]!, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.map, size: 28),
                    label: const Text('عرض الموقع الدقيق على الخريطة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final lat = widget.alert['coordinates']['latitude'];
                      final lng = widget.alert['coordinates']['longitude'];
                      final hazardTitle = widget.alert['title'] ?? 'موقع الخطر';

                      // فتح الخريطة الداخلية بدلاً من التطبيق الخارجي
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => HazardInternalMapScreen(
                            latitude: lat,
                            longitude: lng,
                            title: hazardTitle,
                            severityColor: severityColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            
            const Divider(),
            const Text('🤖 طلب المساعدة الفورية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 15),
            
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.support_agent, size: 28),
                label: const Text(
                  'التواصل المباشر مع إدارة الطوارئ', 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UserChatScreen()),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'سيتم توجيهك لمحادثة مباشرة مع فريق الإدارة للحصول على الدعم والتوجيه.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
              textAlign: TextAlign.center,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text('$label ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],
    );
  }
}

// ---------------------------------------------------------
// شاشة الخريطة الداخلية لعرض موقع الخطر
// ---------------------------------------------------------
class HazardInternalMapScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String title;
  final Color severityColor;

  const HazardInternalMapScreen({
    Key? key,
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.severityColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final location = LatLng(latitude, longitude);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: severityColor,
        foregroundColor: Colors.white,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: location,
          initialZoom: 14.0, 
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.ecoalert.eco_alert', 
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: location,
                width: 60,
                height: 60,
                child: const Column(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 40),
                    Icon(Icons.location_on, color: Colors.red, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
