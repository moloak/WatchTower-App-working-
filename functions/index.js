const functions = require('firebase-functions');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();
const db = admin.firestore();

// Helper: construct a password reset response ensuring we do not leak
// whether an email exists in the system. The admin SDK is used server-side
// to check providers safely. Caller sees only high-level guidance.
async function buildPasswordResetResponse(email) {
  try {
    // Use Admin SDK to get user by email. This will throw if no user exists.
    const userRecord = await admin.auth().getUserByEmail(email);
    const providers = userRecord.providerData.map((p) => p.providerId || '').filter(Boolean);

    // If the account uses a federated provider (e.g., google.com), reject
    // allowing a password reset from the client. Respond with a neutral
    // message that tells the client which path to show.
    if (providers.includes('google.com') || providers.includes('apple.com')) {
      return { canReset: false, reason: 'federated' };
    }

    // Generate a password reset link using Admin SDK.
    // Note: createCustomToken is different; use generatePasswordResetLink
    // available in the Admin SDK.
    const cfg = functions.config ? functions.config() : {};
    const continueUrl = process.env.PASSWORD_RESET_CONTINUE_URL || (cfg.password_reset && cfg.password_reset.continue_url) || 'https://your-app.example.com/reset';

    const resetLink = await admin.auth().generatePasswordResetLink(email, {
      // This continuation URL should be your app's hosted domain where
      // App Links / Universal Links are configured. Update via functions config
      // or environment variable.
      url: continueUrl,
      // Optionally set handleCodeInApp to true so the link opens the app.
      // The Firebase Admin SDK supports adding this as a query param.
    });

    return { canReset: true, sent: false, resetLink };
  } catch (err) {
    // If user not found, don't reveal that. Allow client to behave as if
    // an email was sent (prevent user enumeration), but we still return
    // canReset: true and sent: false so the client may show a generic UI.
    if (err.code && (err.code === 'auth/user-not-found' || err.code === 'USER_NOT_FOUND')) {
      // user not found — return neutral positive response
      return { canReset: true, sent: false };
    }

    console.error('buildPasswordResetResponse error', err);
    throw err;
  }
}

// Optional: function to send email via SMTP using nodemailer. This is
// configurable via environment variables.
async function sendResetEmailViaSmtp(toEmail, resetLink) {
  const cfg = functions.config ? functions.config() : {};
  const smtpHost = process.env.SMTP_HOST || (cfg.smtp && cfg.smtp.host);
  const smtpPort = process.env.SMTP_PORT ? parseInt(process.env.SMTP_PORT, 10) : (cfg.smtp && cfg.smtp.port ? parseInt(cfg.smtp.port, 10) : 587);
  const smtpUser = process.env.SMTP_USER || (cfg.smtp && cfg.smtp.user);
  const smtpPass = process.env.SMTP_PASS || (cfg.smtp && cfg.smtp.pass);

  if (!smtpHost || !smtpUser || !smtpPass) {
    console.warn('SMTP not configured; skipping sendResetEmailViaSmtp');
    return false;
  }

  const transporter = nodemailer.createTransport({
    host: smtpHost,
    port: smtpPort,
    secure: smtpPort === 465, // true for 465, false for other ports
    auth: {
      user: smtpUser,
      pass: smtpPass,
    },
  });

  const info = await transporter.sendMail({
  from: process.env.SMTP_FROM || (cfg.smtp && cfg.smtp.from) || smtpUser,
    to: toEmail,
    subject: 'Reset your password',
    text: `Reset your password by visiting the following link:\n\n${resetLink}\n\nIf you didn't request this, you can ignore this email.`,
    html: `<p>Reset your password by clicking <a href="${resetLink}">this link</a>.</p>`,
  });

  console.log('nodemailer sent:', info.messageId);
  return true;
}

// HTTP function to accept weekly summaries from trusted devices.
// The client should send an Authorization: Bearer <Firebase ID token>
// and a JSON body with { weekStart, generatedAt, apps }
exports.pushWeeklySummary = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const auth = req.get('Authorization') || req.get('authorization');
    if (!auth || !auth.startsWith('Bearer ')) {
      res.status(401).send('Missing or invalid Authorization header');
      return;
    }

    const idToken = auth.split('Bearer ')[1];
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      console.error('Failed to verify ID token:', err);
      res.status(401).send('Invalid ID token');
      return;
    }

    const uid = decoded.uid;
    const body = req.body;
    if (!body || !body.weekStart || !body.apps) {
      res.status(400).send('Invalid payload');
      return;
    }

    const weekStart = body.weekStart;
    const docRef = db.collection('users').doc(uid).collection('weekly_summaries').doc(weekStart);
    await docRef.set({
      weekStart: weekStart,
      generatedAt: body.generatedAt || new Date().toISOString(),
      apps: body.apps,
      pushedBy: 'device',
      pushedAt: new Date().toISOString(),
    });

    res.status(200).send({ success: true });
  } catch (e) {
    console.error('pushWeeklySummary error', e);
    res.status(500).send('Internal Server Error');
  }
});

// Scheduled Cloud Function that aggregates daily_usage docs into a weekly
// summary for each user. Runs every Monday at 03:00 UTC and aggregates the
// previous week's data (Monday..Sunday).
exports.aggregateWeeklySummaries = functions.pubsub
  .schedule('every monday 03:00')
  .timeZone('UTC')
  .onRun(async (context) => {
    try {
      // Compute previous week's Monday
      const now = new Date();
      const thisMonday = new Date(now);
      // Set to nearest Monday of current week
      const day = thisMonday.getUTCDay(); // 0 (Sun) - 6 (Sat)
      const deltaToMonday = ((day + 6) % 7); // days since Monday
      thisMonday.setUTCDate(thisMonday.getUTCDate() - deltaToMonday);
      // previous week's Monday
      const prevMonday = new Date(thisMonday);
      prevMonday.setUTCDate(thisMonday.getUTCDate() - 7);

      const weekStartStr = prevMonday.toISOString().slice(0, 10); // YYYY-MM-DD
      const weekEnd = new Date(prevMonday);
      weekEnd.setUTCDate(prevMonday.getUTCDate() + 6);
      const weekEndStr = weekEnd.toISOString().slice(0, 10);

      console.log('Aggregating weekly summaries for weekStart=', weekStartStr);

      // Iterate all users under /users collection
      const usersSnap = await db.collection('users').get();
      for (const userDoc of usersSnap.docs) {
        const uid = userDoc.id;
        try {
          const dailyQuery = await db.collection('users').doc(uid).collection('daily_usage')
            .where('date', '>=', weekStartStr)
            .where('date', '<=', weekEndStr)
            .get();

          if (dailyQuery.empty) {
            // nothing to aggregate for this user
            continue;
          }

          const aggregate = {};
          for (const d of dailyQuery.docs) {
            const data = d.data();
            if (!data.packageName) continue;
            const pkg = data.packageName;
            const minutes = data.minutes || 0;
            aggregate[pkg] = (aggregate[pkg] || 0) + minutes;
          }

          if (Object.keys(aggregate).length === 0) continue;

          const docRef = db.collection('users').doc(uid).collection('weekly_summaries').doc(weekStartStr);
          await docRef.set({
            weekStart: weekStartStr,
            generatedAt: new Date().toISOString(),
            apps: aggregate,
            pushedBy: 'server_cron',
            pushedAt: new Date().toISOString(),
          }, { merge: true });
        } catch (e) {
          console.error(`Failed to aggregate for user ${uid}:`, e);
        }
      }

      return null;
    } catch (e) {
      console.error('aggregateWeeklySummaries error', e);
      return null;
    }
  });

// HTTP admin endpoint to trigger aggregation on demand for testing. Protect
// with an ADMIN_SECRET environment variable (set via Firebase Functions config
// or environment) to avoid exposing this endpoint publicly.
exports.triggerAggregateWeeklySummaries = functions.https.onRequest(async (req, res) => {
  try {
    const adminSecret = process.env.ADMIN_SECRET || functions.config().admin?.secret;
    const provided = req.get('x-admin-secret');
    if (!adminSecret || provided !== adminSecret) {
      res.status(403).send('Forbidden');
      return;
    }

    // Reuse the aggregation logic by invoking the scheduled handler.
    // We call the same aggregation code inline here for simplicity.
    // Compute previous week's Monday
    const now = new Date();
    const thisMonday = new Date(now);
    const day = thisMonday.getUTCDay();
    const deltaToMonday = ((day + 6) % 7);
    thisMonday.setUTCDate(thisMonday.getUTCDate() - deltaToMonday);
    const prevMonday = new Date(thisMonday);
    prevMonday.setUTCDate(thisMonday.getUTCDate() - 7);

    const weekStartStr = prevMonday.toISOString().slice(0, 10);
    const weekEnd = new Date(prevMonday);
    weekEnd.setUTCDate(prevMonday.getUTCDate() + 6);
    const weekEndStr = weekEnd.toISOString().slice(0, 10);

    const usersSnap = await db.collection('users').get();
    for (const userDoc of usersSnap.docs) {
      const uid = userDoc.id;
      try {
        const dailyQuery = await db.collection('users').doc(uid).collection('daily_usage')
          .where('date', '>=', weekStartStr)
          .where('date', '<=', weekEndStr)
          .get();

        if (dailyQuery.empty) continue;

        const aggregate = {};
        for (const d of dailyQuery.docs) {
          const data = d.data();
          if (!data.packageName) continue;
          const pkg = data.packageName;
          const minutes = data.minutes || 0;
          aggregate[pkg] = (aggregate[pkg] || 0) + minutes;
        }

        if (Object.keys(aggregate).length === 0) continue;

        const docRef = db.collection('users').doc(uid).collection('weekly_summaries').doc(weekStartStr);
        await docRef.set({
          weekStart: weekStartStr,
          generatedAt: new Date().toISOString(),
          apps: aggregate,
          pushedBy: 'server_manual',
          pushedAt: new Date().toISOString(),
        }, { merge: true });
      } catch (e) {
        console.error(`Failed to aggregate for user ${uid}:`, e);
      }
    }

    res.status(200).send({ success: true, weekStart: weekStartStr });
  } catch (e) {
    console.error('triggerAggregateWeeklySummaries error', e);
    res.status(500).send('Internal Server Error');
  }
});


/**
 * HTTP endpoint to securely evaluate whether a password reset should be
 * initiated for the given email. It will:
 * - Accept POST { email: string }
 * - Use Admin SDK to look up the user and their providers
 * - If federated provider (google/apple) is used, respond { canReset: false, reason: 'federated' }
 * - Otherwise, generate a password reset link via Admin SDK and optionally send it via SMTP.
 *
 * Response (200): { canReset: bool, reason?: string, sent?: bool, resetLink?: string }
 * Note: To avoid leaking whether an email exists, responses for unknown emails are intentionally
 * non-revealing: they return canReset: true, sent: false.
 */
exports.createPasswordResetLink = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const body = req.body || {};
    const email = (body.email || '').toString().trim().toLowerCase();
    if (!email) {
      res.status(400).send({ error: 'missing_email' });
      return;
    }

    // Build a safe response using Admin SDK
    const resp = await buildPasswordResetResponse(email);

    // If Admin generated a resetLink and SMTP is configured, try to send it.
    let sent = resp.sent || false;
    if (resp.resetLink) {
      try {
        const didSend = await sendResetEmailViaSmtp(email, resp.resetLink);
        sent = didSend;
      } catch (err) {
        console.error('Failed to send SMTP email:', err);
        // continue; we'll still return the resetLink to authorized callers
      }
    }

    // Return a compact response. For unknown users we return canReset: true
    // so the client shows the generic "If an account exists, we sent an email" UI.
    const out = { canReset: !!resp.canReset, sent };
    if (resp.reason) out.reason = resp.reason;
    // Optionally include resetLink in the response for debugging/testing only.
    const exposeFlag = process.env.EXPOSE_RESET_LINK || (functions.config && functions.config().expose && functions.config().expose.reset_link) || 'false';
    if (String(exposeFlag) === 'true' && resp.resetLink) {
      out.resetLink = resp.resetLink;
    }

    res.status(200).send(out);
  } catch (err) {
    console.error('createPasswordResetLink error', err);
    res.status(500).send({ error: 'internal' });
  }
});

// ------------------ AI Personas & Vertex AI proxy ------------------
// Loads persona system prompts from functions/personas.json and exposes
// simple endpoints to create sessions and send messages. This is a
// lightweight proxy that injects the persona system prompt before
// forwarding the request to Vertex AI. It requires the following
// environment variables to be set before deployment:
// - VERTEX_PROJECT_ID: GCP project id
// - VERTEX_REGION: e.g. us-central1
// - VERTEX_MODEL: model id (e.g., "gemini-1.5" or "models/text-bison-001")
// The function will use Application Default Credentials (service account)
// via google-auth-library to obtain an access token for calling Vertex AI.

const fs = require('fs');
const path = require('path');
const {GoogleAuth} = require('google-auth-library');

let personas = {};
try {
  const p = path.join(__dirname, 'personas.json');
  personas = JSON.parse(fs.readFileSync(p, 'utf8'));
  console.log('Loaded personas:', Object.keys(personas));
} catch (e) {
  console.warn('Could not load personas.json — ensure file exists', e);
}

// Helper: create a session document in Firestore
exports.createAiSession = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
    const body = req.body || {};
    const { userId, persona } = body;
    if (!userId || !persona) return res.status(400).send({ error: 'missing_user_or_persona' });
    if (!personas[persona]) return res.status(400).send({ error: 'unknown_persona' });

    const sessionRef = await db.collection('users').doc(userId).collection('ai_sessions').add({
      persona,
      createdAt: new Date().toISOString(),
      lastActivity: new Date().toISOString(),
    });

    res.status(200).send({ sessionId: sessionRef.id });
  } catch (err) {
    console.error('createAiSession error', err);
    res.status(500).send({ error: 'internal' });
  }
});

// POST /ai/message - send a user message and return the assistant reply
// body: { sessionId, userId, persona, text }
exports.sendAiMessage = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
    const body = req.body || {};
    const { sessionId, userId, persona, text } = body;
    if (!userId || !text) return res.status(400).send({ error: 'missing_user_or_text' });

    const personaId = persona || 'ade';
    const personaObj = personas[personaId] || Object.values(personas)[0];

    // Build the prompt: system prompt (persona) + user text
    const systemPrompt = personaObj && personaObj.systemPrompt ? personaObj.systemPrompt : '';
    const prompt = `${systemPrompt}\n\nUser: ${text}\nAssistant:`;

    // Persist user message (if session provided, save under session)
    let sessionRef = null;
    if (sessionId) {
      sessionRef = db.collection('users').doc(userId).collection('ai_sessions').doc(sessionId);
      await sessionRef.set({ lastActivity: new Date().toISOString() }, { merge: true });
      await sessionRef.collection('messages').add({ role: 'user', text, createdAt: new Date().toISOString() });
    }

    // Prepare Vertex AI call details
    const projectId = process.env.VERTEX_PROJECT_ID || functions.config().vertex?.project_id;
    const region = process.env.VERTEX_REGION || functions.config().vertex?.region || 'us-central1';
    const model = process.env.VERTEX_MODEL || functions.config().vertex?.model || 'gemini-1.5';

    if (!projectId) {
      console.warn('VERTEX_PROJECT_ID not set; cannot call Vertex AI');
      return res.status(500).send({ error: 'vertex_project_not_configured' });
    }

    // Acquire an access token using google-auth-library
    const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
    const client = await auth.getClient();
    const accessTokenResponse = await client.getAccessToken();
    const token = accessTokenResponse && accessTokenResponse.token ? accessTokenResponse.token : accessTokenResponse;

    // Build the Vertex AI REST endpoint URL. Use the generate endpoint for
    // Gemini-style models (gemini-1.5). If you'd prefer a different endpoint
    // signature, set VERTEX_API_URL env var.
    const customUrl = process.env.VERTEX_API_URL || functions.config().vertex?.api_url;
    // Use :generate for generative models like gemini-1.5
    const endpointUrl = customUrl || `https://${region}-aiplatform.googleapis.com/v1/projects/${projectId}/locations/${region}/models/${model}:generate`;

    // Build the request payload for gemini-1.5 (non-streaming). We pass the
    // persona system prompt as the leading context and the user text as the
    // subsequent input. The exact shape may vary by model; this shape has
    // worked with Vertex generative endpoints.
    const instanceInput = `${systemPrompt}\n\nUser: ${text}\nAssistant:`;
    const payload = {
      instances: [
        {
          input: {
            text: instanceInput,
          },
        },
      ],
      parameters: {
        temperature: 0.7,
        maxOutputTokens: 512,
        topP: 0.95,
      },
    };

    const fetchResp = await fetch(endpointUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!fetchResp.ok) {
      const txt = await fetchResp.text();
      console.error('Vertex AI call failed', fetchResp.status, txt);
      return res.status(502).send({ error: 'vertex_error', status: fetchResp.status, body: txt });
    }

    const json = await fetchResp.json();
    // Robust parsing for a few known response shapes. Prefer the most likely
    // generative response fields, but fall back to stringify so callers can
    // debug unexpected shapes.
    let assistantReply = '';
    try {
      // Common shape: { predictions: [ { content: [ { text: '...' } ] } ] }
      if (json.predictions && Array.isArray(json.predictions) && json.predictions[0]) {
        const p = json.predictions[0];
        if (p.content && Array.isArray(p.content) && p.content[0] && p.content[0].text) {
          assistantReply = p.content[0].text;
        } else if (p.text) {
          assistantReply = p.text;
        } else if (p.candidates && p.candidates[0] && p.candidates[0].content) {
          assistantReply = p.candidates[0].content;
        } else {
          assistantReply = JSON.stringify(p);
        }
      // Alternate shape: { 0: { candidates: [ { content: '...' } ] } }
      } else if (Array.isArray(json) && json[0] && json[0].candidates && json[0].candidates[0]) {
        assistantReply = json[0].candidates[0].content || JSON.stringify(json[0].candidates[0]);
      // Another possible shape: { data: [ { content: '...' } ] }
      } else if (json.data && Array.isArray(json.data) && json.data[0] && (json.data[0].content || (json.data[0].text))) {
        assistantReply = json.data[0].content || json.data[0].text;
      } else {
        assistantReply = JSON.stringify(json);
      }
    } catch (parseErr) {
      console.error('Failed to parse Vertex response', parseErr, json);
      assistantReply = JSON.stringify(json);
    }

    // Persist assistant reply
    if (sessionRef) {
      await sessionRef.collection('messages').add({ role: 'assistant', text: assistantReply, createdAt: new Date().toISOString(), persona: personaId });
    }

    res.status(200).send({ reply: assistantReply, raw: json });
  } catch (err) {
    console.error('sendAiMessage error', err);
    res.status(500).send({ error: 'internal' });
  }
});
