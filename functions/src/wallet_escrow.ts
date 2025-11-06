import * as admin from "firebase-admin";
import * as functionsV1 from "firebase-functions/v1";
import { UserRecord } from "firebase-admin/auth";
import { Transaction } from "firebase-admin/firestore";
// v2 (https callable)
import {
  onCall,
  HttpsError,
  FunctionsErrorCode,
  CallableRequest,
} from "firebase-functions/v2/https";
// v2 secrets
import { defineSecret } from "firebase-functions/params";

if (!admin.apps.length) admin.initializeApp();

const db = admin.firestore();
const NOW = admin.firestore.FieldValue.serverTimestamp();
const REGION = "asia-southeast2";
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const TWO_DAYS_MS = 2 * ONE_DAY_MS;
const TWELVE_HOURS_MS = 12 * 60 * 60 * 1000;

// ======================= FEES & ADMIN SECRET =======================
// Pastikan konsisten dengan lib/common/fees.dart di client
const SERVICE_FEE = 2000;       // biaya layanan flat
const TAX_RATE = 0.01;          // 1%
const taxOn = (base: number) => Math.round(base * TAX_RATE);

// Secret ADMIN_UID (UID user admin yang menampung fee & pajak)
const ADMIN_UID_SECRET = defineSecret("ADMIN_UID");

// Fallback agar emulator/dev tetap bisa jalan kalau secret belum diset.
function resolveAdminUid(): string {
  return (
    ADMIN_UID_SECRET.value() ||                      // Secret V2 (prod)
    process.env.ADMIN_UID ||                         // ENV (emulator/CI)
    ""                                               // Return empty string kalau belum set (tapi ga crash!)
  );
}

// ============================ helpers ==============================
const asInt = (v: unknown, def = 0) =>
  typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : def;

const httpsError = (code: FunctionsErrorCode, message: string) =>
  new HttpsError(code, message);

type CancelBy = "SELLER" | "BUYER" | "SYSTEM";

// ---------- (NEW) invoice helpers ----------
// INV-YYYYMMDD-XXXXXX (X = A..Z / 2..9 tanpa karakter yang mirip)
function generateInvoiceId(): string {
  const now = new Date();
  const yyyy = now.getFullYear().toString();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let rand = "";
  for (let i = 0; i < 6; i++) {
    rand += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  return `INV-${yyyy}${mm}${dd}-${rand}`;
}

// pastikan unik di koleksi orders (3x percobaan, lalu fallback timestamp)
async function generateUniqueInvoiceId(): Promise<string> {
  for (let i = 0; i < 3; i++) {
    const candidate = generateInvoiceId();
    const snap = await db
      .collection("orders")
      .where("invoiceId", "==", candidate)
      .limit(1)
      .get();
    if (snap.empty) return candidate;
  }
  return `INV-${Date.now()}`;
}

/** Reusable core to cancel + refund an order safely (idempotent). */
async function cancelOrderCore(
  orderId: string,
  opts: { reason: string; by: CancelBy }
) {
  const orderRef = db.collection("orders").doc(orderId);

  await db.runTransaction(async (t) => {
    const orderSnap = await t.get(orderRef);
    if (!orderSnap.exists) return; // idempotent

    const order = orderSnap.data()!;
    const status = String(order.status || "PLACED").toUpperCase();
    const payStatus = String(order.payment?.status || "");

    // IZINKAN cancel pada PLACED/ACCEPTED/SHIPPED/DISPUTED selama dana ESCROWED
    // (dispute bisa terjadi saat SHIPPED atau sudah DISPUTED)
    if (!["PLACED", "ACCEPTED", "SHIPPED", "DISPUTED"].includes(status) || payStatus !== "ESCROWED")
      return;

    const total = asInt(order.amounts?.total);
    if (total <= 0) return;

    const buyerId: string = String(order.buyerId || "");
    const buyerRef = db.collection("users").doc(buyerId);
    const buyerSnap = await t.get(buyerRef);
    const bWallet = buyerSnap.get("wallet") ?? { available: 0, onHold: 0 };

    // 1) release hold -> back to buyer.available
    t.update(buyerRef, {
      "wallet.onHold": Math.max(0, asInt(bWallet.onHold) - total),
      "wallet.available":
        asInt(buyerSnap.get("wallet")?.available ?? 0) + total,
      "wallet.updatedAt": NOW,
    });

    // 2) return stock if it was deducted
    if (order.stockDeducted) {
      const items: any[] = order.items || [];
      for (const it of items) {
        const ref = db.collection("products").doc(String(it.productId));
        const qty = asInt(it.qty);
        t.update(ref, { stock: admin.firestore.FieldValue.increment(qty) });
      }
    }

    // 3) update order
    t.update(orderRef, {
      status: "CANCELED",
      "payment.status": "REFUNDED",
      "shippingAddress.status": "CANCELED",
      cancel: {
        at: NOW,
        reason: opts.reason || null,
        by: opts.by,
      },
      updatedAt: NOW,
      ...(order.stockDeducted ? { stockDeducted: false } : {}),
      autoCancelAt: admin.firestore.FieldValue.delete(),
      shipByAt: admin.firestore.FieldValue.delete(),
    });

    // 4) buyer refund transaction
    const buyerTxRef = buyerRef.collection("transactions").doc();
    t.set(buyerTxRef, {
      type: "REFUND",
      direction: "IN",
      amount: total,
      status: "SUCCESS",
      orderId,
      title: "Pengembalian",
      createdAt: NOW,
    });

    // 5) Notify buyer: order canceled
    const invoiceId = String(order.invoiceId || orderId);
    const formattedAmount = new Intl.NumberFormat("id-ID", {
      style: "currency",
      currency: "IDR",
      minimumFractionDigits: 0,
    }).format(total);

    let cancelTitle = "❌ Pesanan Dibatalkan";
    let cancelBody = `Pesanan #${invoiceId} telah dibatalkan.\nDana sebesar ${formattedAmount} telah dikembalikan ke dompet Anda.`;

    if (opts.by === "SELLER") {
      cancelTitle = "❌ Pesanan Ditolak Penjual";
      cancelBody = `Pesanan #${invoiceId} ditolak oleh penjual.\nAlasan: ${opts.reason || "Tidak disebutkan"}.\nDana sebesar ${formattedAmount} telah dikembalikan ke dompet Anda.`;
    } else if (opts.by === "BUYER") {
      cancelTitle = "✅ Pesanan Berhasil Dibatalkan";
      cancelBody = `Pesanan #${invoiceId} telah dibatalkan.\nDana sebesar ${formattedAmount} telah dikembalikan ke dompet Anda.`;
    }

    const buyerNotifRef = buyerRef.collection("notifications").doc();
    t.set(buyerNotifRef, {
      title: cancelTitle,
      body: cancelBody,
      type: "order_canceled",
      orderId,
      invoiceId,
      timestamp: NOW,
      createdAt: NOW,
      isRead: false,
    });
  });
}

// ===================== 1) init wallet on signup ====================
export const initWalletOnSignup = functionsV1
  .region(REGION)
  .auth.user()
  .onCreate(async (user: UserRecord) => {
    const ref = db.collection("users").doc(user.uid);
    await ref.set(
      {
        wallet: {
          available: 0,
          onHold: 0,
          currency: "IDR",
          updatedAt: NOW,
        },
      },
      { merge: true }
    );
  });

// ========== 2) placeOrder: hold saldo buyer + buat order ===========
/**
 * Callable: placeOrder
 * data:
 *  - sellerId: string
 *  - storeId: string
 *  - storeName: string
 *  - items: Array<{ productId,name,imageUrl,price,qty,variant? }>
 *  - amounts: { subtotal, shipping, serviceFee, tax, total }
 *  - shippingAddress: { label, address | addressText, phone }   // << phone ditambahkan
 *  - idempotencyKey?: string
 */
export const placeOrder = onCall(
  { region: REGION, secrets: [ADMIN_UID_SECRET] }, // (bind secret, walau tidak dipakai di sini)
  async (req: CallableRequest<any>) => {
    const buyerId = req.auth?.uid;
    if (!buyerId) throw httpsError("unauthenticated", "Login diperlukan.");

    const {
      sellerId,
      storeId,
      storeName,
      items,
      amounts,
      shippingAddress,
      idempotencyKey,
    } = (req.data ?? {}) as Record<string, unknown>;

    const clientSubtotal = asInt((amounts as any)?.subtotal);
    const clientShipping = asInt((amounts as any)?.shipping);
    // NOTE: kita sengaja tidak memakai nilai serviceFee/tax/total dari client
    // agar aman dari manipulasi → dihitung ulang di server.

    if (
      !sellerId ||
      !storeId ||
      !storeName ||
      !Array.isArray(items) ||
      clientSubtotal <= 0
    ) {
      throw httpsError("invalid-argument", "Payload tidak lengkap/valid.");
    }

    // Idempotency
    if (idempotencyKey) {
      const dup = await db
        .collection("orders")
        .where("buyerId", "==", buyerId)
        .where("idempotencyKey", "==", idempotencyKey)
        .limit(1)
        .get();
      if (!dup.empty) {
        const d = dup.docs[0].data();
        return {
          ok: true,
          orderId: dup.docs[0].id,
          idempotent: true,
          invoiceId: d.invoiceId ?? null,
        };
      }
    }

    // Recompute di server (anti manipulasi)
    const serviceFee = SERVICE_FEE;
    const tax = taxOn(clientSubtotal);
    const expectedTotal = clientSubtotal + clientShipping + serviceFee + tax;

    // Pakai nilai server sebagai sumber kebenaran
    const total = expectedTotal;

    const buyerRef = db.collection("users").doc(buyerId);
    const orderRef = db.collection("orders").doc();
    const buyerTxRef = buyerRef.collection("transactions").doc();

    const autoCancelAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + ONE_DAY_MS
    );
    const invoiceId = await generateUniqueInvoiceId();

    // --- Normalisasi shippingAddress dari payload (termasuk phone) ---
    const sa: any = (shippingAddress as any) ?? {};
    const saLabel: string = sa.label ?? "-";
    // Simpan keduanya untuk kompatibilitas UI lama/baru
    const saAddressText: string = sa.addressText ?? sa.address ?? "-";
    const saAddressLegacy: string = sa.address ?? sa.addressText ?? "-";
    const saPhone: string = sa.phone ? String(sa.phone) : "";

    await db.runTransaction(async (t: Transaction) => {
      const buyerSnap = await t.get(buyerRef);
      const wallet = buyerSnap.get("wallet") ?? { available: 0, onHold: 0 };

      const available = asInt(wallet.available);
      if (available < total) {
        throw httpsError("failed-precondition", "Saldo tidak cukup.");
      }

      // 1) hold saldo buyer
      t.update(buyerRef, {
        "wallet.available": available - total,
        "wallet.onHold": asInt(wallet.onHold) + total,
        "wallet.updatedAt": NOW,
      });

      // 2) buat order dengan amounts lengkap
      t.set(orderRef, {
        buyerId,
        sellerId,
        storeId,
        storeName,
        items,
        amounts: {
          subtotal: clientSubtotal,
          shipping: clientShipping,
          serviceFee, // NEW
          tax,        // NEW
          total,      // NEW
        },
        payment: {
          method: "abc_payment",
          status: "ESCROWED",
        },
        status: "PLACED",
        shippingAddress: {
          label: saLabel,
          address: saAddressLegacy,   // kompat backend/versi lama
          addressText: saAddressText, // dipakai UI baru
          phone: saPhone,             // <<< SIMPAN NOMOR HP DI SINI
          status: "PLACED",
        },
        createdAt: NOW,
        updatedAt: NOW,
        autoCancelAt, // deadline auto-cancel 24 jam
        idempotencyKey: (idempotencyKey as string) ?? null,
        invoiceId,
      });

      // 3) catat transaksi buyer (ESCROWED)
      t.set(buyerTxRef, {
        type: "PAYMENT",
        direction: "OUT",
        amount: total,
        status: "ESCROWED",
        orderId: orderRef.id,
        counterpartyUid: sellerId,
        title: "Pembayaran (ditahan)",
        createdAt: NOW,
        idempotencyKey: (idempotencyKey as string) ?? null,
      });
    });

    return { ok: true, orderId: orderRef.id, invoiceId };
  }
);

// ====== 3) completeOrder: lepas hold & split ke seller/admin ======
/**
 * Callable: completeOrder
 * data: { orderId: string, completedBy?: 'buyer' | 'auto' }
 * Hanya buyer pemilik order yang boleh menyelesaikan (atau system via auto-complete).
 */
export const completeOrder = onCall(
  { region: REGION, secrets: [ADMIN_UID_SECRET] }, // butuh secret
  async (req: CallableRequest<any>) => {
    const buyerId = req.auth?.uid;
    const orderId: string | undefined = req.data?.orderId;
    const completedBy: string = req.data?.completedBy ?? "buyer"; // 'buyer' atau 'auto'
    
    if (!orderId) throw httpsError("invalid-argument", "orderId wajib.");

    // Jika completedBy = 'auto', skip auth check (dipanggil dari scheduled function)
    // Jika completedBy = 'buyer', wajib login
    if (completedBy === "buyer" && !buyerId) {
      throw httpsError("unauthenticated", "Login diperlukan.");
    }

    const ADMIN_UID = resolveAdminUid();
    if (!ADMIN_UID) {
      throw httpsError(
        "failed-precondition",
        "ADMIN_UID belum dikonfigurasi sebagai Secret/ENV."
      );
    }

    const orderRef = db.collection("orders").doc(orderId);

    await db.runTransaction(async (t: Transaction) => {
      const orderSnap = await t.get(orderRef);
      if (!orderSnap.exists)
        throw httpsError("not-found", "Order tidak ditemukan.");

      const order = orderSnap.data()!;
      
      // Validasi buyer ownership (skip jika auto-complete)
      if (completedBy === "buyer" && order.buyerId !== buyerId) {
        throw httpsError("permission-denied", "Bukan pemilik pesanan.");
      }
      
      if ((order.payment?.status ?? "") !== "ESCROWED")
        throw httpsError(
          "failed-precondition",
          "Pembayaran tidak berstatus ESCROWED."
        );

      const subtotal = asInt(order.amounts?.subtotal);
      const shipping = asInt(order.amounts?.shipping);
      const service = asInt(order.amounts?.serviceFee);
      const tax = asInt(order.amounts?.tax);
      const total = asInt(order.amounts?.total);

      const sellerId = String(order.sellerId ?? "");
      if (!sellerId || total <= 0)
        throw httpsError("internal", "Data order tidak valid.");

      // Hitung pembagian
      const sellerTake = subtotal + shipping;
      let adminTake = service + tax;

      // Antisipasi mismatch pembulatan/versi lama
      const remainder = total - sellerTake - adminTake;
      if (remainder > 0) adminTake += remainder;

      const buyerRef = db.collection("users").doc(buyerId);
      const sellerRef = db.collection("users").doc(sellerId);
      const adminRef = db.collection("users").doc(ADMIN_UID);

      const buyerTxRef = buyerRef.collection("transactions").doc();
      const sellerTxRef = sellerRef.collection("transactions").doc();
      const adminTxRef = adminRef.collection("transactions").doc();

      const buyerSnap = await t.get(buyerRef);
      const sellerSnap = await t.get(sellerRef);
      const adminSnap = await t.get(adminRef);

      const bWallet = buyerSnap.get("wallet") ?? { available: 0, onHold: 0 };
      const sWallet = sellerSnap.get("wallet") ?? { available: 0, onHold: 0 };
      const aWallet = adminSnap.get("wallet") ?? { available: 0, onHold: 0 };

      // 1) lepas hold buyer
      t.update(buyerRef, {
        "wallet.onHold": Math.max(0, asInt(bWallet.onHold) - total),
        "wallet.updatedAt": NOW,
      });

      // 2) kredit seller (subtotal + shipping)
      t.update(sellerRef, {
        "wallet.available": asInt(sWallet.available) + sellerTake,
        "wallet.updatedAt": NOW,
      });

      // 3) kredit admin (service + tax + remainder kalau ada)
      if (adminTake > 0) {
        t.set(
          adminRef,
          {
            wallet: {
              available: asInt(aWallet.available) + adminTake,
              onHold: asInt(aWallet.onHold) || 0,
              currency: aWallet.currency || "IDR",
              updatedAt: NOW,
            },
          },
          { merge: true }
        );
      }

      // 4) metrik produk & toko
      const items: any[] = order.items || [];
      for (const it of items) {
        const ref = db.collection("products").doc(String(it.productId));
        const qty = asInt(it.qty);
        t.update(ref, { sold: admin.firestore.FieldValue.increment(qty) });
      }

      const storeIdStr = String(order.storeId || "");
      if (storeIdStr) {
        const totalQty = items.reduce((sum, it) => sum + asInt(it.qty), 0);
        const storeRef = db.collection("stores").doc(storeIdStr);
        t.update(storeRef, {
          totalSales: admin.firestore.FieldValue.increment(totalQty),
          lastSaleAt: NOW,
        });
      }

      // 5) update order + settlement breakdown + completedBy tracking
      t.update(orderRef, {
        status: "COMPLETED",
        "payment.status": "SETTLED",
        "shippingAddress.status": "COMPLETED",
        updatedAt: NOW,
        completedAt: NOW,
        completedBy, // 'buyer' atau 'auto'
        settlement: {
          sellerTake,
          adminTake,
          settledAt: NOW,
        },
        autoCancelAt: admin.firestore.FieldValue.delete(),
        shipByAt: admin.firestore.FieldValue.delete(),
        autoCompleteAt: admin.firestore.FieldValue.delete(),
        reminderSentAt: admin.firestore.FieldValue.delete(),
      });

      // 6) transaksi ringkas
      t.set(buyerTxRef, {
        type: "PAYMENT",
        direction: "OUT",
        amount: total,
        status: "SUCCESS",
        orderId,
        counterpartyUid: sellerId,
        title: "Pembayaran (Selesai)",
        createdAt: NOW,
      });

      t.set(sellerTxRef, {
        type: "SETTLEMENT",
        direction: "IN",
        amount: sellerTake,
        status: "SUCCESS",
        orderId,
        counterpartyUid: buyerId,
        title: "Pencairan",
        createdAt: NOW,
      });

      if (adminTake > 0) {
        t.set(adminTxRef, {
          type: "FEE",
          direction: "IN",
          amount: adminTake,
          status: "SUCCESS",
          orderId,
          counterpartyUid: buyerId,
          title: "Biaya Layanan & Pajak",
          createdAt: NOW,
        });
      }
    });

    return { ok: true };
  }
);

// ========== 4) cancelOrder: refund hold ke buyer ==========
/**
 * Callable: cancelOrder
 * data: { orderId: string, reason?: string }
 */
export const cancelOrder = onCall(
  { region: REGION, secrets: [ADMIN_UID_SECRET] },
  async (req: CallableRequest<any>) => {
    const uid = req.auth?.uid;
    if (!uid) throw httpsError("unauthenticated", "Login diperlukan.");
    const orderId: string | undefined = req.data?.orderId;
    const reason: string = req.data?.reason ?? "";
    if (!orderId) throw httpsError("invalid-argument", "orderId wajib.");

    const snap = await db.collection("orders").doc(orderId).get();
    if (!snap.exists) throw httpsError("not-found", "Order tidak ditemukan.");

    const buyerId: string = snap.get("buyerId") ?? "";
    const sellerId: string = snap.get("sellerId") ?? "";
    if (![buyerId, sellerId].includes(uid)) {
      throw httpsError(
        "permission-denied",
        "Tidak berhak membatalkan pesanan ini."
      );
    }

    await cancelOrderCore(orderId, {
      reason,
      by: uid === sellerId ? "SELLER" : "BUYER",
    });

    return { ok: true };
  }
);

// --- 5) acceptOrder (potong stok + ubah status ke ACCEPTED)
export const acceptOrder = onCall(
  { region: REGION, secrets: [ADMIN_UID_SECRET] },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw httpsError("unauthenticated", "Login diperlukan.");
    const orderId: string | undefined = req.data?.orderId;
    if (!orderId) throw httpsError("invalid-argument", "orderId wajib.");

    const orderRef = db.collection("orders").doc(orderId);

    await db.runTransaction(async (t) => {
      const snap = await t.get(orderRef);
      if (!snap.exists) throw httpsError("not-found", "Order tidak ditemukan.");

      const order = snap.data()!;
      const status: string = (order.status || "PLACED").toUpperCase();

      if (status !== "PLACED") {
        // idempotent
        if (
          ["ACCEPTED", "SHIPPED", "DELIVERED", "COMPLETED", "SUCCESS"].includes(
            status
          )
        )
          return;
        throw httpsError(
          "failed-precondition",
          `Tidak bisa diterima pada status ${status}.`
        );
      }

      // only owner seller
      if (String(order.sellerId || "") !== uid) {
        throw httpsError("permission-denied", "Bukan seller pemilik pesanan.");
      }

      const items: any[] = order.items || [];
      if (!items.length) throw httpsError("failed-precondition", "Item kosong.");

      // check stock
      const prodRefs = items.map((it) =>
        db.collection("products").doc(String(it.productId))
      );
      const prodSnaps = await Promise.all(prodRefs.map((r) => t.get(r)));

      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        const prod = prodSnaps[i];
        if (!prod.exists)
          throw httpsError("failed-precondition", "Produk tidak ditemukan.");
        const data = prod.data()!;
        const stock = asInt(data.stock);
        const qty = asInt(it.qty);
        if (qty <= 0) throw httpsError("failed-precondition", "Qty tidak valid.");
        if (stock < qty) {
          throw httpsError(
            "failed-precondition",
            `Stok ${data.name || it.productId} tidak cukup (tersisa ${stock}).`
          );
        }
      }

      // deduct stock
      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        const qty = asInt(it.qty);
        t.update(prodRefs[i], {
          stock: admin.firestore.FieldValue.increment(-qty),
        });
      }

      // set deadline kirim 2 hari dari sekarang
      const shipByAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + TWO_DAYS_MS
      );

      // update order
      t.update(orderRef, {
        status: "ACCEPTED",
        stockDeducted: true,
        updatedAt: NOW,
        autoCancelAt: admin.firestore.FieldValue.delete(),
        shipByAt,
        "shippingAddress.status": "ACCEPTED",
      });
    });

    return { ok: true };
  }
);

// --- 6) Scheduler: auto-cancel after 24h if still PLACED
export const autoCancelUnacceptedOrders = functionsV1
  .region(REGION)
  .pubsub.schedule("every 15 minutes")
  .timeZone("Asia/Jakarta")
  .onRun(async () => {
    const nowTs = admin.firestore.Timestamp.now();

    const q = db
      .collection("orders")
      .where("status", "==", "PLACED")
      .where("autoCancelAt", "<=", nowTs)
      .limit(300);

    let processed = 0;
    while (true) {
      const snap = await q.get();
      if (snap.empty) break;

      for (const doc of snap.docs) {
        try {
          await cancelOrderCore(doc.id, {
            reason: "Timeout: seller did not accept within 24h",
            by: "SYSTEM",
          });
          processed++;
        } catch (e) {
          console.error("auto-cancel (PLACED) failed for", doc.id, e);
        }
      }

      if (snap.size < 300) break;
    }

    console.log(`autoCancel (PLACED) processed: ${processed}`);
    return null;
  });

// --- 7) Scheduler: auto-cancel after 48h if ACCEPTED not SHIPPED
export const autoCancelUnshippedOrders = functionsV1
  .region(REGION)
  .pubsub.schedule("every 15 minutes")
  .timeZone("Asia/Jakarta")
  .onRun(async () => {
    const nowTs = admin.firestore.Timestamp.now();

    const q = db
      .collection("orders")
      .where("status", "==", "ACCEPTED")
      .where("shipByAt", "<=", nowTs)
      .limit(300);

    let processed = 0;
    while (true) {
      const snap = await q.get();
      if (snap.empty) break;

      for (const doc of snap.docs) {
        try {
          await cancelOrderCore(doc.id, {
            reason: "Timeout: seller did not ship within 48h",
            by: "SYSTEM",
          });
          processed++;
        } catch (e) {
          console.error("auto-cancel (ACCEPTED) failed for", doc.id, e);
        }
      }

      if (snap.size < 300) break;
    }

    console.log(`autoCancel (ACCEPTED/unshipped) processed: ${processed}`);
    return null;
  });

// --- 8) Scheduler: auto-complete + reminder after SHIPPED
// Timeline: 48 jam (2 hari) reminder → 60 jam (2.5 hari) auto-complete
export const autoCompleteShippedOrders = functionsV1
  .region(REGION)
  .pubsub.schedule("every 1 hours") // PRODUCTION: check every 1 hour
  .timeZone("Asia/Jakarta")
  .onRun(async () => {
    const nowTs = admin.firestore.Timestamp.now();
    const now = Date.now();

    // 1) REMINDER: kirim notif tepat di 48 jam (mulai grace period)
    //    Cari order dengan gracePeriodStartAt <= NOW dan belum kirim reminder
    //    NOTE: Membutuhkan Firestore index (status, gracePeriodStartAt, reminderSentAt)
    try {
      const reminderQuery = db
        .collection("orders")
        .where("status", "==", "SHIPPED")
        .where("gracePeriodStartAt", "<=", nowTs)
        .where("reminderSentAt", "==", null)
        .limit(100);

      const reminderSnap = await reminderQuery.get();
      for (const doc of reminderSnap.docs) {
        try {
          const data = doc.data();
          const buyerId = String(data.buyerId || "");
          const invoiceId = String(data.invoiceId || doc.id);
          const autoCompleteAt = data.autoCompleteAt?.toDate();

          if (!buyerId || !autoCompleteAt) continue;

          const hoursLeft = Math.round(
            (autoCompleteAt.getTime() - now) / (60 * 60 * 1000)
          );

          // Kirim in-app notification (grace period dimulai!)
          await db
            .collection("users")
            .doc(buyerId)
            .collection("notifications")
            .add({
              title: "⏰ Konfirmasi Penerimaan atau Laporkan Masalah",
              body:
                `Pesanan #${invoiceId} sudah 2 hari sejak dikirim.\n\n` +
                `Sudah terima barang? Konfirmasi sekarang atau laporkan jika ada masalah. ` +
                `Transaksi akan selesai otomatis dalam ${hoursLeft} jam.`,
              type: "order_grace_period",
              orderId: doc.id,
              priority: "high",
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              isRead: false,
            });

          // Mark reminder sent
          await doc.ref.update({
            reminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
          });

          console.log(
            `Grace period reminder sent for order ${doc.id}, ${hoursLeft}h left before auto-complete`
          );
        } catch (e) {
          console.error("Failed to send grace period reminder for", doc.id, e);
        }
      }
    } catch (indexErr) {
      // Index mungkin belum dibuat, skip reminder tapi lanjut auto-complete
      console.warn("Grace period reminder query failed (index missing?):", indexErr);
    }

    // 2) AUTO-COMPLETE: release dana ke seller jika deadline lewat
    const completeQuery = db
      .collection("orders")
      .where("status", "==", "SHIPPED")
      .where("autoCompleteAt", "<=", nowTs)
      .limit(100);

    let completed = 0;
    const completeSnap = await completeQuery.get();

    for (const doc of completeSnap.docs) {
      try {
        const data = doc.data();
        
        // Skip jika sedang disputed (seharusnya status DISPUTED tapi double check)
        if (data.disputeId) {
          console.log(`Skipping disputed order: ${doc.id}`);
          continue;
        }
        
        const buyerId = String(data.buyerId || "");
        const sellerId = String(data.sellerId || "");
        const invoiceId = String(data.invoiceId || doc.id);

        // Call completeOrder dengan completedBy = 'auto'
        const ADMIN_UID = resolveAdminUid();
        if (!ADMIN_UID) {
          console.error("ADMIN_UID not configured, skipping", doc.id);
          continue;
        }

        // Execute completion (reuse existing logic)
        await completeOrderCore(doc.id, ADMIN_UID, "auto");

        // Notif ke buyer: pesanan selesai otomatis
        if (buyerId) {
          await db
            .collection("users")
            .doc(buyerId)
            .collection("notifications")
            .add({
              title: "✅ Pesanan Selesai Otomatis",
              body:
                `Pesanan #${invoiceId} telah diselesaikan otomatis.\n\n` +
                `Jika ada masalah, hubungi customer service.`,
              type: "order_auto_completed",
              orderId: doc.id,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              isRead: false,
            });
        }

        // Notif ke seller: dana masuk
        if (sellerId) {
          const sellerTake = data.amounts?.sellerEarnings || data.amounts?.total || 0;
          await db
            .collection("users")
            .doc(sellerId)
            .collection("notifications")
            .add({
              title: "💰 Dana Pesanan Masuk",
              body:
                `Pesanan #${invoiceId} selesai otomatis. ` +
                `Dana Rp${sellerTake.toLocaleString("id-ID")} telah masuk ke wallet Anda.`,
              type: "order_completed",
              orderId: doc.id,
              amountToSeller: sellerTake,
              timestamp: admin.firestore.FieldValue.serverTimestamp(),
              isRead: false,
            });
        }

        completed++;
        console.log(`Auto-completed order ${doc.id}`);
      } catch (e) {
        console.error("Auto-complete failed for", doc.id, e);
      }
    }

    console.log(
      `autoComplete (SHIPPED): completed ${completed} orders`
    );
    return null;
  });

// --- 9) createDispute: buyer laporkan masalah, freeze auto-complete
export const createDispute = onCall(
  { region: REGION },
  async (req: CallableRequest<any>) => {
    const buyerId = req.auth?.uid;
    if (!buyerId) throw httpsError("unauthenticated", "Login diperlukan.");

    const {
      orderId,
      reason,
      description,
      evidence,
    } = (req.data ?? {}) as Record<string, unknown>;

    if (!orderId || typeof orderId !== "string") {
      throw httpsError("invalid-argument", "orderId wajib.");
    }
    if (!reason || typeof reason !== "string") {
      throw httpsError("invalid-argument", "Alasan komplain wajib diisi.");
    }

    const orderRef = db.collection("orders").doc(orderId);
    const orderSnap = await orderRef.get();

    if (!orderSnap.exists) {
      throw httpsError("not-found", "Order tidak ditemukan.");
    }

    const order = orderSnap.data()!;

    // Validasi: hanya buyer pemilik yang bisa dispute
    if (String(order.buyerId || "") !== buyerId) {
      throw httpsError("permission-denied", "Bukan pemilik pesanan.");
    }

    // Validasi: status harus SHIPPED (belum complete)
    const status = String(order.status || "").toUpperCase();
    if (status !== "SHIPPED") {
      throw httpsError(
        "failed-precondition",
        "Hanya pesanan yang sudah dikirim bisa dilaporkan."
      );
    }

    // Validasi: harus dalam grace period (setelah 48 jam dari shipped)
    const gracePeriodStartAt = order.gracePeriodStartAt;
    if (gracePeriodStartAt) {
      const nowMillis = Date.now();
      const graceStartMillis = gracePeriodStartAt.toMillis();
      
      if (nowMillis < graceStartMillis) {
        const hoursLeft = Math.ceil((graceStartMillis - nowMillis) / (60 * 60 * 1000));
        throw httpsError(
          "failed-precondition",
          `Komplain hanya bisa dilaporkan setelah 2 hari (48 jam) dari pengiriman. Silakan tunggu ${hoursLeft} jam lagi.`
        );
      }
    }

    // Validasi: evidence harus ada (foto + video wajib)
    const evidenceArray = Array.isArray(evidence) ? evidence : [];
    if (evidenceArray.length === 0) {
      throw httpsError(
        "invalid-argument",
        "Bukti foto dan video wajib dilampirkan untuk komplain."
      );
    }

    // Validasi: minimal harus ada 1 video (cek extension .mp4, .mov, .avi)
    const hasVideo = evidenceArray.some((url: string) => {
      const lower = String(url).toLowerCase();
      return lower.includes(".mp4") || lower.includes(".mov") || lower.includes(".avi") || lower.includes(".webm");
    });

    if (!hasVideo) {
      throw httpsError(
        "invalid-argument",
        "Video unboxing wajib dilampirkan sebagai bukti komplain."
      );
    }

    // Cek apakah sudah ada dispute untuk order ini
    const existingDispute = await db
      .collection("orderDisputes")
      .where("orderId", "==", orderId)
      .where("status", "in", ["open", "investigating"])
      .limit(1)
      .get();

    if (!existingDispute.empty) {
      throw httpsError(
        "already-exists",
        "Laporan untuk pesanan ini sudah ada dan sedang diproses."
      );
    }

    // Buat dispute document
    const disputeRef = await db.collection("orderDisputes").add({
      orderId,
      buyerId,
      sellerId: String(order.sellerId || ""),
      storeId: String(order.storeId || ""),
      invoiceId: String(order.invoiceId || orderId),
      reason: String(reason),
      description: String(description || ""),
      evidence: evidenceArray,
      status: "open", // open, investigating, resolved, rejected
      createdAt: NOW,
      updatedAt: NOW,
      resolution: null,
      resolvedAt: null,
      adminNotes: null,
    });

    // Freeze auto-complete: set status DISPUTED & hapus autoCompleteAt
    await orderRef.update({
      status: "DISPUTED",
      disputeId: disputeRef.id,
      autoCompleteAt: admin.firestore.FieldValue.delete(),
      updatedAt: NOW,
    });

    // Notifikasi ke seller: pesanan dilaporkan
    const sellerId = String(order.sellerId || "");
    if (sellerId) {
      await db
        .collection("users")
        .doc(sellerId)
        .collection("notifications")
        .add({
          title: "⚠️ Pesanan Dilaporkan",
          body:
            `Buyer melaporkan masalah dengan pesanan #${order.invoiceId || orderId}.\n` +
            `Alasan: ${reason}\n\n` +
            `Dana ditahan sampai dispute diselesaikan.`,
          type: "order_disputed",
          orderId,
          disputeId: disputeRef.id,
          timestamp: NOW,
          isRead: false,
        });
    }

    // Notifikasi ke buyer: konfirmasi komplain diterima
    await db
      .collection("users")
      .doc(buyerId)
      .collection("notifications")
      .add({
        title: "✅ Komplain Berhasil Dikirim",
        body:
          `Komplain Anda untuk pesanan #${order.invoiceId || orderId} telah diterima.\n\n` +
          `Status pesanan ditahan sampai admin memproses komplain Anda. ` +
          `Kami akan mengirim notifikasi setelah ada keputusan dari admin.`,
        type: "dispute_submitted",
        orderId,
        disputeId: disputeRef.id,
        timestamp: NOW,
        createdAt: NOW,
        isRead: false,
      });

    // Notifikasi ke admin: ada dispute baru
    try {
      // Kirim ke collection admin_notifications (konsisten dengan approval lain)
      await db
        .collection("admin_notifications")
        .add({
          title: "Komplain Baru",
          body:
            `Pesanan #${order.invoiceId || orderId} dilaporkan buyer.\n` +
            `Alasan: ${reason}`,
          type: "new_dispute",
          orderId,
          disputeId: disputeRef.id,
          priority: "high",
          timestamp: NOW,
          isRead: false,
        });
      console.log("Admin notification sent to admin_notifications collection");
    } catch (notifError) {
      console.error("Failed to send admin notification:", notifError);
      // Don't throw - dispute already created
    }

    console.log("Dispute created successfully:", disputeRef.id);
    return { ok: true, disputeId: disputeRef.id };
  }
);

// --- 10) resolveDispute: admin approve/reject dispute
export const resolveDispute = onCall(
  { region: REGION, secrets: [ADMIN_UID_SECRET] },
  async (req: CallableRequest<any>) => {
    const adminId = req.auth?.uid;
    if (!adminId) throw httpsError("unauthenticated", "Login diperlukan.");

    // Validasi admin role
    const adminSnap = await db.collection("users").doc(adminId).get();
    const roles = adminSnap.get("role") || [];
    const isAdmin = Array.isArray(roles)
      ? roles.includes("admin")
      : roles === "admin";

    if (!isAdmin) {
      throw httpsError("permission-denied", "Hanya admin yang bisa resolve dispute.");
    }

    const {
      disputeId,
      resolution,
      adminNotes,
    } = (req.data ?? {}) as Record<string, unknown>;

    if (!disputeId || typeof disputeId !== "string") {
      throw httpsError("invalid-argument", "disputeId wajib.");
    }
    if (!resolution || !["refund", "reject"].includes(String(resolution))) {
      throw httpsError(
        "invalid-argument",
        "resolution harus 'refund' atau 'reject'."
      );
    }

    const disputeRef = db.collection("orderDisputes").doc(disputeId);
    const disputeSnap = await disputeRef.get();

    if (!disputeSnap.exists) {
      throw httpsError("not-found", "Dispute tidak ditemukan.");
    }

    const dispute = disputeSnap.data()!;
    const orderId = String(dispute.orderId || "");

    if (!orderId) {
      throw httpsError("internal", "Dispute tidak valid (missing orderId).");
    }

    const orderRef = db.collection("orders").doc(orderId);
    const orderSnap = await orderRef.get();
    
    if (!orderSnap.exists) {
      throw httpsError("not-found", "Order tidak ditemukan.");
    }
    
    const order = orderSnap.data()!;

    if (resolution === "refund") {
      // Admin approve: refund dana ke buyer
      await cancelOrderCore(orderId, {
        reason: `Dispute approved: ${adminNotes || dispute.reason}`,
        by: "SYSTEM",
      });

      // Update dispute status
      await disputeRef.update({
        status: "resolved",
        resolution: "refund",
        adminNotes: String(adminNotes || ""),
        resolvedAt: NOW,
        resolvedBy: adminId,
        updatedAt: NOW,
      });

      // Notif buyer: refund approved
      const buyerId = String(dispute.buyerId || "");
      if (buyerId) {
        const totalAmount = asInt(order.amounts?.total);
        const formattedAmount = new Intl.NumberFormat("id-ID", {
          style: "currency",
          currency: "IDR",
          minimumFractionDigits: 0,
        }).format(totalAmount);

        await db
          .collection("users")
          .doc(buyerId)
          .collection("notifications")
          .add({
            title: "✅ Komplain Disetujui",
            body:
              `Komplain Anda untuk pesanan #${dispute.invoiceId || orderId} disetujui.\n` +
              `Dana sebesar ${formattedAmount} telah dikembalikan ke dompet Anda.`,
            type: "dispute_approved",
            orderId,
            disputeId,
            timestamp: NOW,
            isRead: false,
          });
      }

      // Notif seller: dispute resolved, refunded
      const sellerId = String(dispute.sellerId || "");
      if (sellerId) {
        await db
          .collection("users")
          .doc(sellerId)
          .collection("notifications")
          .add({
            title: "⚠️ Dispute Disetujui - Dana Dikembalikan",
            body:
              `Dispute untuk pesanan #${dispute.invoiceId || orderId} disetujui admin.\n` +
              `Dana dikembalikan ke buyer.`,
            type: "dispute_refunded",
            orderId,
            disputeId,
            timestamp: NOW,
            isRead: false,
          });
      }
    } else {
      // Admin reject: lanjutkan order, restore auto-complete
      const orderSnap = await orderRef.get();
      const orderData = orderSnap.data();

      if (orderData) {
        // Restore autoCompleteAt (extend 24 jam dari sekarang untuk seller)
        const newAutoComplete = admin.firestore.Timestamp.fromMillis(
          Date.now() + ONE_DAY_MS
        );

        await orderRef.update({
          status: "SHIPPED",
          autoCompleteAt: newAutoComplete,
          disputeId: admin.firestore.FieldValue.delete(),
          updatedAt: NOW,
        });
      }

      // Update dispute status
      await disputeRef.update({
        status: "rejected",
        resolution: "reject",
        adminNotes: String(adminNotes || ""),
        resolvedAt: NOW,
        resolvedBy: adminId,
        updatedAt: NOW,
      });

      // Notif buyer: komplain ditolak
      const buyerId = String(dispute.buyerId || "");
      if (buyerId) {
        await db
          .collection("users")
          .doc(buyerId)
          .collection("notifications")
          .add({
            title: "❌ Komplain Ditolak",
            body:
              `Komplain Anda untuk pesanan #${dispute.invoiceId || orderId} ditolak.\n` +
              `Alasan: ${adminNotes || "Tidak cukup bukti."}`,
            type: "dispute_rejected",
            orderId,
            disputeId,
            timestamp: NOW,
            isRead: false,
          });
      }

      // Notif seller: dispute rejected, proceed
      const sellerId = String(dispute.sellerId || "");
      if (sellerId) {
        await db
          .collection("users")
          .doc(sellerId)
          .collection("notifications")
          .add({
            title: "✅ Dispute Ditolak - Pesanan Dilanjutkan",
            body:
              `Dispute untuk pesanan #${dispute.invoiceId || orderId} ditolak admin.\n` +
              `Pesanan akan selesai otomatis dalam 24 jam.`,
            type: "dispute_rejected_seller",
            orderId,
            disputeId,
            timestamp: NOW,
            isRead: false,
          });
      }
    }

    return { ok: true };
  }
);

// Helper function untuk complete order (extracted untuk reuse)
async function completeOrderCore(
  orderId: string,
  ADMIN_UID: string,
  completedBy: string
) {
  const orderRef = db.collection("orders").doc(orderId);

  await db.runTransaction(async (t) => {
    const orderSnap = await t.get(orderRef);
    if (!orderSnap.exists) return;

    const order = orderSnap.data()!;
    if ((order.payment?.status ?? "") !== "ESCROWED") return;

    const subtotal = asInt(order.amounts?.subtotal);
    const shipping = asInt(order.amounts?.shipping);
    const service = asInt(order.amounts?.serviceFee);
    const tax = asInt(order.amounts?.tax);
    const total = asInt(order.amounts?.total);

    const buyerId = String(order.buyerId ?? "");
    const sellerId = String(order.sellerId ?? "");
    if (!sellerId || total <= 0) return;

    const sellerTake = subtotal + shipping;
    let adminTake = service + tax;
    const remainder = total - sellerTake - adminTake;
    if (remainder > 0) adminTake += remainder;

    const buyerRef = db.collection("users").doc(buyerId);
    const sellerRef = db.collection("users").doc(sellerId);
    const adminRef = db.collection("users").doc(ADMIN_UID);

    const buyerSnap = await t.get(buyerRef);
    const sellerSnap = await t.get(sellerRef);
    const adminSnap = await t.get(adminRef);

    const bWallet = buyerSnap.get("wallet") ?? { available: 0, onHold: 0 };
    const sWallet = sellerSnap.get("wallet") ?? { available: 0, onHold: 0 };
    const aWallet = adminSnap.get("wallet") ?? { available: 0, onHold: 0 };

    // Release hold + credit seller
    t.update(buyerRef, {
      "wallet.onHold": Math.max(0, asInt(bWallet.onHold) - total),
      "wallet.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    });

    t.update(sellerRef, {
      "wallet.available": asInt(sWallet.available) + sellerTake,
      "wallet.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
    });

    if (adminTake > 0) {
      t.set(
        adminRef,
        {
          wallet: {
            available: asInt(aWallet.available) + adminTake,
            onHold: asInt(aWallet.onHold) || 0,
            currency: aWallet.currency || "IDR",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    }

    // Update product metrics
    const items: any[] = order.items || [];
    for (const it of items) {
      const ref = db.collection("products").doc(String(it.productId));
      const qty = asInt(it.qty);
      t.update(ref, { sold: admin.firestore.FieldValue.increment(qty) });
    }

    const storeIdStr = String(order.storeId || "");
    if (storeIdStr) {
      const totalQty = items.reduce((sum, it) => sum + asInt(it.qty), 0);
      const storeRef = db.collection("stores").doc(storeIdStr);
      t.update(storeRef, {
        totalSales: admin.firestore.FieldValue.increment(totalQty),
        lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Update order status
    t.update(orderRef, {
      status: "COMPLETED",
      "payment.status": "SETTLED",
      "shippingAddress.status": "COMPLETED",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      completedBy,
      settlement: {
        sellerTake,
        adminTake,
        settledAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      autoCancelAt: admin.firestore.FieldValue.delete(),
      shipByAt: admin.firestore.FieldValue.delete(),
      autoCompleteAt: admin.firestore.FieldValue.delete(),
      reminderSentAt: admin.firestore.FieldValue.delete(),
    });
  });
}
