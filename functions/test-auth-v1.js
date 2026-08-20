async function main() {
  const { getMasterAccessToken } = require('./lib/lib/firebaseAdmin.js');
  const token = await getMasterAccessToken();
  const projectId = 'qr-attendance-3459f-ldrixe6w'; // The one from the screenshot
  
  const url1 = `https://identitytoolkit.googleapis.com/admin/v2/projects/${projectId}/config`;
  const url2 = `https://identitytoolkit.googleapis.com/v1/projects/${projectId}/config`;

  let res = await fetch(url1, { headers: { 'Authorization': `Bearer ${token}` } });
  console.log('GET admin/v2:', res.status, await res.text());

  // How about we try creating a default tenant?
  const url3 = `https://identitytoolkit.googleapis.com/v2/projects/${projectId}/tenants`;
  res = await fetch(url3, { headers: { 'Authorization': `Bearer ${token}` } });
  console.log('GET tenants:', res.status, await res.text());
}
main().catch(console.error);
