const nodemailer = require('nodemailer');

export default async function handler(req, res) {
  // Allow CORS
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed. Use POST.' });
  }

  try {
    const { recipientEmail, password, roleLabel, recipientName } = req.body;

    const email = String(recipientEmail || '').trim().toLowerCase();
    const pass = String(password || '').trim();
    const role = String(roleLabel || 'user').trim();
    const name = recipientName && String(recipientName).trim() ? String(recipientName).trim() : 'User';

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Valid recipient email is required.' });
    }
    if (!pass) {
      return res.status(400).json({ error: 'Password is required.' });
    }

    const smtpEmail = process.env.SMTP_EMAIL;
    const smtpPassword = process.env.SMTP_PASSWORD;

    if (!smtpEmail || !smtpPassword) {
      return res.status(500).json({
        error: 'SMTP credentials (SMTP_EMAIL, SMTP_PASSWORD) are not configured in Vercel Environment Variables.',
      });
    }

    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: smtpEmail,
        pass: smtpPassword,
      },
    });

    const emailText = `Hello ${name},

Your ${role} account for TRAKR has been created.

Here are your login credentials:
User ID: ${email}
Password: ${pass}

Please log in using these credentials. You can change your password later using Forgot Password with this registered email.

Best Regards,
TRAKR Team`;

    await transporter.sendMail({
      from: `"TRAKR" <${smtpEmail}>`,
      to: email,
      subject: 'Your TRAKR Login Credentials',
      text: emailText,
    });

    return res.status(200).json({ success: true, message: 'Credential email sent successfully.' });
  } catch (error) {
    console.error('Error sending credential email:', error);
    return res.status(500).json({ error: 'Internal server error', details: error.message });
  }
}
