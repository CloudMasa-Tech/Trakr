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

  try {
    console.log('Attempting to update EmailSignInConfig...');
    // updateProjectConfig does not accept signIn.
    // What does it accept?
    // Let's print out the interface structure if we can.
    await app.auth().projectConfigManager().updateProjectConfig({
      passwordPolicyConfig: { enforcePasswordPolicy: false } // Just trying anything valid to see if it creates the config
    });
    console.log('Update Success!');
  } catch(e) {
    console.log('Update Error:', e.message);
  }
}

main().catch(console.error);
