// Emby Tag Manager — standalone configuration
//
// SETUP:
//   1. Copy this file to config.js
//   2. Fill in your values below
//   3. Open index.html in your browser
//
// config.js is in .gitignore and will never be committed to git.

window.__EMBY_CONFIG__ = {

  // Full URL to your Emby server — no trailing slash
  serverUrl: 'http://192.168.1.100:8096',

  // Emby API key
  // Find it: Dashboard → Advanced → Security → API Keys → + New Key
  apiKey: 'your_api_key_here',

  // Your Emby user ID (not your username — it's a long hex string)
  // Find it: Dashboard → Users → click your user → copy ID from the URL
  // Or run: curl http://YOUR_SERVER:8096/Users -H "X-Emby-Token: YOUR_KEY"
  userId: 'your_user_id_here'

};