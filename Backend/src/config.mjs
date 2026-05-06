import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');
const defaultDatabasePath = path.join(backendRoot, 'data', 'trai.sqlite');

export function createConfig(env = process.env) {
  const requestedEnvironment = String(env.TRAI_ENVIRONMENT ?? 'production').trim();
  const environment =
    requestedEnvironment === 'production'
      ? 'production'
      : requestedEnvironment === 'localDevelopment' || requestedEnvironment === 'local'
        ? 'localDevelopment'
        : 'staging';

  const requestedDatabaseDriver = String(env.TRAI_DATABASE_DRIVER ?? 'sqlite').trim();
  const databaseDriver =
    requestedDatabaseDriver === 'firestore'
      ? 'firestore'
      : 'sqlite';

  const geminiModel = env.GEMINI_MODEL ?? 'gemini-3-flash-preview';
  const openAIModel = env.OPENAI_MODEL ?? 'gpt-5.4-mini';
  const defaultOpenAITokenPricing = defaultTokenPricingForProvider('openai', openAIModel);
  const defaultGeminiTokenPricing = defaultTokenPricingForProvider('gemini', geminiModel);

  return {
    port: Number.parseInt(env.PORT ?? '8789', 10),
    host: env.HOST ?? '127.0.0.1',
    environment,
    aiProvider: String(env.TRAI_AI_PROVIDER ?? env.AI_PROVIDER ?? 'openai').trim() === 'gemini' ? 'gemini' : 'openai',
    databaseDriver,
    databasePath: env.TRAI_DB_PATH ?? defaultDatabasePath,
    firestoreProjectID: env.FIRESTORE_PROJECT_ID ?? env.GOOGLE_CLOUD_PROJECT ?? env.GCLOUD_PROJECT ?? '',
    firestoreDatabaseID: env.FIRESTORE_DATABASE_ID ?? '(default)',
    geminiApiKey: env.GEMINI_API_KEY ?? '',
    geminiModel,
    openAIApiKey: env.OPENAI_API_KEY ?? '',
    openAIModel,
    allowDevAppleBypass: env.ALLOW_DEV_APPLE_BYPASS === 'true',
    appleIssuer: env.APPLE_EXPECTED_ISSUER ?? 'https://appleid.apple.com',
    appleExpectedAudiences: (env.APPLE_EXPECTED_AUDIENCES ?? env.APPLE_AUDIENCE ?? 'Nadav.Trai')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    appleJWKSURL: env.APPLE_JWKS_URL ?? 'https://appleid.apple.com/auth/keys',
    appleJWKSPath: env.APPLE_JWKS_PATH ?? '',
    appleJWKSCacheTTLSeconds: Number.parseInt(env.APPLE_JWKS_CACHE_TTL_SECONDS ?? '21600', 10),
    appStoreExpectedBundleIDs: (env.APP_STORE_EXPECTED_BUNDLE_IDS ?? 'Nadav.Trai')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    appStoreTrustedRootCertPaths: (env.APP_STORE_ROOT_CERT_PATHS ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    appStoreTrustedRootSubjects: (env.APP_STORE_TRUSTED_ROOT_SUBJECTS ?? 'Apple Root CA - G3,Apple Inc. Root')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
    adminAPIKey: env.TRAI_ADMIN_API_KEY ?? env.ADMIN_API_KEY ?? '',
    aiProxyMaxRequestBytes: Number.parseInt(env.AI_PROXY_MAX_REQUEST_BYTES ?? '6291456', 10),
    aiProxyMaxOutputTokens: Number.parseInt(env.AI_PROXY_MAX_OUTPUT_TOKENS ?? '8192', 10),
    aiProxyMaxContents: Number.parseInt(env.AI_PROXY_MAX_CONTENTS ?? '32', 10),
    aiProxyMaxPartsPerContent: Number.parseInt(env.AI_PROXY_MAX_PARTS_PER_CONTENT ?? '24', 10),
    aiProxyMaxTotalTextChars: Number.parseInt(env.AI_PROXY_MAX_TOTAL_TEXT_CHARS ?? '120000', 10),
    aiProxyMaxInlineImages: Number.parseInt(env.AI_PROXY_MAX_INLINE_IMAGES ?? '4', 10),
    aiProxyMaxInlineImageBytes: Number.parseInt(env.AI_PROXY_MAX_INLINE_IMAGE_BYTES ?? '4194304', 10),
    aiProxyMaxFunctionDeclarations: Number.parseInt(env.AI_PROXY_MAX_FUNCTION_DECLARATIONS ?? '24', 10),
    aiProxyMaxConcurrentRequestsPerUser: Number.parseInt(env.AI_PROXY_MAX_CONCURRENT_REQUESTS_PER_USER ?? '3', 10),
    aiProxyMaxRequestsPerMinute: Number.parseInt(env.AI_PROXY_MAX_REQUESTS_PER_MINUTE ?? '20', 10),
    aiProxyMaxUnitsPerTenMinutes: Number.parseInt(env.AI_PROXY_MAX_UNITS_PER_TEN_MINUTES ?? '150', 10),
    aiProxyMaxUnitsPer24Hours: Number.parseInt(env.AI_PROXY_MAX_UNITS_PER_24_HOURS ?? '150', 10),
    aiProxyMaxUnitsPer7Days: Number.parseInt(env.AI_PROXY_MAX_UNITS_PER_7_DAYS ?? '500', 10),
    aiTokenPricing: {
      openai: {
        inputUSDPer1M: parseOptionalNumber(env.OPENAI_INPUT_USD_PER_1M_TOKENS) ?? defaultOpenAITokenPricing?.inputUSDPer1M ?? null,
        outputUSDPer1M: parseOptionalNumber(env.OPENAI_OUTPUT_USD_PER_1M_TOKENS) ?? defaultOpenAITokenPricing?.outputUSDPer1M ?? null,
        cachedInputUSDPer1M: parseOptionalNumber(env.OPENAI_CACHED_INPUT_USD_PER_1M_TOKENS) ?? defaultOpenAITokenPricing?.cachedInputUSDPer1M ?? null
      },
      gemini: {
        inputUSDPer1M: parseOptionalNumber(env.GEMINI_INPUT_USD_PER_1M_TOKENS) ?? defaultGeminiTokenPricing?.inputUSDPer1M ?? null,
        outputUSDPer1M: parseOptionalNumber(env.GEMINI_OUTPUT_USD_PER_1M_TOKENS) ?? defaultGeminiTokenPricing?.outputUSDPer1M ?? null,
        cachedInputUSDPer1M: parseOptionalNumber(env.GEMINI_CACHED_INPUT_USD_PER_1M_TOKENS) ?? defaultGeminiTokenPricing?.cachedInputUSDPer1M ?? null
      }
    }
  };
}

export function validateConfig(config) {
  if (config.environment === 'production' && config.allowDevAppleBypass) {
    throw new Error('ALLOW_DEV_APPLE_BYPASS must never be enabled in production.');
  }

  if (config.aiProvider === 'openai' && !config.openAIApiKey) {
    throw new Error('OPENAI_API_KEY must be configured when TRAI_AI_PROVIDER=openai.');
  }

  if (config.appleExpectedAudiences.length === 0) {
    throw new Error('APPLE_EXPECTED_AUDIENCES must include at least one bundle or service identifier.');
  }
}

export function loadTrustedAppStoreRoots(config) {
  return config.appStoreTrustedRootCertPaths.flatMap((filePath) => {
    try {
      const certificate = new crypto.X509Certificate(fs.readFileSync(filePath));
      return [certificate];
    } catch {
      throw new Error(`Failed to read trusted App Store root certificate at ${filePath}`);
    }
  });
}

function parseOptionalNumber(value) {
  if (value == null || String(value).trim() === '') {
    return null;
  }

  const parsed = Number.parseFloat(String(value));
  return Number.isFinite(parsed) ? parsed : null;
}

function defaultTokenPricingForProvider(provider, model) {
  const normalizedProvider = String(provider ?? '').trim().toLowerCase();
  const normalizedModel = String(model ?? '').trim().toLowerCase();

  if (normalizedProvider === 'openai') {
    if (normalizedModel.startsWith('gpt-5.4-mini')) {
      return {
        inputUSDPer1M: 0.75,
        outputUSDPer1M: 4.5,
        cachedInputUSDPer1M: 0.075
      };
    }

    if (normalizedModel.startsWith('gpt-5.4')) {
      return {
        inputUSDPer1M: 2.5,
        outputUSDPer1M: 15,
        cachedInputUSDPer1M: 0.25
      };
    }

    return null;
  }

  if (normalizedProvider === 'gemini') {
    if (normalizedModel.startsWith('gemini-3-flash-preview')) {
      return {
        inputUSDPer1M: 0.5,
        outputUSDPer1M: 3,
        cachedInputUSDPer1M: 0.05
      };
    }

    return null;
  }

  return null;
}

export const PLAN_LIMITS = {
  developer: null,
  free: 0,
  pro: 1200
};

export const PLAN_PRICING = {
  free: {
    monthlyPriceUSD: 0,
    priceDisplay: '$0.00'
  },
  pro: {
    monthlyPriceUSD: 3.99,
    priceDisplay: '$3.99'
  }
};

export const UNIT_ECONOMICS = {
  estimatedUSDPerUnit: 1 / PLAN_LIMITS.pro,
  targetAveragePaidAICostUSD: 1.0,
  softBufferPaidAICostUSD: 1.5,
  hardCeilingPaidAICostUSD: 2.25,
  smallBusinessNetRevenueShare: 0.85,
  standardYearOneNetRevenueShare: 0.70
};

export const FEATURE_COSTS = {
  coachChat: 1,
  agentCoachChat: 3,
  agentToolFollowUp: 1,
  foodPhotoAnalysis: 6,
  foodRefinement: 2,
  nutritionPlanGeneration: 8,
  nutritionPlanRefinement: 4,
  workoutPlanGeneration: 8,
  workoutPlanRefinement: 4,
  exerciseAnalysis: 2,
  exercisePhotoAnalysis: 5,
  memoryExtraction: 2,
  nutritionAdvice: 2
};

export const PRODUCT_DEFINITIONS = [
  {
    id: 'trai.pro.monthly',
    plan: 'pro',
    displayName: 'Trai Pro',
    priceDisplay: PLAN_PRICING.pro.priceDisplay,
    billingPeriodLabel: 'per month',
    monthlyAIUnits: PLAN_LIMITS.pro,
    isPrimaryOffer: true,
    marketingPoints: [
      'Coach chat',
      'Food photo analysis',
      'Personalized nutrition and workout plans'
    ]
  }
];
