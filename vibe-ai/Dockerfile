FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    gcc \
    g++ \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# tbb has no ARM64 wheel; install it if available (x86), skip if not (Apple Silicon)
RUN pip install --no-cache-dir tbb 2>/dev/null || true && \
    grep -v '^tbb' requirements.txt > /tmp/requirements_notbb.txt && \
    pip install --no-cache-dir -r /tmp/requirements_notbb.txt

COPY . .

EXPOSE 9017

ENV PYTHONPATH=/app/src
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "9017"]
