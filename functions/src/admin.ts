// functions/src/admin.ts
import {onRequest} from "firebase-functions/v2/https";
import {onCall} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

/**
 * HTTP Function untuk membuat admin pertama
 * URL: https://YOUR_REGION-YOUR_PROJECT_ID.cloudfunctions.net/createFirstAdmin?email=admin@example.com&password=yourpassword&name=Admin
 * 
 * ⚠️ PENTING: HAPUS atau DISABLE function ini setelah membuat admin pertama!
 */
export const createFirstAdmin = onRequest(
  { 
    cors: true,
    invoker: "public" 
  },
  async (req, res) => {
  // Ambil parameter dari query string
  const email = req.query.email as string;
  const password = req.query.password as string;
  const name = (req.query.name as string) || "Admin";

  // Validasi input
  if (!email || !password) {
    res.status(400).json({
      error: "Missing required parameters",
      usage: "?email=admin@example.com&password=yourpassword&name=Admin",
    });
    return;
  }

  try {
    // 1. Buat user di Firebase Auth
    const userRecord = await admin.auth().createUser({
      email,
      password,
      emailVerified: true,
      displayName: name,
    });

    // 2. Set custom claim 'admin: true'
    await admin.auth().setCustomUserClaims(userRecord.uid, { admin: true });

    // 3. Buat dokumen di Firestore users collection
    await admin.firestore().collection("users").doc(userRecord.uid).set({
      email,
      name,
      role: "admin",
      displayName: name,
      isAdmin: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 4. Berhasil!
    res.status(200).json({
      success: true,
      message: "Admin account created successfully!",
      data: {
        uid: userRecord.uid,
        email: userRecord.email,
        name,
      },
      nextSteps: [
        "1. Login dengan email dan password yang dibuat",
        "2. HAPUS atau DISABLE function 'createFirstAdmin' untuk keamanan",
      ],
    });
  } catch (error: any) {
    console.error("Error creating admin:", error);
    res.status(500).json({
      error: "Failed to create admin account",
      details: error.message,
    });
  }
});

/**
 * Callable Function untuk set admin role ke user yang sudah ada
 * Hanya bisa dipanggil oleh admin yang sudah ada
 */
export const setAdminRole = onCall(async (request) => {
  // Cek apakah caller adalah admin
  if (!request.auth) {
    throw new Error("User must be authenticated");
  }

  const callerToken = request.auth.token;
  if (!callerToken.admin) {
    throw new Error("Only admins can set admin role");
  }

  // Ambil email atau UID dari target user
  const { email, uid } = request.data;

  if (!email && !uid) {
    throw new Error("Must provide either email or uid");
  }

  try {
    // Get user by email or UID
    let userRecord;
    if (uid) {
      userRecord = await admin.auth().getUser(uid);
    } else {
      userRecord = await admin.auth().getUserByEmail(email);
    }

    // Set admin claim
    await admin.auth().setCustomUserClaims(userRecord.uid, { admin: true });

    // Update Firestore document
    await admin.firestore().collection("users").doc(userRecord.uid).set(
      {
        role: "admin",
        isAdmin: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      success: true,
      message: `User ${userRecord.email} is now an admin`,
      uid: userRecord.uid,
    };
  } catch (error: any) {
    throw new Error(error.message);
  }
});
