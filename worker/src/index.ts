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
import { GoogleGenAI } from '@google/genai';

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

// POST /token : mint a single-use ephemeral token for the Gemini Live API.
// The iOS app connects to Gemini directly with this token
// so the real API key is never exposed to the client. 
// The token is locked to our model and a new connection must start within 2 minutes of minting. 
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
        liveConnectConstraints: { model: c.env.GEMINI_LIVE_MODEL },
      }
    });
    return c.json({ token: token.name, model: c.env.GEMINI_LIVE_MODEL });
  } catch (err) {
    return c.json({ error: `token request failed: ${String(err)}` }, 502);
  }
});

// Export the app as the worker's entry point.
export default app;