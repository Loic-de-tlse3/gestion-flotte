/**
 * OpenTelemetry SDK Bootstrap
 *
 * Ce fichier initialise le SDK Node.js d'OpenTelemetry qui active automatiquement:
 * - Instrumentation des bibliothèques (Express, PostgreSQL, Kafka, etc.)
 * - Export des traces vers le collecteur OTLP
 * - Export des métriques (CPU, mémoire, HTTP, etc.)
 * 
 * DOIT être chargé avant tout autre code: `node --require ./src/observability/telemetry.js src/app.js`
 */

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

// Récupération des variables d'environnement
const serviceName = process.env.OTEL_SERVICE_NAME || 'evenement-service';
const otlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318';
const environment = process.env.NODE_ENV || 'development';

// Configuration des exporteurs OTLP (OpenTelemetry Protocol)
// Ces exporteurs envoient les traces et métriques au collecteur (ex: Prometheus, Jaeger, Loki)
const traceExporter = new OTLPTraceExporter({
  url: `${otlpEndpoint}/v1/traces`, // Endpoint /v1/traces pour les traces gRPC (HTTP bridge)
});

const metricExporter = new OTLPMetricExporter({
  url: `${otlpEndpoint}/v1/metrics`, // Endpoint /v1/metrics pour les métriques
});

// Lecteur de métriques périodique (exporte toutes les 60 secondes)
const metricReader = new PeriodicExportingMetricReader({
  exporter: metricExporter,
  intervalMillis: 60000, // Export périodique chaque 60s
});

// Ressource: descripteur immuable de ce service
// Contient les métadonnées (nom, version, environnement) utilisées par tous les signaux
const resource = Resource.default().merge(
  new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: serviceName,
    [SemanticResourceAttributes.SERVICE_VERSION]: require('../../package.json').version || '1.0.0',
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: environment,
  }),
);

// Initialisation du SDK Node.js avec auto-instrumentation
const sdk = new NodeSDK({
  resource,
  traceExporter,
  metricReader,
  // getNodeAutoInstrumentations() active automatiquement l'instrumentation de:
  // - express (HTTP)
  // - pg (PostgreSQL)
  // - kafkajs (Kafka producer/consumer)
  // - et 30+ autres libs
  instrumentations: [getNodeAutoInstrumentations()],
});

// Démarrage du SDK (activation des hooks automatiques)
sdk.start();

console.log(`[OpenTelemetry] SDK démarré pour ${serviceName}`);
console.log(`[OpenTelemetry] Exporteur OTLP: ${otlpEndpoint}`);

// Graceful shutdown: arrêt propre du SDK
process.on('SIGTERM', async () => {
  try {
    await sdk.shutdown();
    console.log('[OpenTelemetry] SDK arrêté proprement');
  } catch (error) {
    console.error('[OpenTelemetry] Erreur lors de l\'arrêt:', error);
  }
});
