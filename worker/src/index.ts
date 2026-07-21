

// Imports: Hono for routing, the Anthropic SDK for the Claude call.
import { Hono } from 'hono';
import Anthropic from '@anthropic-ai/sdk';

// Bindings: the worker's environment, holding the API key secrets.
type Bindings = {
  ANTHROPIC_API_KEY: string;      // wrangler secret
  OPENAI_API_KEY: string;         // wrangler secret
  OPENAI_REALTIME_MODEL: string;  // wrangler.toml [vars]
}

// CARD_SCHEMA: the exact JSON shape Claude must return. With structured
// outputs the model is forced to fill these four string fields, so the
// response is always valid JSON in this shape.
const CARD_SCHEMA = {
  type: 'object',
  properties: {
    word: { type: "string", description: "The object's name in Simplified Chinese (hanzi)" },
    pinyin: { type: "string", description: "Pinyin with tone marks for the word" },
    translation: { type: "string", description: "The English meaning of the word" },
    example: { type: "string", description: "A short, natural example sentence in Simplified Chinese using the word" },
  },
  required: ['word', 'pinyin', 'translation', 'example'],
  additionalProperties: false,
} as const; 

// PROMPT: the instruction telling Claude to read the main object in the photo
// and write the four card fields in Simplified Chinese.
const PROMPT =`
  Look at the main object in this photo. Produce a Chinese (Simplified)
  vocabulary card for a beginner language learner: the word for that object 
  in hanzi, its pinyin, the English translation, and one short natural example
  sentence in Chinese that uses the word.
  `;  

// app: the Hono application, typed with the bindings above.
const app = new Hono<{ Bindings: Bindings }>(); 

// GET / : a health check so opening the URL in a browser shows it is alive.
app.get('/', (c) => c.text('VocabGlass Worker is running') );

// POST /generate : read the image from the body, send it to Claude with the
// schema and prompt, and return the card JSON (502 on failure).
app.post('/generate', async (c) => {
  const body = await c.req
    .json<{ image?: string; mediaType?: string }>()
    .catch(() => null);
  if (!body?.image) {
    return c.json({ error: "missing image" }, 400);
  }

  const client = new Anthropic({ apiKey: c.env.ANTHROPIC_API_KEY });

  try {
    const response = await client.messages.create({
      model: 'claude-sonnet-4-6',
      max_tokens: 1024,
      output_config: { format: {type: 'json_schema', schema: CARD_SCHEMA} },
            messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: 'image/jpeg',
                data: body.image,
              },
            },
            { type: 'text', text: PROMPT },
          ],
        },
      ],
    });

    const text = response.content.find((b) => b.type === 'text')?.text;
    if (!text) {
      return c.json({ error: "no card returned" }, 502);
    }
    return c.body(text, 200, { 'content-type': 'application/json' });
  } catch (err) {
    return c.json({ error: `claude request failed: ${String(err)}` }, 502);
  }
});

// The session brain. The system prompt and tools are baked into the
// ephemeral key via the session config, not sent by the app: a leaked
// key can only start a VocabGlass session, not a general-purpose one.
// The model decides on its own when to call the tools.
const REALTIME_SYSTEM_PROMPT = `You are VocabGlass, a voice assistant for a language learning session. The user wears camera glasses and looks at real objects, capturing them as vocabulary cards. Keep replies short and conversational.`;

const REALTIME_TOOLS = [
  {
    type: 'function',
    name: 'capture_object',
    description: 'Capture a photo of what the user is looking at and save it as a vocabulary entry. Call this when the user asks to capture, save, or learn the thing they see.',
    parameters: { type: 'object', properties: {} },
  },
  {
    type: 'function',
    name: 'end_session',
    description: 'End the current learning session. Call this when the user says they are done or asks to end the session.',
    parameters: { type: 'object', properties: {} },
  },
];

// POST /token : mint an ephemeral client secret for the OpenAI Realtime
// API. The iOS app uses it to open a WebRTC connection directly to
// OpenAI, so the real API key is never exposed to the client. The key
// expires 10 minutes after minting.
app.post('/token', async (c) => {
  try {
    const res = await fetch('https://api.openai.com/v1/realtime/client_secrets', {
      method: 'POST',
      headers: {
        'authorization': `Bearer ${c.env.OPENAI_API_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        expires_after: { anchor: 'created_at', seconds: 600 },
        session: {
          type: 'realtime',
          model: c.env.OPENAI_REALTIME_MODEL,
          instructions: REALTIME_SYSTEM_PROMPT,
          tools: REALTIME_TOOLS,
          tool_choice: 'auto',
          audio: { output: { voice: 'marin' } },
        },
      }),
    });
    if (!res.ok) {
      // Log the upstream detail server-side only; the raw OpenAI error
      // exposes backend state to anonymous callers.
      console.error('token request failed:', res.status, await res.text());
      return c.json({ error: 'token request failed' }, 502);
    }
    const data = await res.json<{ value: string }>();
    return c.json({ token: data.value, model: c.env.OPENAI_REALTIME_MODEL });
  } catch (err) {
    console.error('token request failed:', err);
    return c.json({ error: 'token request failed' }, 502);
  }
});

// Export the app as the worker's entry point.
export default app;