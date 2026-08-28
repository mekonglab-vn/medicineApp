#!/bin/sh
set -e

echo "=================================================="
echo "🚀 MedicineApp Node.js Backend Container Starting"
echo "=================================================="

# 1. Execute database migrations
echo "📦 [1/2] Running PostgreSQL database migrations..."
node src/config/migrate.js

# 2. Check and execute drug database seed if needed
if [ "${AUTO_SEED:-true}" = "true" ]; then
  echo "🌱 [2/2] Checking drug database seed..."
  node src/config/seed.js || echo "⚠️ Warning: Drug seed step encountered a non-fatal issue."
else
  echo "⏭️  [2/2] AUTO_SEED=false, skipping seed."
fi

echo "✨ Backend initialization complete. Starting HTTP server on port ${PORT:-3000}..."
exec "$@"
