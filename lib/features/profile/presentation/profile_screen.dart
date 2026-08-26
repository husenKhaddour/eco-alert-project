import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  // دالة لإضافة موقع مفضل جديد لقاعدة بيانات المستخدم
  Future<void> _addFavoriteLocation(BuildContext context, String uid) async {
    try {
      // 1. فتح شاشة الخريطة التفاعلية لاختيار الموقع
      final LatLng? pickedLocation = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MapLocationPickerScreen()),
      );

      // إذا تراجع المستخدم ولم يختر موقعاً
      if (pickedLocation == null) return;

      if (!context.mounted) return;

      String locationName = '';

      // 2. إظهار نافذة منبثقة لإدخال اسم الموقع بعد اختياره من الخريطة
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('إضافة موقع مفضل 📍'),
          content: TextField(
            decoration: const InputDecoration(hintText: "مثال: المنزل، العمل، مزرعة العائلة"),
            onChanged: (val) => locationName = val,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () async {
                if (locationName.trim().isEmpty) return;
                Navigator.pop(context);
                
                // 3. تحديث قائمة المواقع في Firestore
                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                  'savedLocations': FieldValue.arrayUnion([
                    {
                      'name': locationName.trim(),
                      'latitude': pickedLocation.latitude,
                      'longitude': pickedLocation.longitude,
                    }
                  ])
                });

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ الموقع بنجاح ✅'), backgroundColor: Colors.green)
                  );
                }
              },
              child: const Text('حفظ'),
            )
          ],
        )
      );
    } catch (e) {
      debugPrint("خطأ في تحديد الموقع: $e");
    }
  }

  // واجهة عرض وإدارة المواقع المفضلة
  Widget _buildSavedLocationsSection(Map<String, dynamic> userData, String uid, BuildContext context) {
    List<dynamic> savedLocations = userData['savedLocations'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('المواقع المفضلة للتنبيهات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_location_alt, color: Colors.green),
              onPressed: () => _addFavoriteLocation(context, uid),
              tooltip: 'إضافة موقع جديد من الخريطة',
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (savedLocations.isEmpty)
          const Text('لم تقم بإضافة مواقع مفضلة بعد.', style: TextStyle(color: Colors.grey)),
        
        ...savedLocations.map((loc) => Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 8.0),
          child: ListTile(
            leading: const Icon(Icons.location_city, color: Colors.blue, size: 30),
            title: Text(loc['name'] ?? 'موقع محفوظ', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('إحداثيات: ${loc['latitude'].toStringAsFixed(3)}, ${loc['longitude'].toStringAsFixed(3)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () async {
                // مسح الموقع من القائمة باستخدام arrayRemove
                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                  'savedLocations': FieldValue.arrayRemove([loc])
                });
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف الموقع'), backgroundColor: Colors.red)
                  );
                }
              },
            ),
          ),
        )).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. جلب معرف المستخدم الحالي (ID)
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('يرجى تسجيل الدخول أولاً')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green[700],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      // 2. استخدام StreamBuilder للاستماع لتغيرات بيانات المستخدم لحظياً
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text('لا توجد بيانات لهذا المستخدم'));
          }

          // استخراج البيانات الحقيقية من قاعدة البيانات
          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          final int trustScore = userData['trustScore'] ?? 0;
          final String role = userData['role'] == 'admin' ? 'مدير النظام' : 'مستخدم متطوع';
          final String email = userData['email'] ?? 'مستخدم غير معروف';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.green,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(email, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('الصلاحية: $role', style: const TextStyle(color: Colors.grey)),
                
                const SizedBox(height: 30),
                
                // 3. مؤشر الثقة الحي (Live Trust Score)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('مؤشر الموثوقية (Trust Score)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Icon(Icons.verified_user, color: Colors.blue),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: (trustScore / 100).clamp(0.0, 1.0), 
                          backgroundColor: Colors.grey[300],
                          color: trustScore >= 60 ? Colors.green : (trustScore >= 30 ? Colors.orange : Colors.red),
                          minHeight: 10,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '$trustScore نقطة - ${trustScore >= 60 ? 'حساب موثوق عالٍ' : (trustScore >= 30 ? 'حساب متوسط الثقة' : 'حساب منخفض الثقة')}', 
                          style: TextStyle(color: trustScore >= 60 ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // 4. جلب الإحصائيات الحقيقية للبلاغات الخاصة بهذا المستخدم
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('community_reports')
                      .where('userId', isEqualTo: currentUser.uid)
                      .snapshots(),
                  builder: (context, reportsSnapshot) {
                    int totalReports = 0;
                    int verifiedReports = 0;

                    if (reportsSnapshot.hasData) {
                      totalReports = reportsSnapshot.data!.docs.length;
                      verifiedReports = reportsSnapshot.data!.docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'verified').length;
                    }

                    return Row(
                      children: [
                        Expanded(child: _buildStatCard('إجمالي بلاغاتك', totalReports.toString(), Icons.campaign, Colors.orange)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildStatCard('بلاغات موثقة', verifiedReports.toString(), Icons.check_circle, Colors.green)),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 10),

                // 5. قسم المواقع المفضلة الجديد
                _buildSavedLocationsSection(userData, currentUser.uid, context),

                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 20),

                // 6. الأوسمة (تظهر بناءً على النقاط)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('الأوسمة المجتمعية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (trustScore >= 10) _buildBadgeChip('🥇 متطوع مبادر', Colors.amber),
                    if (trustScore >= 50) _buildBadgeChip('⭐ عضو موثوق', Colors.blue),
                    if (trustScore >= 80) _buildBadgeChip('🛡️ حارس المدينة', Colors.purple),
                    if (trustScore < 10) const Text('شارك في الإبلاغ عن المخاطر لكسب الأوسمة!', style: TextStyle(color: Colors.grey)),
                  ],
                )
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeChip(String label, Color color) {
    return Chip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: color.withOpacity(0.2),
      side: BorderSide(color: color),
    );
  }
}

// ---------------------------------------------------------
// شاشة جديدة: خريطة لاختيار الموقع المفضل بالنقر
// ---------------------------------------------------------
class MapLocationPickerScreen extends StatefulWidget {
  const MapLocationPickerScreen({Key? key}) : super(key: key);

  @override
  State<MapLocationPickerScreen> createState() => _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  LatLng? _selectedLocation;
  final MapController _mapController = MapController();
  bool _isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _moveToCurrentLocation();
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        final currentLatLng = LatLng(position.latitude, position.longitude);
        _mapController.move(currentLatLng, 13.0);
        setState(() {
          _selectedLocation = currentLatLng;
        });
      }
    } catch (e) {
      debugPrint("تعذر الوصول للموقع الحالي: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حدد الموقع على الخريطة'),
        backgroundColor: Colors.green[700],
        actions: [
          if (_selectedLocation != null)
            IconButton(
              icon: const Icon(Icons.check_circle, size: 30, color: Colors.white),
              tooltip: 'تأكيد الموقع',
              onPressed: () {
                // إرجاع الإحداثيات المختارة للصفحة السابقة
                Navigator.pop(context, _selectedLocation);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(34.8, 38.9), // موقع افتراضي (سوريا)
              initialZoom: 6.0,
              onTap: (tapPosition, point) {
                setState(() {
                  _selectedLocation = point; // تحديث النقطة عند نقر المستخدم
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (_selectedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedLocation!,
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.location_pin, color: Colors.red, size: 50),
                    ),
                  ],
                ),
            ],
          ),
          if (_isLoadingLocation)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 15),
                      Text("جاري تحديد موقعك الحالي..."),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        onPressed: _moveToCurrentLocation,
        child: const Icon(Icons.my_location, color: Colors.blue),
      ),
    );
  }
}
