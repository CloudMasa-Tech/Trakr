const { execSync } = require('child_process');
async function main() {
  const secretJson = execSync('gcloud secrets versions access latest --secret="SERVICE_ACCOUNT_JSON" --project=trakradminsetup-28437').toString();
  process.env.SERVICE_ACCOUNT_JSON = secretJson;

  const { getMasterAccessToken } = require('./lib/lib/firebaseAdmin.js');
  const token = await getMasterAccessToken();
  console.log('Token obtained.');

  const projectId = 'qr-attendance-3459f-ldrixe6w'; // The one from the screenshot
  const url = `https://identitytoolkit.googleapis.com/v2/projects/${projectId}/config`;
  
  console.log(`GET ${url}`);
  let res = await fetch(url, {
    method: 'GET',
    headers: { 'Authorization': `Bearer ${token}` }
  });
  
  console.log('GET Status:', res.status);
  console.log('GET Response:', await res.text());

  // Let's also try identityPlatform:initializeAuth if GET returns 404
  if (res.status === 404) {
    const initUrl = `https://identitytoolkit.googleapis.com/v2/projects/${projectId}/identityPlatform:initializeAuth`;
    console.log(`\nPOST ${initUrl}`);
    res = await fetch(initUrl, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({})
    });
    console.log('Init Status:', res.status);
    console.log('Init Response:', await res.text());
  }
}

main().catch(console.error);
