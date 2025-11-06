const admin = require("firebase-admin");
const serviceAccount = require("./pasma-apps-8d37e-firebase-adminsdk-6koxc-8a6c40e83a.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testNotif() {
  const ref = await db.collection("admin_notifications").add({
    title: " Komplain Baru (TEST)",
    body: "Pesanan #TEST-001 dilaporkan buyer.\nAlasan: Barang rusak (test manual)",
    type: "new_dispute",
    orderId: "test_order_123",
    disputeId: "test_dispute_456",
    priority: "high",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    isRead: false,
  });
  console.log(" Test notification created:", ref.id);
  process.exit(0);
}

testNotif().catch(e => {
  console.error(" Error:", e);
  process.exit(1);
});
