#Requires -Version 5.1

Write-Error @"
This source-build Windows installer has been retired.

Supported personal self-hosted paths now use the published OmniLux image instead:

1. Use Docker Desktop or another local Docker runtime.
2. Copy docker\docker-compose.example.yml and run:
   docker compose pull
   docker compose up -d

This repo no longer supports building OmniLux from source or managing a native
Windows service from omnilux-deploy.
"@

exit 1
