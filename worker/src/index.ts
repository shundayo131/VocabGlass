//
// VocabGlass Worker (Hono + Anthropic)
//
// POST /generate
//   body:    { "image": "<base64 jpeg>", "mediaType": "image/jpeg" }
//   returns: { "word", "pinyin", "translation", "example" }
//
// receive a base64 photo, ask Claude to name the main object, and
// return a Chinese (Simplified) vocabulary card as JSON.
//

// Imports: Hono for routing, the Anthropic SDK for the Claude call.
import { Hono } from 'hono';
import Anthropic from '@anthropic-ai/sdk';
import { GoogleGenAI, Modality, Behavior } from '@google/genai';

// Bindings: the worker's environment, holding the Anthropic API key secret.
type Bindings = {
  ANTHROPIC_API_KEY: string;  // wrangler secret
  GEMINI_API_KEY: string;     // wrangler secret 
  GEMINI_LIVE_MODEL: string;  // wrangler.toml [vars]
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
// ephemeral token via liveConnectConstraints, not sent by the app: the
// constrained WebSocket method ignores client-side setup for these
// fields, and baking them in also means a leaked token can only start
// a VocabGlass session, not a general-purpose Gemini one.
// The narration rules exist because captures take about 10 seconds
// (photo + card generation) and run in the background: without them
// the model claims "done" early, users ask again, and late results
// derail the conversation. See spec.md, Voice UX design (M9).
const LIVE_SYSTEM_PROMPT = `You are VocabGlass, a voice assistant for a language learning session. The user wears camera glasses and looks at real objects. Keep every reply to one short sentence. When the user asks to capture something, call capture_object right away and tell them it takes about ten seconds. Captures run in the background: keep chatting normally and accept further capture requests while they process. Never say a capture is saved before its final tool result arrives. When a final result arrives, briefly announce the word and its meaning at the next quiet moment. If a tool result reports busy or an error, tell the user briefly and suggest waiting or trying again. When the user wants to stop, call end_session and say goodbye.`;

// NON_BLOCKING lets the model keep talking while the app runs the tool.
// Sync-only models (3.1 today) ignore it.
const LIVE_TOOLS = [{
  functionDeclarations: [
    {
      name: 'capture_object',
      description: 'Capture a photo of what the user is looking at and save it as a vocabulary entry. Call this when the user asks to capture, save, or learn the thing they see.',
      behavior: Behavior.NON_BLOCKING,
    },
    {
      name: 'end_session',
      description: 'End the current learning session. Call this when the user says they are done or asks to end the session.',
      behavior: Behavior.NON_BLOCKING,
    },
  ],
}];

// POST /token : mint a single-use ephemeral token for the Gemini Live API.
// The iOS app connects to Gemini directly with this token
// so the real API key is never exposed to the client.
// The token is locked to our model, prompt, and tools, and a new
// connection must start within 2 minutes of minting.
app.post('/token', async (c) => {
  // Ephemeral tokens only exist on the v1alpha API surface 
  const ai = new GoogleGenAI({ 
    apiKey: c.env.GEMINI_API_KEY, 
    httpOptions: {apiVersion: 'v1alpha'} 
  }); 

  try {
    const now = Date.now();
    const token = await ai.authTokens.create({
      config: {
        uses: 1,
        // Messages allowed for 12 minutes (10 minites + 2 minutes setup/buffer)
        expireTime: new Date(now + 12 * 60_000).toISOString(),
        newSessionExpireTime: new Date(now + 2 * 60_000).toISOString(),
        liveConnectConstraints: {
          model: c.env.GEMINI_LIVE_MODEL,
          config: {
            responseModalities: [Modality.AUDIO],
            systemInstruction: LIVE_SYSTEM_PROMPT,
            tools: LIVE_TOOLS,
            // Debug instrumentation (M13: remove): the app logs what Gemini
            // heard and said, with timestamps, to diagnose latency and echo.
            inputAudioTranscription: {},
            outputAudioTranscription: {},
          },
        },
      }
    });
    return c.json({ token: token.name, model: c.env.GEMINI_LIVE_MODEL });
  } catch (err) {
    // Log the upstream detail server-side only; the raw Google error
    // exposes backend state to anonymous callers.
    console.error('token request failed:', err);
    return c.json({ error: 'token request failed' }, 502);
  }
});

// Export the app as the worker's entry point.
export default app;