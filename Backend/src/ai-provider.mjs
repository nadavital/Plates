import { URLSearchParams } from 'node:url';

export function createAIProvider(config, HttpError) {
  switch (config.aiProvider) {
    case 'gemini':
      return createGeminiProvider(config, HttpError);
    case 'openai':
      return createOpenAIProvider(config, HttpError);
    default:
      throw new Error(`Unsupported TRAI_AI_PROVIDER value: ${config.aiProvider}`);
  }
}

function createGeminiProvider(config, HttpError) {
  return {
    name: 'gemini',
    model: config.geminiModel,
    isConfigured() {
      return Boolean(config.geminiApiKey);
    },
    async execute(requestBody, { streaming }) {
      if (!config.geminiApiKey) {
        throw new HttpError(503, {
          error: 'gemini_not_configured',
          message: 'GEMINI_API_KEY is required for AI proxy requests.'
        });
      }

      const action = streaming ? 'streamGenerateContent' : 'generateContent';
      const query = new URLSearchParams({ key: config.geminiApiKey });
      if (streaming) {
        query.set('alt', 'sse');
      }

      const upstreamURL = `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiModel}:${action}?${query.toString()}`;
      const upstreamResponse = await fetch(upstreamURL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      if (!upstreamResponse.ok) {
        const errorText = await upstreamResponse.text();
        throw new HttpError(upstreamResponse.status, {
          error: 'gemini_error',
          message: errorText || 'Gemini proxy request failed.'
        });
      }

      return upstreamResponse;
    }
  };
}

function createOpenAIProvider(config, HttpError) {
  return {
    name: 'openai',
    model: config.openAIModel,
    isConfigured() {
      return Boolean(config.openAIApiKey);
    },
    async execute() {
      if (!config.openAIApiKey) {
        throw new HttpError(503, {
          error: 'openai_not_configured',
          message: 'OPENAI_API_KEY is required when TRAI_AI_PROVIDER=openai.'
        });
      }

      throw new HttpError(501, {
        error: 'openai_not_implemented',
        message: 'OpenAI provider wiring has not been implemented yet.'
      });
    }
  };
}
