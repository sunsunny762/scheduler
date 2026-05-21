import { Injectable, OnModuleInit } from '@nestjs/common';
import * as admin from 'firebase-admin';

const serviceAccount = require('../../firebase/default.json');
@Injectable()
export class FirebaseAdminService implements OnModuleInit {
  onModuleInit() {
    // Initialize Firebase Admin SDK if not already initialized
    if (!admin.apps.length) {
      try {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
        });
        console.log('Firebase Admin initialized successfully');
      } catch (error) {
        console.error('Firebase Admin initialization error:', error);
        throw error;
      }
    }
  }

  getAuth() {
    return admin.auth();
  }
}