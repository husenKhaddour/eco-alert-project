import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import axios from "axios";

// تهيئة تطبيق Firebase Admin
if (!admin.apps.length) {
    admin.initializeApp();
}
const db = admin.firestore();

// دالة حساب المسافة (Haversine formula)
function getDistanceFromLatLonInKm(lat1: number, lon1: number, lat2: number, lon2: number) {
    const R = 6371; 
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a = 
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) * 
        Math.sin(dLon / 2) * Math.sin(dLon / 2); 
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)); 
    return R * c; 
}

// ----------------------------------------------------------------------
// 1. وظيفة جلب البيانات البيئية (بيانات الزلازل من USGS)
// ----------------------------------------------------------------------
export const fetchUSGSEarthquakes = functions.pubsub.schedule("every 60 minutes").onRun(async (context: functions.EventContext) => {
    try {
        const url = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_day.geojson";
        const response = await axios.get(url);
        
        const features = response.data.features;
        if (!features || features.length === 0) return null;

        const batch = db.batch();
        const hazardsRef = db.collection("environmental_hazards");

        for (const feature of features) {
            const hazardId = feature.id; 
            const properties = feature.properties;
            const geometry = feature.geometry;

            let severity = "low";
            if (properties.mag >= 6.0) severity = "high";
            else if (properties.mag >= 5.0) severity = "medium";

            const hazardData = {
                title: `زلزال بقوة ${properties.mag} ريختر`,
                type: "Earthquake",
                severity: severity,
                location_name: properties.place,
                coordinates: { latitude: geometry.coordinates[1], longitude: geometry.coordinates[0] },
                timestamp: admin.firestore.Timestamp.fromMillis(properties.time),
                source: "USGS"
            };

            const docRef = hazardsRef.doc(hazardId);
            batch.set(docRef, hazardData, { merge: true });
        }
        await batch.commit();
        return null;
    } catch (error) {
        console.error("Error fetching USGS:", error);
        return null;
    }
});

// ----------------------------------------------------------------------
// 2. وظيفة جلب بيانات جودة الهواء والتلوث (OpenAQ)
// ----------------------------------------------------------------------
export const fetchOpenAQData = functions.pubsub.schedule("every 2 hours").onRun(async (context: functions.EventContext) => {
    try {
        // جلب المناطق التي تتجاوز فيها نسبة التلوث الحدود الآمنة (مثال: pm2.5 أعلى من 50)
        const url = "https://api.openaq.org/v2/measurements?parameter=pm25&value_from=50&limit=50";
        const response = await axios.get(url);
        
        const results = response.data.results;
        if (!results || results.length === 0) return null;

        const batch = db.batch();
        const hazardsRef = db.collection("environmental_hazards");

        for (const record of results) {
            // توليد معرف فريد يعتمد على الموقع والزمن
            const hazardId = `openaq_${record.locationId}_${new Date(record.date.utc).getTime()}`;
            
            let severity = "medium";
            if (record.value >= 150) severity = "high"; // تلوث خطير جداً

            const hazardData = {
                title: `تلوث هواء شديد (PM2.5: ${record.value})`,
                type: "تلوث غازي",
                severity: severity,
                location_name: record.location,
                coordinates: { latitude: record.coordinates.latitude, longitude: record.coordinates.longitude },
                timestamp: admin.firestore.Timestamp.fromDate(new Date(record.date.utc)),
                source: "OpenAQ"
            };

            batch.set(hazardsRef.doc(hazardId), hazardData, { merge: true });
        }
        await batch.commit();
        console.log("تم جلب بيانات OpenAQ بنجاح.");
        return null;
    } catch (error) {
        console.error("Error fetching OpenAQ:", error);
        return null;
    }
});

// ----------------------------------------------------------------------
// 3. وظيفة جلب تنبيهات الطقس المتطرف (OpenWeatherMap)
// ----------------------------------------------------------------------
export const fetchWeatherAlerts = functions.pubsub.schedule("every 3 hours").onRun(async (context: functions.EventContext) => {
    try {
        // تنويه: استبدل YOUR_OPENWEATHER_API_KEY بالمفتاح الفعلي الخاص بك
        const API_KEY = "YOUR_OPENWEATHER_API_KEY"; 
        const url = `https://api.openweathermap.org/data/2.5/alerts?lat=34.8&lon=38.9&appid=${API_KEY}`;
        const response = await axios.get(url);
        
        const alerts = response.data.alerts;
        if (!alerts || alerts.length === 0) return null;

        const batch = db.batch();
        const hazardsRef = db.collection("environmental_hazards");

        for (const alert of alerts) {
            const hazardId = `weather_${new Date(alert.start * 1000).getTime()}`;
            
            const hazardData = {
                title: alert.event,
                type: "فيضان", // أو أي تصنيف ديناميكي يعتمد على طبيعة التنبيه
                severity: "high",
                location_name: "تنبيه جوي إقليمي",
                coordinates: { latitude: 34.8, longitude: 38.9 }, // الإحداثيات المستخدمة في الطلب
                timestamp: admin.firestore.Timestamp.fromMillis(alert.start * 1000),
                source: "OpenWeatherMap",
                details: alert.description
            };

            batch.set(hazardsRef.doc(hazardId), hazardData, { merge: true });
        }
        await batch.commit();
        console.log("تم جلب بيانات OpenWeatherMap بنجاح.");
        return null;
    } catch (error) {
        console.error("Error fetching Weather Alerts:", error);
        return null;
    }
});

// ----------------------------------------------------------------------
// 4. خوارزمية التوثيق الذكي مع (Trust Score)
// ----------------------------------------------------------------------
export const verifyCommunityReport = functions.firestore
    .document("community_reports/{reportId}")
    .onCreate(async (snap: functions.firestore.QueryDocumentSnapshot, context: functions.EventContext) => {
        const newReport = snap.data();
        if (newReport.status !== 'pending_verification') return null;

        const reporterId = newReport.userId || 'anonymous';
        const reportLat = newReport.coordinates.latitude;
        const reportLng = newReport.coordinates.longitude;

        // جلب جميع البلاغات المشابهة المعلقة
        const similarReports = await db.collection("community_reports")
            .where("type", "==", newReport.type)
            .where("status", "==", "pending_verification")
            .get();

        let relatedDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];

        // التحقق من المسافة لجميع البلاغات
        similarReports.forEach((doc) => {
            const data = doc.data();
            const dist = getDistanceFromLatLonInKm(reportLat, reportLng, data.coordinates.latitude, data.coordinates.longitude);
            if (dist <= 5.0) {
                relatedDocs.push(doc);
            }
        });

        // إذا وصل العدد إلى 3 بلاغات متقاربة
        if (relatedDocs.length >= 3) {
            const batch = db.batch();
            
            // 1. تحديث حالة جميع البلاغات الثلاثة إلى موثقة
            relatedDocs.forEach(doc => {
                batch.update(doc.ref, { status: 'verified' });
            });
            
            // 2. إضافة نقاط للمستخدم الذي أرسل البلاغ الأخير
            if (reporterId !== 'anonymous') {
                batch.update(db.collection("users").doc(reporterId), {
                    trustScore: admin.firestore.FieldValue.increment(10)
                });
            }

            // 3. إنشاء تنبيه بيئي رسمي ليظهر لجميع المستخدمين في التطبيق
            const officialHazardId = `community_verified_${context.params.reportId}`;
            const hazardRef = db.collection("environmental_hazards").doc(officialHazardId);
            batch.set(hazardRef, {
                title: `تنبيه مجتمعي موثق: ${newReport.type}`,
                type: newReport.type,
                severity: newReport.severity,
                location_name: "موقع تم تحديده من قبل المجتمع",
                coordinates: newReport.coordinates,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                source: "بلاغ مجتمعي"
            });
            
            await batch.commit();
            console.log("تم توثيق البلاغات بنجاح وتحويلها إلى تنبيه عام.");
        }
        return null;
    });

// ----------------------------------------------------------------------
// 5. وظيفة إرسال الإشعارات المخصصة جغرافياً (Geofenced Push Notifications)
// ----------------------------------------------------------------------
export const sendHazardNotification = functions.firestore
    .document("environmental_hazards/{hazardId}")
    .onCreate(async (snap: functions.firestore.QueryDocumentSnapshot, context: functions.EventContext) => {
        const newHazard = snap.data();
        
        // تجاهل المخاطر المنخفضة لعدم إزعاج الناس
        if (newHazard.severity === "low") return null;

        const hazardLat = newHazard.coordinates.latitude;
        const hazardLng = newHazard.coordinates.longitude;
        const tokensToSend: string[] = [];

        try {
            // جلب مواقع المستخدمين الحالية من مجموعة users_locations
            const locationsSnapshot = await db.collection("users_locations").get();
            // جلب بيانات المستخدمين لمعرفة المواقع المفضلة المحفوظة savedLocations
            const usersSnapshot = await db.collection("users").get();
            
            // إنشاء قاموس (Map) لبيانات المستخدمين لتسريع البحث
            const usersMap = new Map();
            usersSnapshot.forEach(doc => {
                usersMap.set(doc.id, doc.data());
            });

            locationsSnapshot.forEach(doc => {
                const locData = doc.data();
                const userId = doc.id;
                const fcmToken = locData.fcmToken;
                const userData = usersMap.get(userId);

                if (!fcmToken) return;

                let isNear = false;

                // 1. فحص القرب من الموقع الحالي للمستخدم (GPS)
                if (locData.coordinates && locData.coordinates.latitude) {
                    const dist = getDistanceFromLatLonInKm(
                        hazardLat, hazardLng, 
                        locData.coordinates.latitude, locData.coordinates.longitude
                    );
                    if (dist <= 50.0) isNear = true; // نطاق الخطر 50 كم
                }

                // 2. فحص القرب من المواقع المفضلة المحفوظة (المنزل، العمل..) إذا لم يكن قريباً من موقعه الحالي
                if (!isNear && userData && userData.savedLocations) {
                    for (const savedLoc of userData.savedLocations) {
                        const dist = getDistanceFromLatLonInKm(
                            hazardLat, hazardLng, 
                            savedLoc.latitude, savedLoc.longitude
                        );
                        if (dist <= 50.0) {
                            isNear = true;
                            break;
                        }
                    }
                }

                // إذا كان المستخدم قريباً (حالياً أو عبر المفضلة)، أضف جهاز التوكن الخاص به
                if (isNear) {
                    tokensToSend.push(fcmToken);
                }
            });

            // إرسال الإشعار فقط للأجهزة التي تقع ضمن نطاق الخطر
            if (tokensToSend.length > 0) {
                const payload = {
                    notification: { 
                        title: "⚠️ تنبيه بيئي في منطقتك (Eco Alert)", 
                        body: `${newHazard.title} - اقترب الخطر من موقعك أو أحد مواقعك المفضلة.` 
                    }
                };

                // إرسال رسائل متعددة (Multicast) للأجهزة المحددة
                const response = await admin.messaging().sendMulticast({
                    tokens: tokensToSend,
                    notification: payload.notification
                });
                
                console.log(`تم إرسال الإشعار بنجاح لـ ${response.successCount} مستخدم في نطاق الخطر.`);
            } else {
                console.log("الخطر بعيد عن جميع المستخدمين ومواقعهم المفضلة، لم يتم إرسال إشعارات.");
            }
        } catch (error) {
            console.error("خطأ في توجيه الإشعارات الجغرافية:", error);
        }
        
        return null;
    });
