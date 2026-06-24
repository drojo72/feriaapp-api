#!/bin/bash
set -e

echo "=== FeriaApp API Setup ==="

if [ ! -d "venv" ]; then
    echo "Creando virtual environment..."
    python3 -m venv venv
fi

echo "Activando venv..."
source venv/bin/activate

pip install --upgrade pip
echo "Instalando dependencias..."
pip install -r requirements.txt

if [ ! -f ".env" ]; then
    echo "Creando .env desde template..."
    cp .env.example .env
    echo "⚠️  EDITA .env con tus credenciales de Neon"
fi

echo ""
echo "✅ Setup completo"
echo "Activa: source venv/bin/activate"
echo "Correr: uvicorn feriaapp_api.main:app --reload --host 0.0.0.0 --port 8000"
