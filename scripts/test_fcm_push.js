// Simplified FCM Test Push using native crypto
const fs = require('fs');
const https = require('https');
const crypto = require('crypto');

// Read service account key
const serviceAccount = JSON.parse(fs.readFileSync('C:/Users/andre/Downloads/spotwatt-900e9-firebase-adminsdk-fbsvc-1b1af9554f.json', 'utf8'));

// FCM device token
const DEVICE_TOKEN = 'fdeN74dIRJyF9CG90Icvx2:APA91bF7tno2rewpt5bxi_m66BXDH3z6TzQba2iC8QPuIcpFTpVCkeaoGH0UXbQDDt0S_uPj-lSJlItbNcrigD6yyHzZrDZMZveCLSNQZxpI-xIH7VFcBuw';

// Base64 URL encode
function base64UrlEncode(str) {
  return Buffer.from(str)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// Get OAuth2 access token
async function getAccessToken() {
  return new Promise((resolve, reject) => {
    try {
      const now = Math.floor(Date.now() / 1000);

      const header = {
        alg: 'RS256',
        typ: 'JWT'
      };

      const payload = {
        iss: serviceAccount.client_email,
        sub: serviceAccount.client_email,
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
        scope: 'https://www.googleapis.com/auth/firebase.messaging'
      };

      const encodedHeader = base64UrlEncode(JSON.stringify(header));
      const encodedPayload = base64UrlEncode(JSON.stringify(payload));
      const unsignedToken = `${encodedHeader}.${encodedPayload}`;

      // Sign JWT
      const sign = crypto.createSign('RSA-SHA256');
      sign.update(unsignedToken);
      const signature = sign.sign(serviceAccount.private_key);
      const encodedSignature = signature.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');

      const jwt = `${unsignedToken}.${encodedSignature}`;

      // Exchange JWT for access token
      const postData = new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt
      }).toString();

      const options = {
        hostname: 'oauth2.googleapis.com',
        port: 443,
        path: '/token',
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': postData.length
        }
      };

      const req = https.request(options, (res) => {
        let data = '';

        res.on('data', (chunk) => {
          data += chunk;
        });

        res.on('end', () => {
          if (res.statusCode === 200) {
            const response = JSON.parse(data);
            resolve(response.access_token);
          } else {
            reject(new Error(`Token request failed: ${res.statusCode} - ${data}`));
          }
        });
      });

      req.on('error', (error) => {
        reject(error);
      });

      req.write(postData);
      req.end();

    } catch (error) {
      reject(error);
    }
  });
}

// Send FCM message
async function sendTestPush() {
  try {
    console.log('🔑 Getting access token...');
    const accessToken = await getAccessToken();
    console.log('✅ Access token obtained');

    const message = {
      message: {
        token: DEVICE_TOKEN,
        data: {
          action: 'update_prices'
        },
        android: {
          priority: 'high'
        }
      }
    };

    console.log('📤 Sending FCM message...');
    console.log('Token:', DEVICE_TOKEN.substring(0, 30) + '...');

    const data = JSON.stringify(message);

    const options = {
      hostname: 'fcm.googleapis.com',
      port: 443,
      path: '/v1/projects/spotwatt-900e9/messages:send',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
        'Content-Length': data.length
      }
    };

    const req = https.request(options, (res) => {
      let responseData = '';

      res.on('data', (chunk) => {
        responseData += chunk;
      });

      res.on('end', () => {
        if (res.statusCode === 200) {
          console.log('✅ FCM message sent successfully!');
          console.log('Response:', JSON.parse(responseData));
        } else {
          console.error('❌ FCM send failed:', res.statusCode);
          console.error('Response:', responseData);
        }
      });
    });

    req.on('error', (error) => {
      console.error('❌ Request error:', error);
    });

    req.write(data);
    req.end();

  } catch (error) {
    console.error('❌ Error:', error);
  }
}

sendTestPush();
