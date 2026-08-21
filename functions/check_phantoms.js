const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'trakradminsetup-28437',
  credential: admin.credential.applicationDefault()
});

const db = admin.firestore();

async function check() {
  console.log('Checking for phantom workspaces...');
  
  const snapshot = await db.collection('workspaces')
    .where('gcpProjectVerified', '==', false)
    .get();
  console.log(`Found ${snapshot.size} phantom workspace(s):`);
  for (const doc of snapshot.docs) {
    console.log(`  Workspace ID: ${doc.id}`);
    console.log(`  Data: ${JSON.stringify(doc.data(), null, 2)}`);
  }
  
  const deletedSnapshot = await db.collection('deleted_projects').where(admin.firestore.FieldPath.documentId(), 'in', ['sample-4c6ce', 'sample-1e482']).get();
  console.log(`\nFound ${deletedSnapshot.size} deleted_project(s):`);
  for (const doc of deletedSnapshot.docs) {
    console.log(`  Project ID: ${doc.id}`);
    console.log(`  Data: ${JSON.stringify(doc.data(), null, 2)}`);
  }
  
  const auditSnapshot = await db.collection('audit_logs').where('targetName', 'in', ['sample-4c6ce', 'sample-1e482']).get();
  console.log(`\nFound ${auditSnapshot.size} audit_log(s):`);
  for (const doc of auditSnapshot.docs) {
    console.log(`  Log ID: ${doc.id}`);
    console.log(`  Data: ${JSON.stringify(doc.data(), null, 2)}`);
  }
  
  const allocSnapshot = await db.collection('project_allocations').where(admin.firestore.FieldPath.documentId(), 'in', ['sample-4c6ce', 'sample-1e482']).get();
  console.log(`\nFound ${allocSnapshot.size} project_allocation(s):`);
  for (const doc of allocSnapshot.docs) {
    console.log(`  Project ID: ${doc.id}`);
    console.log(`  Data: ${JSON.stringify(doc.data(), null, 2)}`);
  }
  
  // Check tenant_users for workspaces
  if (snapshot.size > 0) {
    const workspaceIds = snapshot.docs.map(d => d.id);
    const tenantUsersSnapshot = await db.collection('tenant_users').where('workspaceId', 'in', workspaceIds).get();
    console.log(`\nFound ${tenantUsersSnapshot.size} tenant_users entries:`);
    for (const doc of tenantUsersSnapshot.docs) {
      console.log(`  Doc ID: ${doc.id}`);
      console.log(`  Data: ${JSON.stringify(doc.data(), null, 2)}`);
    }
    
    const provisionSnapshot = await db.collection('workspace_provision_logs').where('workspaceId', 'in', workspaceIds).get();
    console.log(`\nFound ${provisionSnapshot.size} workspace_provision_logs entries:`);
    for (const doc of provisionSnapshot.docs) {
      console.log(`  Doc ID: ${doc.id}`);
      console.log(`  Data: ${JSON.stringify(doc.data(), null, 2)}`);
    }
  }
  
  process.exit(0);
}

check().catch(e => { console.error(e); process.exit(1); });
