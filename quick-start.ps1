Write-Host "🚀 Starting PostgreSQL Tuning Demo..." -ForegroundColor Green
docker-compose up -d
Write-Host "⏳ Waiting for PostgreSQL to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
Write-Host "✅ Demo started! Connect with:" -ForegroundColor Green
Write-Host "docker exec -it pg-tuning-demo psql -U demo_user -d tuning_demo" -ForegroundColor Cyan
