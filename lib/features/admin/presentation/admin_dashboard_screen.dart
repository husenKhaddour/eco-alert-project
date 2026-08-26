import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:geocoding/geocoding.dart'; // إضافة مكتبة تحويل الإحداثيات إلى عناوين
import 'admin_chats_screen.dart'; // استدعاء شاشة محادثات الدعم الفني

// تم تحويل الشاشة إلى StatefulWidget لدعم ميزة التحديث
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, 
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('لوحة تحكم الإدارة 🛡️', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo[900], 
          foregroundColor: Colors.white,
          actions: [
            // 👇 إضافة زر التحديث الخاص بالأدمن
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'تحديث الإحصائيات والبيانات',
              onPressed: () {
                // إعادة بناء الشاشة لتحديث جلب البيانات من فايربيز
                setState(() {});
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث بيانات لوحة التحكم بنجاح ✅'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.orange,
            isScrollable: true, 
            tabs: [
              Tab(icon: Icon(Icons.analytics), text: 'نظرة عامة'),
              Tab(icon: Icon(Icons.pending_actions), text: 'البلاغات المعلقة'),
              Tab(icon: Icon(Icons.people), text: 'إدارة المستخدمين'),
              Tab(icon: Icon(Icons.support_agent), text: 'الدعم والمحادثات'), 
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _OverviewTab(),        
            _PendingReportsTab(),  
            _UsersManagementTab(), 
            AdminChatsScreen(),    // ربط شاشة محادثات الأدمن هنا
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📊 الإحصائيات الشاملة للمنصة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // إحصائيات المستخدمين
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              int usersCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return _buildStatCard('إجمالي المتطوعين المسجلين', usersCount.toString(), Icons.people, Colors.blue);
            },
          ),
          const SizedBox(height: 16),

          // جلب كل البلاغات وتحليلها (Data Aggregation)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('community_reports').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs;
              int total = docs.length;
              int verified = 0;
              int pending = 0;
              int rejected = 0;
              
              int fires = 0;
              int earthquakes = 0;
              int pollution = 0;
              int floods = 0;

              for (var doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'];
                final type = data['type'];

                if (status == 'verified') verified++;
                else if (status == 'pending_verification') pending++;
                else if (status == 'rejected') rejected++;

                if (type == 'حريق') fires++;
                else if (type == 'زلزال') earthquakes++;
                else if (type == 'تلوث' || type == 'تلوث غازي') pollution++;
                else if (type == 'فيضان') floods++;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بطاقات الحالة المصغرة
                  Row(
                    children: [
                      Expanded(child: _buildMiniStatCard('موثق', verified.toString(), Colors.green)),
                      Expanded(child: _buildMiniStatCard('معلق', pending.toString(), Colors.orange)),
                      Expanded(child: _buildMiniStatCard('مرفوض', rejected.toString(), Colors.red)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // تحليل أنواع المخاطر
                  const Text('🔥 توزيع أنواع المخاطر (مقارنة)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildProgressBar('الحرائق', fires, total, Colors.redAccent),
                          const SizedBox(height: 12),
                          _buildProgressBar('الزلازل', earthquakes, total, Colors.brown),
                          const SizedBox(height: 12),
                          _buildProgressBar('التلوث الغازي', pollution, total, Colors.grey),
                          const SizedBox(height: 12),
                          _buildProgressBar('الفيضانات', floods, total, Colors.blueAccent),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 30),
        ),
        title: Text(title, style: const TextStyle(fontSize: 16, color: Colors.blueGrey)),
        trailing: Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }

  Widget _buildMiniStatCard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(String label, int count, int total, Color color) {
    double percentage = total == 0 ? 0 : (count / total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('$count بلاغ (${(percentage * 100).toStringAsFixed(1)}%)', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: percentage,
          backgroundColor: Colors.grey[200],
          color: color,
          minHeight: 10,
          borderRadius: BorderRadius.circular(5),
        ),
      ],
    );
  }
}

class _PendingReportsTab extends StatelessWidget {
  const _PendingReportsTab({Key? key}) : super(key: key);

  Future<void> _approveReport(BuildContext context, String docId, Map<String, dynamic> data) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري جلب الموقع الحقيقي وتوثيق البلاغ... ⏳')));
      }

      String actualLocationName = 'موقع محدد من قبل مستخدم';
      final geo = data['coordinates'];

      if (geo != null && geo['latitude'] != null && geo['longitude'] != null) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(geo['latitude'], geo['longitude']);
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks.first;
            actualLocationName = [place.locality, place.subLocality, place.street]
                .where((e) => e != null && e.isNotEmpty)
                .join('، ');
            
            if (actualLocationName.isEmpty) actualLocationName = place.country ?? 'موقع غير معروف';
          }
        } catch (e) {
          debugPrint("خطأ في جلب اسم الموقع باستخدام Geocoding: $e");
        }
      }

      final db = FirebaseFirestore.instance;
      final batch = db.batch(); 

      batch.update(db.collection('community_reports').doc(docId), {'status': 'verified'});

      batch.set(db.collection('environmental_hazards').doc(), {
        'title': 'خطر موثق من الإدارة: ${data['type']}',
        'type': data['type'],
        'severity': data['severity'],
        'location_name': actualLocationName, 
        'coordinates': data['coordinates'],
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'Admin Verified',
      });

      if (data['userId'] != null && data['userId'] != 'anonymous') {
        batch.update(db.collection('users').doc(data['userId']), {
          'trustScore': FieldValue.increment(15) 
        });
      }

      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar(); 
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم توثيق البلاغ ونشره بالموقع الحقيقي بنجاح ✅'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _rejectReport(BuildContext context, String docId, String? userId) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('community_reports').doc(docId).update({'status': 'rejected'});
      
      if (userId != null && userId != 'anonymous') {
        await db.collection('users').doc(userId).update({
          'trustScore': FieldValue.increment(-20) 
        });
      }
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض البلاغ وخصم نقاط من المستخدم ❌')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('community_reports').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('لا توجد بلاغات معلقة حالياً ✅', style: TextStyle(fontSize: 18)));

        final pendingDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == 'pending_verification';
        }).toList();

        pendingDocs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final Timestamp? t1 = dataA['timestamp'] as Timestamp?;
          final Timestamp? t2 = dataB['timestamp'] as Timestamp?;
          if (t1 == null || t2 == null) return 0;
          return t2.compareTo(t1);
        });

        if (pendingDocs.isEmpty) {
          return const Center(child: Text('لا توجد بلاغات معلقة حالياً ✅', style: TextStyle(fontSize: 18)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: pendingDocs.length,
          itemBuilder: (context, index) {
            final doc = pendingDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String type = data['type'] ?? 'غير معروف';
            final String severity = data['severity'] ?? 'low';
            final geo = data['coordinates'] ?? {'latitude': 0.0, 'longitude': 0.0};
            
            String timeString = "وقت غير معروف";
            if (data['timestamp'] != null) {
              DateTime dt = (data['timestamp'] as Timestamp).toDate();
              timeString = intl.DateFormat('yyyy-MM-dd – kk:mm').format(dt);
            }

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.orange, width: 1)),
              child: ExpansionTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
                title: Text('بلاغ: $type', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('الشدة: $severity\nالوقت: $timeString'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('👤 المُبلغ (UID): ${data['userId'] ?? 'غير معروف'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Divider(),
                        Text('📍 الموقع: خط عرض ${geo['latitude']}, خط طول ${geo['longitude']}'),
                        Text('🕒 التوقيت: $timeString'),
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              label: const Text('رفض كاذب', style: TextStyle(color: Colors.red)),
                              onPressed: () => _rejectReport(context, doc.id, data['userId']),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              icon: const Icon(Icons.check_circle),
                              label: const Text('توثيق ونشر'),
                              onPressed: () => _approveReport(context, doc.id, data),
                            ),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _UsersManagementTab extends StatelessWidget {
  const _UsersManagementTab({Key? key}) : super(key: key);

  Future<void> _resetUserTrustScore(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({'trustScore': 0});
  }

  Future<void> _banUser(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'role': 'banned',
      'trustScore': -100, 
    });
  }

  Future<void> _deleteUser(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').orderBy('trustScore', descending: false).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('لا يوجد مستخدمين بعد.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String email = data['email'] ?? 'مستخدم مجهول';
            final String name = data['name'] ?? email.split('@').first;
            final String? avatarUrl = data['avatarUrl'];
            final int trustScore = data['trustScore'] ?? 0;
            final String role = data['role'] ?? 'user';

            Color scoreColor = Colors.green;
            if (role == 'banned') scoreColor = Colors.black;
            else if (trustScore < 30) scoreColor = Colors.red;
            else if (trustScore < 60) scoreColor = Colors.orange;

            return Card(
              elevation: 2,
              color: role == 'banned' ? Colors.grey[300] : Colors.white,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: role == 'admin' ? Colors.indigo : scoreColor, 
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null ? Icon(
                    role == 'admin' ? Icons.admin_panel_settings : 
                    role == 'banned' ? Icons.block : Icons.person, 
                    color: Colors.white
                  ) : null,
                ),
                title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, decoration: role == 'banned' ? TextDecoration.lineThrough : null)),
                subtitle: Text('$email\nمؤشر الموثوقية: $trustScore | الصلاحية: $role', style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold)),
                isThreeLine: true,
                
                trailing: role == 'admin' ? const Text('مسؤول', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)) : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'reset') {
                      _resetUserTrustScore(doc.id);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصفير نقاط المستخدم بنجاح.')));
                    } else if (value == 'ban') {
                      _banUser(doc.id);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حظر المستخدم!')));
                    } else if (value == 'delete') {
                      _deleteUser(doc.id);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف بيانات المستخدم نهائياً!')));
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(value: 'reset', child: Row(children: [Icon(Icons.refresh, color: Colors.orange), SizedBox(width: 8), Text('تصفير النقاط')])),
                    const PopupMenuItem<String>(value: 'ban', child: Row(children: [Icon(Icons.block, color: Colors.red), SizedBox(width: 8), Text('حظر المستخدم')])),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_forever, color: Colors.black), SizedBox(width: 8), Text('حذف نهائي', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))])),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
