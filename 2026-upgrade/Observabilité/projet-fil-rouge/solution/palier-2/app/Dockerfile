FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PROMETHEUS_DISABLE_CREATED_SERIES=True

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY *.py .

# Utilisateur non-root : un service observé n'a aucune raison d'être root
RUN useradd --uid 10001 --no-create-home marche
USER marche

# Le service lancé est choisi par la commande du docker-compose (python gateway.py, etc.)
CMD ["python", "gateway.py"]
