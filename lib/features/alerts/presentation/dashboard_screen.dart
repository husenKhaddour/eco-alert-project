import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/hazards_sync_service.dart';
import '../../hazards_map/presentation/map_screen.dart';
import 'hazard_details_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../auth/presentation/login_screen.dart';
import '../../chat/presentation/user_chat_screen.dart';
import 'notifications_screen.dart';

// ============================================================================
// 1. دوال محاكاة السيرفر للتوثيق التلقائي (Demo Mode Fallback)
// ============================================================================
double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0;
  final dLat = (lat2 - lat1) * (pi / 180.0);
  final dLon = (lon2 - lon1) * (pi / 180.0);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * (pi / 180.0)) * cos(lat2 * (pi / 180.0)) *
      sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

Future<void> _simulateCloudFunctionVerification(String reportType, double lat, double lng) async {
  try {
    final db = FirebaseFirestore.instance;

    // جلب البلاغات المعلقة من نفس النوع
    final querySnapshot = await db.collection('community_reports')
        .where('type', isEqualTo: reportType)
        .where('status', isEqualTo: 'pending_verification')
        .get();

    List<DocumentSnapshot> nearbyReports = [];

    // التحقق من المسافة (5 كم)
    for (var doc in querySnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final coords = data['coordinates'];
      if (coords != null) {
        final double rLat = coords['latitude'];
        final double rLng = coords['longitude'];
        final dist = _calculateDistance(lat, lng, rLat, rLng);
        
        if (dist <= 5.0) {
          nearbyReports.add(doc);
        }
      }
    }

    // إذا وصلت البلاغات لـ 3، نقوم بالتوثيق التلقائي
    if (nearbyReports.length >= 3) {
      final batch = db.batch();

      for (var doc in nearbyReports) {
        // إخفاء البلاغات الفردية
        batch.update(doc.reference, {'status': 'merged'});

        // إضافة نقاط ثقة
        final data = doc.data() as Map<String, dynamic>;
        final userId = data['userId'];
        if (userId != null && userId != 'anonymous') {
          final userRef = db.collection('users').doc(userId);
          batch.update(userRef, {'trustScore': FieldValue.increment(10)});
        }
      }

      // إنشاء خطر عام موثق
      final hazardId = 'auto_verified_${DateTime.now().millisecondsSinceEpoch}';
      final hazardRef = db.collection('environmental_hazards').doc(hazardId);
      
      batch.set(hazardRef, {
        'title': 'تنبيه مجتمعي موثق: $reportType',
        'type': reportType,
        'severity': 'medium', 
        'location_name': 'موقع تم تحديده من قبل المجتمع',
        'coordinates': {'latitude': lat, 'longitude': lng},
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'بلاغ مجتمعي',
      });

      await batch.commit();
      debugPrint("نجاح: تم توثيق البلاغات وتحويلها إلى تنبيه عام (محاكاة السيرفر).");
    }
  } catch (e) {
    debugPrint("خطأ في المحاكاة: $e");
  }
}
// ============================================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Box _alertsBox;
  bool _isLoading = false;
  bool _isOffline = false;
  
  String _selectedFilter = 'الكل'; 
  bool _isImageAttached = false; 
  bool _isAdmin = false; 

  @override
  void initState() {
    super.initState();
    _initHiveAndLoadData();
    _checkUserRole();
    _syncUserLocationAndToken(); 
    _listenForGlobalHazards(); // تفعيل مراقب الكوارث للإشعارات داخل التطبيق
  }

  // ============================================================================
  // مراقب الإشعارات الشاملة (In-App Notifications)
  // ============================================================================
  void _listenForGlobalHazards() {
    FirebaseFirestore.instance
        .collection('environmental_hazards')
        .where('timestamp', isGreaterThan: DateTime.now())
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            _showInAppNotification(data['title'] ?? 'خطر جديد', data['location_name'] ?? 'موقع غير محدد');
          }
        }
      }
    });
  }

  void _showInAppNotification(String title, String location) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 20, right: 20),
        backgroundColor: Colors.red[800],
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 30),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('إشعار طوارئ جديد!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  Text('$title في $location', style: const TextStyle(fontSize: 14, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ============================================================================

  Future<void> _syncUserLocationAndToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low); 
        String? token = await FirebaseMessaging.instance.getToken();

        await FirebaseFirestore.instance.collection('users_locations').doc(user.uid).set({
          'fcmToken': token,
          'coordinates': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)); 
      }
    } catch (e) {
      debugPrint("لم يتمكن من تحديث الموقع: $e");
    }
  }

  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        setState(() => _isAdmin = doc.data()?['role'] == 'admin');
      }
    }
  }

  Future<void> _initHiveAndLoadData() async {
    setState(() => _isLoading = true);
    _alertsBox = await Hive.openBox('alerts_cache_box');
    bool hasConnection = await InternetConnectionChecker.createInstance().hasConnection;
    setState(() => _isOffline = !hasConnection);
    if (hasConnection) {
      await _syncFromFirestoreToLocal();
      await _syncOfflineReports(); 
    }
    setState(() => _isLoading = false);
  }

  Future<void> _syncFromFirestoreToLocal() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('environmental_hazards').orderBy('timestamp', descending: true).limit(20).get();
      await _alertsBox.clear();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['timestamp'] is Timestamp) data['timestamp'] = (data['timestamp'] as Timestamp).toDate().toIso8601String();
        await _alertsBox.put(doc.id, data);
      }
    } catch (e) {
      debugPrint("خطأ: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncOfflineReports() async {
    var queueBox = await Hive.openBox('offline_reports_queue');
    if (queueBox.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    for (var i = 0; i < queueBox.length; i++) {
      final report = queueBox.getAt(i) as Map<dynamic, dynamic>;
      final firebaseReport = Map<String, dynamic>.from(report);
      firebaseReport['timestamp'] = FieldValue.serverTimestamp(); 
      final docRef = db.collection('community_reports').doc();
      batch.set(docRef, firebaseReport);
    }

    await batch.commit();
    await queueBox.clear(); 
    debugPrint('تم رفع البلاغات المؤجلة بنجاح.');
  }

  Future<void> _syncOpenData() async {
     setState(() => _isLoading = true);
     await HazardsSyncService().fetchAndSaveEarthquakes();
     await _syncFromFirestoreToLocal();
     setState(() => _isLoading = false);
  }

  Future<void> _submitCommunityReport(String type, String severity) async {
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final currentUser = FirebaseAuth.instance.currentUser;
      
      final reportData = {
        'type': type,
        'severity': severity,
        'coordinates': {'latitude': position.latitude, 'longitude': position.longitude},
        'status': 'pending_verification',
        'source': 'community',
        'userId': currentUser?.uid ?? 'anonymous',
        'hasImage': _isImageAttached,
      };

      if (_isOffline) {
        var queueBox = await Hive.openBox('offline_reports_queue');
        reportData['local_timestamp'] = DateTime.now().toIso8601String(); 
        await queueBox.add(reportData);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('أنت غير متصل بالإنترنت. تم حفظ البلاغ محلياً وسيتم رفعه تلقائياً عند عودة الشبكة 📴'),
              backgroundColor: Colors.orange,
            )
          );
        }
      } else {
        reportData['timestamp'] = FieldValue.serverTimestamp();
        
        await FirebaseFirestore.instance.collection('community_reports').add(reportData);
        await _simulateCloudFunctionVerification(type, position.latitude, position.longitude);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال البلاغ بنجاح! سيتم التحقق منه.'), backgroundColor: Colors.green)
          );
        }
      }
    } catch (e) {
      debugPrint("خطأ في رفع البلاغ: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الإرسال، الخطأ: $e'), 
            backgroundColor: Colors.red, 
            duration: const Duration(seconds: 5)
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showReportDialog() {
    String selectedType = 'حريق';
    String selectedSeverity = 'medium';
    _isImageAttached = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('الإبلاغ عن خطر ⚠️'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'نوع الخطر'),
                    value: selectedType,
                    items: const [
                      DropdownMenuItem(value: 'حريق', child: Text('🔥 حريق')),
                      DropdownMenuItem(value: 'فيضان', child: Text('🌊 فيضان')),
                      DropdownMenuItem(value: 'زلزال', child: Text('🫨 زلزال')),
                      DropdownMenuItem(value: 'تلوث غازي', child: Text('💨 تلوث غازي')),
                      DropdownMenuItem(value: 'رياح شديدة', child: Text('💨 رياح شديدة')),
                      DropdownMenuItem(value: 'عاصفة جليدية', child: Text('❄️ عاصفة جليدية')),
                      DropdownMenuItem(value: 'إعصار', child: Text('🌪️ إعصار')),
                      DropdownMenuItem(value: 'رياح مغبرة', child: Text('🌫️ رياح مغبرة')),
                      DropdownMenuItem(value: 'عواصف رعدية', child: Text('⛈️ عواصف رعدية')),
                      DropdownMenuItem(value: 'جائحة مرضية', child: Text('🦠 جائحة مرضية')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedType = val!),
                  ),
                  DropdownButtonFormField<String>(
                    value: selectedSeverity,
                    items: const [
                      DropdownMenuItem(value: 'high', child: Text('🔴 خطر عالي')),
                      DropdownMenuItem(value: 'medium', child: Text('🟠 خطر متوسط')),
                      DropdownMenuItem(value: 'low', child: Text('🟢 خطر منخفض')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedSeverity = val!),
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton.icon(
                    onPressed: () {
                      setDialogState(() => _isImageAttached = !_isImageAttached);
                    },
                    icon: Icon(_isImageAttached ? Icons.check_circle : Icons.camera_alt, color: _isImageAttached ? Colors.green : Colors.blue),
                    label: Text(_isImageAttached ? 'تم إرفاق الصورة بنجاح' : 'التقاط صورة كدليل (اختياري)'),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: _isImageAttached ? Colors.green : Colors.blue)),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    Navigator.pop(context);
                    _submitCommunityReport(selectedType, selectedSeverity);
                  },
                  child: const Text('إرسال', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Eco Alert', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _isOffline ? Colors.blueGrey : (_isAdmin ? Colors.indigo[800] : Colors.green[700]),
        leading: _isAdmin ? null : IconButton(
          icon: const Icon(Icons.person_pin, color: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen())),
        ),
        actions: [
          if (_isAdmin)
            IconButton(icon: const Icon(Icons.admin_panel_settings, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboardScreen()))),
          
          if (!_isAdmin)
            IconButton(
              icon: const Icon(Icons.support_agent, color: Colors.white),
              tooltip: 'التحدث مع الدعم الفني',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UserChatScreen())),
            ),

          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'تحديث الكوارث', onPressed: _syncOpenData),
          
          if (!_isAdmin)
            IconButton(
              icon: const Icon(Icons.notifications_active, color: Colors.white), 
              tooltip: 'سجل الإشعارات', 
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()))
            ),

          IconButton(icon: const Icon(Icons.map), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const MapScreen()))),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'تسجيل خروج',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
            },
          ),
        ],
      ),
      floatingActionButton: _isAdmin ? null : FloatingActionButton.extended(
        heroTag: 'unique_report_tag', 
        onPressed: _showReportDialog,
        backgroundColor: Colors.orange[800],
        icon: const Icon(Icons.campaign, color: Colors.white),
        label: const Text('إبلاغ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          NetworkStatusBanner(
            isOffline: _isOffline,
            onSyncPressed: () async {
              bool hasConnection = await InternetConnectionChecker.createInstance().hasConnection;
              setState(() => _isOffline = !hasConnection);
              
              if (hasConnection) {
                await _syncFromFirestoreToLocal();
                await _syncOfflineReports(); 
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تمت مزامنة البيانات ورفع البلاغات المؤجلة بنجاح ✅', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('لا يوجد اتصال بالإنترنت حتى الآن ❌', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
                  );
                }
              }
            },
          ),

          if (_isLoading) const LinearProgressIndicator(),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                'الكل', 'سوريا', 'الزلازل', 'الحرائق', 'الفيضانات', 'رياح', 'جليد', 'إعصار', 'غبار', 'عواصف', 'جائحة'
              ].map((filter) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: ChoiceChip(
                    label: Text(filter, style: TextStyle(color: _selectedFilter == filter ? Colors.white : Colors.black87)),
                    selected: _selectedFilter == filter,
                    selectedColor: Colors.green[700],
                    backgroundColor: Colors.grey[200],
                    onSelected: (selected) { if (selected) setState(() => _selectedFilter = filter); },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: Hive.box('alerts_cache_box').listenable(),
              builder: (context, Box box, _) {
                if (box.isEmpty && !_isLoading) return const Center(child: Text('الوضع آمن حالياً ✅', style: TextStyle(fontSize: 18)));
                
                List<Map<dynamic, dynamic>> filteredAlerts = [];
                for (int i = 0; i < box.length; i++) {
                  final alert = box.getAt(i) as Map<dynamic, dynamic>;
                  final type = alert['type'] ?? '';
                  final severity = alert['severity'] ?? '';
                  final location = alert['location_name'] ?? '';

                  bool isSyria = location.contains('سوريا') || location.contains('حلب') || 
                                 location.contains('دمشق') || location.contains('دير الزور') || 
                                 location.contains('الحسكة') || location.contains('الرقة') || 
                                 location.contains('إدلب') || location.contains('اللاذقية') || 
                                 location.contains('حمص') || location.contains('حماة');
                  
                  if (_selectedFilter == 'الكل') filteredAlerts.add(alert);
                  else if (_selectedFilter == 'سوريا' && isSyria) filteredAlerts.add(alert);
                  else if (_selectedFilter == 'الزلازل' && (type == 'Earthquake' || type == 'زلزال')) filteredAlerts.add(alert);
                  else if (_selectedFilter == 'الحرائق' && type == 'حريق') filteredAlerts.add(alert);
                  else if (_selectedFilter == 'الفيضانات' && type == 'فيضان') filteredAlerts.add(alert);
                  else if (_selectedFilter == 'رياح' && type.contains('رياح')) filteredAlerts.add(alert);
                  else if (_selectedFilter == 'جليد' && type.contains('جليد')) filteredAlerts.add(alert);
                  else if (_selectedFilter == 'إعصار' && type == 'إعصار') filteredAlerts.add(alert);
                  else if (_selectedFilter == 'غبار' && type == 'رياح مغبرة') filteredAlerts.add(alert);
                  else if (_selectedFilter == 'عواصف' && type.contains('عواصف')) filteredAlerts.add(alert);
                  else if (_selectedFilter == 'جائحة' && type == 'جائحة مرضية') filteredAlerts.add(alert);
                }

                if (filteredAlerts.isEmpty) return Center(child: Text('لا توجد تنبيهات تطابق الفلتر: $_selectedFilter'));

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredAlerts.length,
                  itemBuilder: (context, index) {
                    final alert = filteredAlerts[index];
                    final String title = alert['title'] ?? 'تنبيه';
                    final String type = alert['type'] ?? '';
                    final String severity = alert['severity'] ?? 'low';
                    final String location = alert['location_name'] ?? 'موقع غير معروف';
                    final String source = alert['source'] ?? 'USGS';
                    
                    Color severityColor = Colors.green;
                    IconData hazardIcon = Icons.info;
                    
                    if (severity == 'high') { severityColor = Colors.red; }
                    else if (severity == 'medium') { severityColor = Colors.orange; }
                    
                    if (type == 'Earthquake' || type == 'زلزال') hazardIcon = Icons.waves;
                    else if (type == 'حريق') hazardIcon = Icons.local_fire_department;
                    else if (type == 'فيضان') hazardIcon = Icons.water_damage;
                    else if (type == 'تلوث غازي') hazardIcon = Icons.masks;
                    else if (type.contains('رياح') || type == 'إعصار' || type == 'غبار') hazardIcon = Icons.air;
                    else if (type.contains('جليد')) hazardIcon = Icons.ac_unit;
                    else if (type.contains('عواصف')) hazardIcon = Icons.thunderstorm;
                    else if (type == 'جائحة مرضية') hazardIcon = Icons.coronavirus;
                    
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(border: Border(right: BorderSide(color: severityColor, width: 6))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: severityColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(hazardIcon, color: severityColor, size: 28),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.grey), const SizedBox(width: 4), Expanded(child: Text(location, style: const TextStyle(color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis))]),
                              const SizedBox(height: 6),
                              Badge(label: Text(source, style: const TextStyle(fontSize: 10)), backgroundColor: source == 'USGS' ? Colors.blue : Colors.purple),
                            ],
                          ),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => HazardDetailsScreen(alert: alert))),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class NetworkStatusBanner extends StatelessWidget {
  final bool isOffline;
  final VoidCallback onSyncPressed;

  const NetworkStatusBanner({
    Key? key,
    required this.isOffline,
    required this.onSyncPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      color: Colors.orange[850],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'أنت تعمل حالياً بدون إنترنت - يتم عرض البيانات المحلية المؤرشفة',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: onSyncPressed,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('مزامنة', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
