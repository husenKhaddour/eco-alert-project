import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:geocoding/geocoding.dart'; // تمت إضافة مكتبة تحويل العناوين لإحداثيات

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // 1. متغيرات الخريطة والبحث الجديدة
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final LatLng _syriaCenter = const LatLng(34.8021, 38.9968); // إحداثيات سوريا كمركز افتراضي

  // متغيرات التصفية (Filters)
  String _selectedSeverity = 'الكل'; 
  String _selectedType = 'الكل';     
  bool _showVerifiedOnly = true;     
  
  // المتغيرات الخاصة بفلتر "المواقع المفضلة"
  bool _showNearFavoritesOnly = false; 
  final Distance _distanceCalc = const Distance();

  // دالة البحث والانتقال في الخريطة
  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;
    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        _mapController.move(LatLng(loc.latitude, loc.longitude), 6.0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على البلد. جرب اسماً آخر.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // دالة للتحقق من خلو قائمة المواقع المفضلة
  void _checkFavoritesEmpty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final List<dynamic> locs = doc.data()?['savedLocations'] ?? [];
    
    if (locs.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد مواقع مفضلة محفوظة حالياً. يمكنك إضافتها من ملفك الشخصي.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // دالة لجلب ودمج البيانات من فايربيز مع تطبيق الفلاتر
  Stream<List<Marker>> _getFilteredMarkers() {
    Stream<QuerySnapshot> hazardsStream = FirebaseFirestore.instance.collection('environmental_hazards').snapshots();
    Stream<QuerySnapshot> reportsStream = FirebaseFirestore.instance.collection('community_reports').snapshots();

    return hazardsStream.asyncMap((hazardsSnapshot) async {
      final reportsSnapshot = await reportsStream.first;
      
      List<dynamic> savedLocations = [];
      final user = FirebaseAuth.instance.currentUser;
      if (_showNearFavoritesOnly && user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          savedLocations = userDoc.data()?['savedLocations'] ?? [];
        }
      }

      List<Marker> markers = [];
      List<QueryDocumentSnapshot> allDocs = [];
      
      allDocs.addAll(hazardsSnapshot.docs);
      allDocs.addAll(reportsSnapshot.docs);

      for (var doc in allDocs) {
        final data = doc.data() as Map<String, dynamic>;
        
        final String type = data['type'] ?? '';
        final String severity = data['severity'] ?? 'low';
        final String status = data['status'] ?? 'verified'; 
        final geo = data['coordinates'];

        if (geo == null || geo['latitude'] == null || geo['longitude'] == null) continue;
        
        final double lat = (geo['latitude'] as num).toDouble();
        final double lng = (geo['longitude'] as num).toDouble();

        if (_showVerifiedOnly && status == 'pending_verification') continue;
        if (_selectedSeverity != 'الكل' && severity != _selectedSeverity) continue;
        if (_selectedType != 'الكل' && type != _selectedType && !(type == 'Earthquake' && _selectedType == 'زلزال')) continue;

        if (_showNearFavoritesOnly) {
          if (savedLocations.isEmpty) continue; 
          
          bool isNear = false;
          for (var loc in savedLocations) {
            double locLat = (loc['latitude'] as num).toDouble();
            double locLng = (loc['longitude'] as num).toDouble();
            
            double distInMeters = _distanceCalc.distance(LatLng(lat, lng), LatLng(locLat, locLng));
            if (distInMeters <= 50000) { 
              isNear = true;
              break;
            }
          }
          if (!isNear) continue; 
        }

        Color markerColor = Colors.green;
        IconData markerIcon = Icons.location_on;
        double iconSize = 30.0;

        if (severity == 'high') { markerColor = Colors.red; iconSize = 40.0; }
        else if (severity == 'medium') { markerColor = Colors.orange; iconSize = 35.0; }

        // ربط الأيقونات بفئات الكوارث الجديدة
        if (type == 'حريق') markerIcon = Icons.local_fire_department;
        else if (type == 'زلزال' || type == 'Earthquake') markerIcon = Icons.waves;
        else if (type == 'فيضان') markerIcon = Icons.water_damage;
        else if (type == 'تلوث غازي') markerIcon = Icons.masks;
        else if (type.contains('رياح') || type == 'إعصار' || type == 'غبار') markerIcon = Icons.air;
        else if (type.contains('جليد')) markerIcon = Icons.ac_unit;
        else if (type.contains('عواصف')) markerIcon = Icons.thunderstorm;
        else if (type == 'جائحة مرضية') markerIcon = Icons.coronavirus;

        markers.add(
          Marker(
            point: LatLng(lat, lng),
            width: iconSize,
            height: iconSize,
            child: GestureDetector(
              onTap: () {
                _showMarkerDetails(context, data);
              },
              child: Icon(markerIcon, color: markerColor, size: iconSize),
            ),
          ),
        );
      }
      return markers;
    });
  }

  void _showMarkerDetails(BuildContext context, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نوع الخطر: ${data['type']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('الشدة: ${data['severity']}', style: const TextStyle(fontSize: 16)),
              Text('المصدر: ${data['source'] ?? 'غير معروف'}', style: const TextStyle(fontSize: 16, color: Colors.blue)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خريطة المخاطر الحية 🗺️', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 1. طبقة الخريطة السفلية
          StreamBuilder<List<Marker>>(
            stream: _getFilteredMarkers(),
            builder: (context, snapshot) {
              List<Marker> markers = snapshot.data ?? [];
              
              return FlutterMap(
                mapController: _mapController, // ربط متحكم الخريطة
                options: MapOptions(
                  initialCenter: _syriaCenter, // المركز الافتراضي على سوريا
                  initialZoom: 6.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.eco_alert',
                  ),
                  MarkerLayer(markers: markers),
                ],
              );
            },
          ),

          // 2. شريط البحث العلوي الجديد للبلدان
          Positioned(
            top: 10, left: 15, right: 15,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن بلد (مثال: مصر، تركيا)...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: _searchLocation,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.indigo),
                      onPressed: () => _searchLocation(_searchController.text),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. طبقة شريط التصفية (تم إزاحتها للأسفل لتفادي شريط البحث)
          Positioned(
            top: 80,
            left: 10,
            right: 10,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                children: [
                  FilterChip(
                    label: const Text('قريب من مفضلتي 📍', style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: _showNearFavoritesOnly,
                    selectedColor: Colors.purple[200],
                    onSelected: (bool value) {
                      setState(() => _showNearFavoritesOnly = value);
                      if (value) {
                        _checkFavoritesEmpty(); 
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('موثقة فقط ✅'),
                    selected: _showVerifiedOnly,
                    selectedColor: Colors.green[200],
                    onSelected: (bool value) {
                      setState(() => _showVerifiedOnly = value);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('خطر عالي 🔴'),
                    selected: _selectedSeverity == 'high',
                    selectedColor: Colors.red[200],
                    onSelected: (bool selected) {
                      setState(() => _selectedSeverity = selected ? 'high' : 'الكل');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('متوسط 🟠'),
                    selected: _selectedSeverity == 'medium',
                    selectedColor: Colors.orange[200],
                    onSelected: (bool selected) {
                      setState(() => _selectedSeverity = selected ? 'medium' : 'الكل');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('زلازل 🌊'),
                    selected: _selectedType == 'زلزال',
                    selectedColor: Colors.blue[200],
                    onSelected: (bool selected) {
                      setState(() => _selectedType = selected ? 'زلزال' : 'الكل');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('حرائق 🔥'),
                    selected: _selectedType == 'حريق',
                    selectedColor: Colors.deepOrange[200],
                    onSelected: (bool selected) {
                      setState(() => _selectedType = selected ? 'حريق' : 'الكل');
                    },
                  ),
                  const SizedBox(width: 8),
                  // فلتر جديد للفيضانات
                  ChoiceChip(
                    label: const Text('فيضانات 💧'),
                    selected: _selectedType == 'فيضان',
                    selectedColor: Colors.cyan[200],
                    onSelected: (bool selected) {
                      setState(() => _selectedType = selected ? 'فيضان' : 'الكل');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
