#Requires -Version 5.1

Write-Error @"
This legacy Windows installer has been retired.

Supported self-hosted install paths now use the published OmniLux runtime:

1. Use Docker Desktop or another local Docker runtime.
2. Copy docker\docker-compose.example.yml and run:
   docker compose pull
   docker compose up -d

Use the published installer or Compose bundle for self-hosted installs.
"@

exit 1
