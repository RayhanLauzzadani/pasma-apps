// functions/src/index.ts
import * as admin from "firebase-admin";

// Inisialisasi Admin SDK sekali di entrypoint
admin.initializeApp();

// === Admin Management (PRIORITY) ===
export { createFirstAdmin, setAdminRole } from "./admin";

// === Payments / Midtrans ===
// export { createQrisTransaction } from "./midtrans_qris";

// === Rating ===
export { onRatingWritten } from "./auto_rating";

// === Wallet & Order Escrow ===
export {
  initWalletOnSignup,
  placeOrder,
  completeOrder,
  cancelOrder,
  acceptOrder,
  autoCancelUnacceptedOrders,
  autoCancelUnshippedOrders,
  autoCompleteShippedOrders,
  createDispute,
  resolveDispute,
} from "./wallet_escrow";

// === Shipping ===
export { quoteDelivery } from "./shipping";

// === Notifikasi (FCM) - Firestore triggers ===
export {
  onUserNotificationCreated,
  onChatNotificationCreated,
} from "./notifications";

// === Token dedup / hardening ===
// export {
//   ensureUniqueToken,
//   onUserFcmTokensUpdated,
// } from "./ensureUniqueToken";
