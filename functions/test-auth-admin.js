const { execSync } = require('child_process');
const admin = require('firebase-admin');

async function main() {
  const secretJson = execSync('gcloud secrets versions access latest --secret="SERVICE_ACCOUNT_JSON" --project=trakradminsetup-28437').toString();
  const credentials = JSON.parse(secretJson);
  
  const projectId = 'qr-attendance-3459f-ldrixe6w'; // The one from the screenshot
  
  const app = admin.initializeApp({
    credential: admin.credential.cert(credentials),
    projectId: projectId,
  });

  console.log('App initialized for', projectId);
  
  try {
    const config = await app.auth().projectConfigManager().getProjectConfig();
    console.log('GET Config:', JSON.stringify(config, null, 2));
  } catch(e) {
    console.log('GET Config Error:', e.message);
  }

  try {
    console.log('Attempting to update config...');
    await app.auth().projectConfigManager().updateProjectConfig({
      signIn: {
        email: {
          enabled: true,
          passwordRequired: true,
        },
      },
    });
    console.log('Update Success!');
  } catch(e) {
    console.log('Update Error:', e.message);
  }
}

main().catch(console.error);
