// Temporary script to reset admin password
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const uid = 'aMFefnbnfVfMXpkDi4B9i2aUtd73';
const newPassword = 'admin123';

admin.auth().updateUser(uid, {
  password: newPassword,
  emailVerified: true
})
.then(() => {
  console.log('✅ Password updated successfully!');
  console.log('Email: pasma@admin.com');
  console.log('Password: admin123');
  process.exit(0);
})
.catch(error => {
  console.error('❌ Error:', error);
  process.exit(1);
});
