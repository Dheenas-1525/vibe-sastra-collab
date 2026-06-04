# ViBe — College DGX Server Deployment Guide

> **Who is this guide for?**
> This guide is written for deploying ViBe on a **college DGX KVM virtual machine (VM)** running Linux.
> It assumes you have no prior server or Linux experience.
> Every command is explained. Every step is shown in full.
> If you follow this guide from top to bottom, ViBe will be running with a domain and HTTPS.

---

## Table of Contents

1. [What Are We Deploying?](#1-what-are-we-deploying)
2. [System Requirements](#2-system-requirements)
3. [Before You Start — Collect These Things](#3-before-you-start--collect-these-things)
4. [Phase 1 — Connect to the Server](#phase-1--connect-to-the-server)
5. [Phase 2 — Prepare the Server](#phase-2--prepare-the-server)
6. [Phase 3 — Create External Service Accounts](#phase-3--create-external-service-accounts)
7. [Phase 4 — Clone the Code](#phase-4--clone-the-code)
8. [Phase 5 — Configure ViBe](#phase-5--configure-vibe)
9. [Phase 6 — Set Up AI (Ollama in Docker, No GPU)](#phase-6--set-up-ai-ollama-in-docker-no-gpu)
10. [Phase 7 — Build and Launch ViBe](#phase-7--build-and-launch-vibe)
11. [Phase 8 — Set Up Domain and HTTPS](#phase-8--set-up-domain-and-https)
12. [Phase 9 — Keep Everything Running After Reboot](#phase-9--keep-everything-running-after-reboot)
13. [Phase 10 — GPU Upgrade (When Access Is Granted)](#phase-10--gpu-upgrade-when-access-is-granted)
14. [Maintenance and Updates](#maintenance-and-updates)
15. [Troubleshooting](#troubleshooting)
16. [Quick Command Reference](#quick-command-reference)

---

## 1. What Are We Deploying?

ViBe is an educational platform. It has multiple parts that all run together:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DGX KVM VM (Your Server)                     │
│                                                                       │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐   │
│  │   Frontend   │    │   Backend    │    │    vibe-ai Server    │   │
│  │  React app   │───▶│  Node.js API │◀──▶│  Python + Whisper   │   │
│  │  Port 3000   │    │  Port 8080   │    │  Port 9017           │   │
│  └──────────────┘    └──────┬───────┘    └──────────────────────┘   │
│                              │                        │               │
│                  ┌───────────┤           ┌────────────┘              │
│                  │           │           ▼                            │
│  ┌────────────┐  │  ┌────────▼──────┐  ┌──────────────────────┐     │
│  │  LiteLLM  │  │  │ fake-gcs      │  │   Ollama             │     │
│  │  Port 4000 │◀─┘  │ Port 4443    │  │   Port 11434          │     │
│  └────────────┘     └───────────────┘  │   (AI model server)  │     │
│        │                               └──────────────────────┘     │
│        ▼                                                              │
│   Ollama (same)                                                       │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Nginx (reverse proxy + SSL termination)  — Port 80 / 443   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
           │
           │  External cloud services (free accounts)
           ▼
    MongoDB Atlas (database) + Firebase (login)
```

**What each part does:**

| Container | What it does |
|-----------|-------------|
| `vibe-frontend` | The website users see (React app served by Nginx) |
| `vibe-backend` | The API server (data, logic, authentication) |
| `vibe-aiserver` | Video pipeline: audio extraction → Whisper transcription → segmentation → questions |
| `vibe-ollama` | AI model server — generates quiz questions (replaces LM Studio) |
| `vibe-litellm` | Translates between ViBe's Anthropic SDK calls and Ollama's format |
| `vibe-fake-gcs` | Local Google Cloud Storage emulator — file sharing between backend and vibe-ai |

**External services (cloud, free accounts):**

| Service | Purpose |
|---------|---------|
| MongoDB Atlas | Database — stores all courses, users, quizzes |
| Firebase | User authentication — handles login and sign-up |
| Google reCAPTCHA | Spam protection on sign-up form |

---

## 2. System Requirements

### For the DGX KVM VM

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8 cores |
| RAM | 16 GB | 32 GB |
| Disk Space | 60 GB | 100 GB |
| Operating System | Ubuntu 20.04 LTS | Ubuntu 22.04 LTS |
| Network | Public IP or domain | Domain with SSL |
| GPU | Not required initially | NVIDIA GPU (when approved) |

> **Why 16 GB RAM?**
> Without a GPU, the AI model (Ollama) runs on CPU and needs ~4–8 GB RAM just for the model.
> ViBe's other services need ~2–4 GB. Whisper transcription needs ~2 GB.
> Total: 8–14 GB active. 16 GB gives breathing room.

### Disk Space Breakdown

| What uses space | Size |
|----------------|------|
| Ubuntu OS | ~5 GB |
| Docker + images | ~10 GB |
| Ollama AI model (small 3B) | ~2 GB |
| Ollama AI model (8B, better quality) | ~5 GB |
| Whisper audio model | ~0.5 GB |
| Application data (GCS files, logs) | ~5–20 GB |
| **Total minimum** | **~30 GB** |

---

## 3. Before You Start — Collect These Things

Ask your college IT department for:
- [ ] The **IP address** of your KVM VM (example: `10.0.0.25` or `192.168.1.50`)
- [ ] Your **SSH username** and **password** (or SSH key file)
- [ ] Whether the VM has a **public IP** or is behind a NAT/firewall
- [ ] A **domain name** pointing to the server (example: `vibe.yourcollege.edu`)
  - If not available yet, you can use the IP address first and add a domain later
- [ ] Which **ports are open** on the firewall (you need: 22, 80, 443, 8080, 3000)

---

## Phase 1 — Connect to the Server

### What is SSH?

SSH (Secure Shell) lets you control the server from your own computer by typing commands.
Think of it as a remote keyboard for the server — your computer sends commands,
the server runs them and sends back the output.

### Step 1.1 — Open a Terminal on Your Computer

**macOS:** Press `Cmd + Space`, type `Terminal`, press Enter.

**Windows:** Press `Win + R`, type `cmd`, press Enter.
Or install **Windows Terminal** from the Microsoft Store (recommended).

### Step 1.2 — Connect to the Server

Type this command in your terminal (replace the values with what IT gave you):

```bash
ssh your_username@SERVER_IP_ADDRESS
```

**Example:**
```bash
ssh vibeadmin@10.0.0.25
```

When you press Enter:
1. You may see a message like `The authenticity of host '10.0.0.25' can't be established... Are you sure you want to continue?` — type `yes` and press Enter
2. Enter your password when asked (the password won't show as you type — this is normal)
3. You are now inside the server. Your prompt changes to something like `vibeadmin@dgx-vm:~$`

> **From now on, all commands in this guide are typed inside this SSH session.**

### Step 1.3 — Check the Server

```bash
# What operating system is running?
cat /etc/os-release | grep PRETTY_NAME

# How much RAM does the server have?
free -h

# How much disk space?
df -h /

# How many CPU cores?
nproc
```

---

## Phase 2 — Prepare the Server

### Step 2.1 — Update the System

This downloads and installs all the latest security fixes. Always do this on a fresh server.

```bash
sudo apt update && sudo apt upgrade -y
```

> `sudo` means "run as administrator". It may ask for your password.
> `apt` is Ubuntu's package manager (like an app store for the terminal).
> This may take 2–5 minutes.

### Step 2.2 — Install Essential Tools

```bash
sudo apt install -y \
    git \
    curl \
    wget \
    nano \
    htop \
    ufw \
    ca-certificates \
    gnupg \
    lsb-release
```

**What each tool does:**

| Tool | Purpose |
|------|---------|
| `git` | Downloads code from GitHub |
| `curl` | Downloads files from the internet |
| `wget` | Another way to download files |
| `nano` | Simple text editor in the terminal |
| `htop` | Shows what is running and how much RAM/CPU is used |
| `ufw` | Firewall (controls which network connections are allowed) |

### Step 2.3 — Configure the Firewall

```bash
# Allow SSH so you can still connect after enabling the firewall
sudo ufw allow ssh

# Allow HTTP (port 80) — required for the website and SSL certificate
sudo ufw allow 80/tcp

# Allow HTTPS (port 443) — required for secure HTTPS connections
sudo ufw allow 443/tcp

# Allow the backend API port (needed while setting up, before domain is configured)
sudo ufw allow 8080/tcp

# Allow the frontend port (needed while setting up)
sudo ufw allow 3000/tcp

# Turn on the firewall
sudo ufw enable

# Confirm the rules
sudo ufw status
```

Expected output:
```
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere
443/tcp                    ALLOW       Anywhere
8080/tcp                   ALLOW       Anywhere
3000/tcp                   ALLOW       Anywhere
```

### Step 2.4 — Install Docker

Docker is the software that packages and runs ViBe in isolated "containers".
Think of containers as separate boxes, each with their own software, that all run on the same server.

```bash
# Step 1: Remove any old versions of Docker (safe to run even if Docker was never installed)
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Step 2: Add Docker's official signing key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Step 3: Add Docker's software repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 4: Install Docker
sudo apt update
sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Step 5: Allow your user to run Docker without typing sudo every time
sudo usermod -aG docker $USER

# Step 6: Apply the group change without logging out
newgrp docker

# Step 7: Verify Docker works
docker --version
docker compose version
```

Expected output:
```
Docker version 26.x.x, build xxxxxxx
Docker Compose version v2.x.x
```

### Step 2.5 — Start Docker Automatically on Boot

```bash
sudo systemctl enable docker
sudo systemctl start docker

# Confirm Docker is running
sudo systemctl status docker
```

Look for `Active: active (running)` in green.

---

## Phase 3 — Create External Service Accounts

You need accounts at two free services. These run in the cloud — not on your server.

---

### 3.1 MongoDB Atlas — Database (Free)

MongoDB Atlas is where all ViBe data is stored: users, courses, quizzes, enrollments.

#### Create Account

1. Go to [https://www.mongodb.com/atlas](https://www.mongodb.com/atlas)
2. Click **Try Free** → sign up with email → verify email
3. When asked "What are you building?", choose anything and click **Finish**

#### Create a Free Database Cluster

1. Click **Build a Database**
2. Choose **M0 — Free** tier
3. Select cloud provider: **AWS** (any region near India works — e.g., Mumbai)
4. Name it: `vibe-cluster`
5. Click **Create Deployment**

#### Create a Database User

A popup appears. Fill in:
- **Username**: `vibeadmin`
- **Password**: create a strong password and write it down (example: `V!be@2024Secure`)
- Click **Create Database User**

#### Allow Network Access

1. Click **Add My Current IP Address** — this adds your IP
2. Also click **Add IP Address** and add `0.0.0.0/0` with description `Server access`
   > This allows your college server to connect. You can restrict this later to your server's IP only.
3. Click **Finish and Close**

#### Get the Connection String

1. On the Atlas dashboard, click **Connect** on your cluster
2. Click **Drivers**
3. Select **Node.js**
4. Copy the connection string — it looks like:
   ```
   mongodb+srv://vibeadmin:<password>@vibe-cluster.abc123.mongodb.net/?retryWrites=true&w=majority
   ```
5. Replace `<password>` with the actual password you created
6. **Save this string** — this is your `DB_URL`

---

### 3.2 Firebase — User Authentication (Free)

Firebase handles login and sign-up for teachers and students.

#### Create a Firebase Project

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Click **Add Project**
3. Name it: `vibe-college` (use your college name)
4. Disable Google Analytics (click the toggle, then Continue)
5. Click **Create Project** → wait → click **Continue**

#### Enable Email/Password Login

1. Left sidebar → click **Authentication**
2. Click **Get Started**
3. Click **Email/Password** under Sign-in providers
4. Toggle **Enable** → ON
5. Click **Save**

#### Register a Web App

1. Click the home icon (Firebase project overview)
2. Click the **Web** icon `</>`
3. App nickname: `vibe-web`
4. Do NOT check "Firebase Hosting"
5. Click **Register App**
6. You will see a JavaScript code block. **Copy all 7 values** from `firebaseConfig`:

```
apiKey              → VITE_FIREBASE_API_KEY
authDomain          → VITE_FIREBASE_AUTH_DOMAIN
projectId           → VITE_FIREBASE_PROJECT_ID
storageBucket       → VITE_FIREBASE_STORAGE_BUCKET
messagingSenderId   → VITE_FIREBASE_MESSAGING_SENDER_ID
appId               → VITE_FIREBASE_APP_ID
measurementId       → VITE_FIREBASE_MEASUREMENT_ID
```

7. Click **Continue to Console**

#### Get the Admin Service Account Key

This file lets ViBe's backend verify that login tokens are real.

1. Click the gear icon (⚙️) next to "Project Overview" → **Project Settings**
2. Click the **Service accounts** tab
3. Click **Generate new private key** → click **Generate key** to confirm
4. A JSON file downloads. **Keep this file safe — it contains a private key.**
5. Rename the file to `firebase-service-account.json`

You will upload this file to the server in Phase 5.

#### Add Your Domain to Firebase Authorized Domains

1. In Firebase → Authentication → Settings → **Authorized Domains**
2. Click **Add Domain**
3. Add your server's IP address (example: `10.0.0.25`)
4. Add your domain name if you have one (example: `vibe.yourcollege.edu`)
5. Click **Add**

---

### 3.3 Google reCAPTCHA (Anti-spam, Free)

1. Go to [https://www.google.com/recaptcha/admin/create](https://www.google.com/recaptcha/admin/create)
2. Sign in with a Google account
3. Fill in:
   - **Label**: `ViBe College`
   - **reCAPTCHA type**: Select **reCAPTCHA v2** → **"I'm not a robot" Checkbox**
   - **Domains**: Add your server IP or domain (example: `vibe.yourcollege.edu`)
   - Also add `localhost` for testing
4. Accept Terms → click **Submit**
5. You get two keys:
   - **Site Key** (public) → write this down as `VITE_RECAPTCHA_SITE_KEY`
   - **Secret Key** (private) → write this down as `RECAPTCHA_SECRET_KEY`

---

## Phase 4 — Clone the Code

Now download ViBe's source code onto the server.

```bash
# Go to your home directory
cd ~

# Create a folder for ViBe
mkdir vibe-deploy
cd vibe-deploy

# Download the main ViBe repo
git clone https://github.com/continuousactivelearning/vibe.git

# Download the vibe-ai repo (the AI video pipeline)
git clone https://github.com/vicharanashala/vibe-ai.git

# Check both folders exist
ls
# Expected output: vibe/  vibe-ai/
```

Your directory structure:
```
~/vibe-deploy/
├── vibe/        ← main ViBe (frontend + backend + docker-compose)
└── vibe-ai/     ← AI pipeline server (Python)
```

---

## Phase 5 — Configure ViBe

### Step 5.1 — Upload the Firebase Service Account File

On your **own computer** (not the server), open a new terminal window and run:

```bash
# Replace the path and server details with yours
scp ~/Downloads/firebase-service-account.json your_username@SERVER_IP:~/vibe-deploy/vibe/
```

**Example:**
```bash
scp ~/Downloads/firebase-service-account.json vibeadmin@10.0.0.25:~/vibe-deploy/vibe/
```

Back on the **server**, confirm the file arrived:
```bash
ls ~/vibe-deploy/vibe/firebase-service-account.json
```

### Step 5.2 — Create the Backend Configuration File

```bash
cd ~/vibe-deploy/vibe
nano backend.env
```

Paste the following template and fill in every value marked with `YOUR_...`:

```env
# ── Server ────────────────────────────────────────────────────────────
NODE_ENV=production
APP_PORT=8080

# Replace SERVER_IP_OR_DOMAIN with your server's IP or domain name
APP_URL=http://SERVER_IP_OR_DOMAIN:8080
APP_ORIGINS=http://SERVER_IP_OR_DOMAIN:3000,http://SERVER_IP_OR_DOMAIN
APP_ROUTE_PREFIX=/api
APP_MODULE=all
FRONTEND_URL=http://SERVER_IP_OR_DOMAIN:3000/teacher

ADMIN_PASSWORD=YOUR_STRONG_ADMIN_PASSWORD

# ── Database ──────────────────────────────────────────────────────────
DB_URL=mongodb+srv://vibeadmin:YOUR_PASSWORD@vibe-cluster.abc123.mongodb.net/?retryWrites=true&w=majority
DB_NAME=vibe

# ── Firebase Admin SDK ────────────────────────────────────────────────
GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json
FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY
FIREBASE_STORAGE_BUCKET=YOUR_FIREBASE_PROJECT_ID.appspot.com
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@YOUR_PROJECT_ID.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_KEY_HERE\n-----END PRIVATE KEY-----\n"

# ── AI / LLM (via LiteLLM proxy → Ollama) ────────────────────────────
ANTHROPIC_MODEL=claude-sonnet-4-20250514
ANTHROPIC_CRED=local-llm-no-key-needed
ANTHROPIC_BASE_URL=http://litellm:4000

# ── AI Pipeline Server ────────────────────────────────────────────────
AI_SERVER_IP=vibe-aiserver
AI_SERVER_PORT=9017

# ── reCAPTCHA ─────────────────────────────────────────────────────────
RECAPTCHA_SECRET_KEY=YOUR_RECAPTCHA_SECRET_KEY
IS_RECAPTCHA_ENABLED=true

# ── Optional ──────────────────────────────────────────────────────────
SENTRY_DSN=
ENABLE_DB_BACKUP=false
ENABLE_HP_JOB=true
```

> **How to fill in `FIREBASE_CLIENT_EMAIL` and `FIREBASE_PRIVATE_KEY`:**
> Open `firebase-service-account.json` in nano: `nano firebase-service-account.json`
> Find the `client_email` and `private_key` fields and copy their values.
> The private key must stay on one line — replace actual newlines with `\n`.

Save and exit: `Ctrl + X` → `Y` → `Enter`

### Step 5.3 — Create the Frontend Configuration File

```bash
nano ~/vibe-deploy/vibe/frontend/.env
```

Paste and fill in:

```env
# Firebase web SDK config (from Firebase Console → Project Settings → Your Apps)
VITE_FIREBASE_API_KEY=YOUR_FIREBASE_API_KEY
VITE_FIREBASE_AUTH_DOMAIN=YOUR_PROJECT_ID.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
VITE_FIREBASE_STORAGE_BUCKET=YOUR_PROJECT_ID.appspot.com
VITE_FIREBASE_MESSAGING_SENDER_ID=YOUR_SENDER_ID
VITE_FIREBASE_APP_ID=YOUR_APP_ID
VITE_FIREBASE_MEASUREMENT_ID=YOUR_MEASUREMENT_ID

# API URL — use /api so nginx proxies it (DO NOT change this)
VITE_BASE_URL=/api

# reCAPTCHA site key (the PUBLIC key)
VITE_RECAPTCHA_SITE_KEY=YOUR_RECAPTCHA_SITE_KEY
VITE_IS_RECAPTCHA_ENABLED=true
```

Save and exit.

### Step 5.4 — Create the vibe-ai Configuration File

```bash
nano ~/vibe-deploy/vibe-ai/.env
```

Paste:

```env
# Webhook secret — must match the value vibe-backend expects
WEBHOOK_SECRET=vibe-college-secret-change-this

# URL vibe-ai calls to report progress back to the backend
WEBHOOK_URL=http://vibe-backend:8080/api/genAI/webhook

# LLM API — points to Ollama container
VLLM_BASE_URL=http://ollama:11434/v1

# GCS (local emulator — no real GCP needed)
GCLOUD_PROJECT=vibe-college
GCLOUD_BUCKET_NAME=vibe-aiserver-data
GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json
STORAGE_EMULATOR_HOST=http://fake-gcs:4443

PORT=9017
```

Save and exit.

> **Important:** Also add `WEBHOOK_SECRET` to `backend.env`:
> ```bash
> echo "WEBHOOK_SECRET=vibe-college-secret-change-this" >> ~/vibe-deploy/vibe/backend.env
> ```

### Step 5.5 — Create the LiteLLM Config File

LiteLLM is a translator between ViBe's Anthropic SDK and Ollama's API format.

```bash
nano ~/vibe-deploy/vibe/litellm_config.yaml
```

Paste:

```yaml
model_list:
  - model_name: claude-sonnet-4-20250514
    litellm_params:
      model: openai/ollama-model
      api_base: http://ollama:11434/v1
      api_key: not-needed

litellm_settings:
  drop_params: true
  set_verbose: false
```

Save and exit.

### Step 5.6 — Create GCS Data Directory

```bash
mkdir -p ~/vibe-deploy/vibe/gcs-data/vibe-aiserver-data
```

### Step 5.7 — Create the vibe-ai Dockerfile

The vibe-ai repo doesn't include a Dockerfile. Create one:

```bash
nano ~/vibe-deploy/vibe-ai/Dockerfile
```

Paste:

```dockerfile
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
RUN pip install --no-cache-dir tbb 2>/dev/null || true && \
    grep -v '^tbb' requirements.txt > /tmp/requirements_notbb.txt && \
    pip install --no-cache-dir -r /tmp/requirements_notbb.txt

COPY . .

EXPOSE 9017

ENV PYTHONPATH=/app/src
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "9017"]
```

Save and exit.

### Step 5.8 — Apply Source Code Fixes to vibe-ai

The original vibe-ai code has bugs that prevent it from running. Apply the fixes:

```bash
cd ~/vibe-deploy/vibe-ai
```

**Fix 1: Add missing packages to requirements.txt**
```bash
echo "langchain-openai>=0.3.0" >> requirements.txt
echo "langchain-core>=0.3.0" >> requirements.txt
```

**Fix 2: Cap Whisper model size (prevents 10GB download filling the disk)**
```bash
# This command adds the safety cap to transcription.py
python3 - << 'PYTHON'
import re

with open('src/services/transcription.py', 'r') as f:
    content = f.read()

# Add model size cap after the try: block start
old = '        try:\n            await self._load_model(effective_size)'
if old not in content:
    # Try inserting before _load_model call
    content = content.replace(
        '            await self._load_model(model_size)',
        '''            safe_sizes = {'tiny', 'base', 'small'}
            effective_size = model_size if model_size in safe_sizes else 'small'
            if effective_size != model_size:
                print(f"Model size '{model_size}' capped to 'small' for local deployment")
            await self._load_model(effective_size)'''
    )
    with open('src/services/transcription.py', 'w') as f:
        f.write(content)
    print("transcription.py patched successfully")
else:
    print("transcription.py already patched")
PYTHON
```

**Fix 3: Fix broken LangChain imports in question_generation.py**
```bash
python3 - << 'PYTHON'
import re

filepath = 'src/services/question_generation.py'
with open(filepath, 'r') as f:
    content = f.read()

if 'create_agent' in content:
    # Replace broken imports
    content = content.replace(
        'from langchain.agents import create_agent\nfrom langchain.agents.structured_output import ToolStrategy',
        'from langchain_core.messages import SystemMessage, HumanMessage\nimport re'
    )
    # Save the file
    with open(filepath, 'w') as f:
        f.write(content)
    print("Imports fixed. Now fix _build_agent manually — see vibe-ai-source-changes.md")
else:
    print("Imports already fixed or file has different content")
PYTHON
```

> **Note:** If the automatic patches don't apply cleanly (files may differ from the version used in development), apply the changes manually by following the exact diffs in `vibe/vibe-ai-source-changes.md`.

**Fix 4: Add max_tokens to question_generation.py**
```bash
sed -i 's/timeout=300,/timeout=300,\n            max_tokens=4096,/g' \
    src/services/question_generation.py
```

---

## Phase 6 — Set Up AI (Ollama in Docker, No GPU)

Since the DGX server does not have GPU access yet, AI runs on CPU using **Ollama**.
Ollama is an open-source tool that runs AI models and exposes the same API format as OpenAI.

### What Ollama Replaces

| Before | Now |
|--------|-----|
| LM Studio (Mac desktop app) | Ollama (Docker container on server) |
| Port 1234 on localhost | Port 11434 in `vibe-ollama` container |
| Manual model load via GUI | Auto-loaded via `OLLAMA_PRELOAD_MODEL` env var |

### Step 6.1 — Update docker-compose.yml to Add Ollama

Open the docker-compose.yml:

```bash
nano ~/vibe-deploy/vibe/docker-compose.yml
```

The full `docker-compose.yml` should look like this (copy and replace the entire file):

```yaml
services:

  # ── Backend API ──────────────────────────────────────────────────────
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: vibe-backend
    command:
      - sh
      - -c
      - >
        if [ -n "$$TAILSCALE_AUTHKEY" ]; then
          /app/tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
          /app/tailscale up --auth-key="$$TAILSCALE_AUTHKEY" --hostname=gcp;
        fi;
        exec dumb-init node build/index.js
    volumes:
      - ./firebase-service-account.json:/app/firebase-service-account.json:ro
    env_file:
      - ./backend.env
    ports:
      - "8080:8080"
    restart: unless-stopped
    depends_on:
      - fake-gcs
      - litellm
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    networks:
      - vibe-network

  # ── Frontend ─────────────────────────────────────────────────────────
  frontend:
    build:
      context: .
      dockerfile: frontend/Dockerfile
      shm_size: '2gb'
    container_name: vibe-frontend
    ports:
      - "3000:80"
    restart: unless-stopped
    depends_on:
      backend:
        condition: service_healthy
    networks:
      - vibe-network

  # ── vibe-ai Server ───────────────────────────────────────────────────
  vibe-aiserver:
    build:
      context: ../vibe-ai
      dockerfile: Dockerfile
    container_name: vibe-aiserver
    env_file:
      - ../vibe-ai/.env
    volumes:
      - ./firebase-service-account.json:/app/firebase-service-account.json:ro
    ports:
      - "9017:9017"
    restart: unless-stopped
    depends_on:
      - fake-gcs
      - ollama
    networks:
      - vibe-network

  # ── Ollama — AI Model Server (CPU mode, no GPU required) ─────────────
  ollama:
    image: ollama/ollama
    container_name: vibe-ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
    environment:
      # Preload model on startup so first request is not slow
      - OLLAMA_PRELOAD_MODEL=qwen2.5:3b
    networks:
      - vibe-network

  # ── LiteLLM Proxy — translates Anthropic API → Ollama API ────────────
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: vibe-litellm
    volumes:
      - ./litellm_config.yaml:/app/config.yaml
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    ports:
      - "4000:4000"
    restart: unless-stopped
    depends_on:
      - ollama
    networks:
      - vibe-network

  # ── Local GCS Emulator — no real Google Cloud account needed ──────────
  fake-gcs:
    image: fsouza/fake-gcs-server
    container_name: vibe-fake-gcs
    volumes:
      - ./gcs-data:/data
    command: >
      -scheme http
      -port 4443
      -backend filesystem
      -filesystem-root /data
      -public-host fake-gcs:4443
    ports:
      - "4443:4443"
    restart: unless-stopped
    networks:
      - vibe-network

networks:
  vibe-network:
    driver: bridge

volumes:
  ollama_data:
```

Save and exit (`Ctrl+X` → `Y` → `Enter`).

### Step 6.2 — Choose an AI Model

**Without GPU (CPU only)** — choose a small model that still works:

| Model | Download Size | RAM Needed | Quality | Pull Command |
|-------|--------------|-----------|---------|-------------|
| `qwen2.5:3b` | ~2 GB | 4 GB | Decent | `ollama pull qwen2.5:3b` |
| `llama3.2:3b` | ~2 GB | 4 GB | Decent | `ollama pull llama3.2:3b` |
| `qwen2.5:7b` | ~4.7 GB | 8 GB | Good | `ollama pull qwen2.5:7b` |
| `llama3.1:8b` | ~4.7 GB | 8 GB | Good | `ollama pull llama3.1:8b` |

**Recommendation for 16 GB RAM server (no GPU): `qwen2.5:7b`**
- Good JSON output quality (important for question generation)
- Fits in RAM with room for other services
- Slow on CPU (~2-5 min per generation) but works

**Recommendation for 32 GB RAM server (no GPU): `llama3.1:8b`**
- Better quality questions
- Still fits in RAM comfortably

> When you get GPU access, you can switch to larger, faster models (see Phase 10).

Update `docker-compose.yml` to set your chosen model:
```yaml
environment:
  - OLLAMA_PRELOAD_MODEL=qwen2.5:7b   # change this to your chosen model
```

Also update `litellm_config.yaml` — the `model_name` field must match what you tell Ollama to use.
The actual model name in `litellm_params` does not need to match exactly since Ollama uses whichever model is loaded, but it's good practice to keep them consistent.

---

## Phase 7 — Build and Launch ViBe

### Step 7.1 — Build the Backend and vibe-ai from Source

```bash
cd ~/vibe-deploy/vibe

# Build both containers (this takes 5-15 minutes first time)
docker compose build backend vibe-aiserver
```

**What is happening:**
- Docker downloads Python 3.12 and Node.js 20 base images
- It installs all dependencies (pip packages, npm packages)
- It compiles the TypeScript backend code to JavaScript
- It packages everything into runnable Docker images

Watch for errors. If you see `ERROR` (not just warnings), something needs fixing.
Common errors and fixes are in the [Troubleshooting](#troubleshooting) section.

### Step 7.2 — Build the Frontend

```bash
docker compose build frontend
```

This compiles the React app into static HTML/CSS/JS files with your configuration baked in.
This takes 5-15 minutes.

### Step 7.3 — Pull the Ollama Model

Ollama needs to download the AI model before it can generate questions.
Do this before starting everything so the first job doesn't time out.

```bash
# Start only the Ollama container
docker compose up -d ollama

# Wait 10 seconds for it to start
sleep 10

# Pull your chosen model (replace qwen2.5:7b with your chosen model)
docker exec vibe-ollama ollama pull qwen2.5:7b
```

This downloads the model file. Progress is shown. It takes 2-10 minutes depending on server speed.

Verify the model is loaded:
```bash
docker exec vibe-ollama ollama list
```

Expected output (example):
```
NAME            ID              SIZE    MODIFIED
qwen2.5:7b      f6daf6b12345    4.7 GB  2 minutes ago
```

### Step 7.4 — Start Everything

```bash
cd ~/vibe-deploy/vibe
docker compose up -d
```

This starts all 6 containers in the background. Watch the startup:

```bash
docker compose ps
```

Expected output after ~1 minute:
```
NAME              STATUS
vibe-backend      Up (healthy)
vibe-frontend     Up
vibe-aiserver     Up
vibe-ollama       Up
vibe-litellm      Up
vibe-fake-gcs     Up
```

### Step 7.5 — Verify Everything is Working

**Check the backend:**
```bash
curl http://localhost:8080/health
```
Expected: `{"status":"ok"}`

**Check vibe-ai:**
```bash
curl http://localhost:9017/health
```
Expected: `{"status":"healthy"}`

**Check Ollama:**
```bash
curl http://localhost:11434/api/tags
```
Expected: JSON listing your downloaded model.

**Check LiteLLM:**
```bash
curl http://localhost:4000/health
```
Expected: `{"status":"healthy"}`

**Open the website:**

In your browser, go to:
```
http://SERVER_IP_ADDRESS:3000
```

You should see the ViBe login page.

---

## Phase 8 — Set Up Domain and HTTPS

This makes ViBe accessible at a clean URL like `https://vibe.yourcollege.edu`
instead of `http://10.0.0.25:3000`.

### Step 8.1 — Ask IT to Point the Domain to Your Server

Contact your college IT department and say:

> "I need the DNS record for `vibe.yourcollege.edu` to point to IP address `YOUR_SERVER_IP`
> with an A record."

Wait for them to confirm this is done. You can verify with:
```bash
nslookup vibe.yourcollege.edu
```
When it shows your server's IP, the DNS is working.

### Step 8.2 — Install Nginx as the Reverse Proxy

Nginx sits in front of ViBe and handles:
- Serving everything through port 80 (HTTP) and 443 (HTTPS) — standard web ports
- SSL certificate management
- Routing: `/api` requests → backend, everything else → frontend

```bash
sudo apt install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

Verify Nginx is running:
```bash
sudo systemctl status nginx
```
Look for `Active: active (running)`.

### Step 8.3 — Create Nginx Configuration for ViBe

```bash
sudo nano /etc/nginx/sites-available/vibe
```

Paste this (replace `vibe.yourcollege.edu` with your actual domain):

```nginx
# HTTP → redirect to HTTPS
server {
    listen 80;
    server_name vibe.yourcollege.edu;
    return 301 https://$host$request_uri;
}

# HTTPS — main server block
server {
    listen 443 ssl;
    server_name vibe.yourcollege.edu;

    # SSL certificates (Certbot will fill these in automatically)
    ssl_certificate /etc/letsencrypt/live/vibe.yourcollege.edu/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/vibe.yourcollege.edu/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

    # Increase timeouts for AI operations (transcription, question gen can take minutes)
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
    proxy_connect_timeout 60s;

    # Frontend — serve the React app
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }

    # Backend API — route /api requests to the backend
    location /api {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
    }

    # Limit upload size (for video URLs and file uploads)
    client_max_body_size 100M;
}
```

Save and exit.

### Step 8.4 — Temporarily Enable HTTP-Only for Certificate Setup

Before we can set up HTTPS, we need Certbot to verify we own the domain.
Create a temporary HTTP-only config:

```bash
sudo nano /etc/nginx/sites-available/vibe-temp
```

Paste:
```nginx
server {
    listen 80;
    server_name vibe.yourcollege.edu;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }

    location /api {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
```

Save and exit. Enable this temporary config:

```bash
# Remove any existing enabled config for this domain
sudo rm -f /etc/nginx/sites-enabled/vibe /etc/nginx/sites-enabled/default

# Enable the temporary HTTP-only config
sudo ln -s /etc/nginx/sites-available/vibe-temp /etc/nginx/sites-enabled/vibe-temp

# Test the config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### Step 8.5 — Get a Free SSL Certificate (Let's Encrypt)

Let's Encrypt provides free SSL certificates. Certbot is the tool that handles this automatically.

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Get the certificate (replace with your domain)
sudo certbot --nginx -d vibe.yourcollege.edu
```

Certbot will ask:
1. Your email address → enter a real one (for renewal notices)
2. Agree to terms → type `Y`
3. Share email with EFF → type `N` (optional)

Certbot automatically modifies your Nginx config to enable HTTPS.

### Step 8.6 — Switch to the Full HTTPS Config

```bash
# Remove temporary config
sudo rm /etc/nginx/sites-enabled/vibe-temp

# Enable the full HTTPS config
sudo ln -s /etc/nginx/sites-available/vibe /etc/nginx/sites-enabled/vibe

# Test
sudo nginx -t

# Reload
sudo systemctl reload nginx
```

### Step 8.7 — Update ViBe Configuration for HTTPS

Now that you have HTTPS, update the URLs in your config files:

```bash
nano ~/vibe-deploy/vibe/backend.env
```

Change:
```env
APP_URL=https://vibe.yourcollege.edu
APP_ORIGINS=https://vibe.yourcollege.edu
FRONTEND_URL=https://vibe.yourcollege.edu/teacher
```

```bash
nano ~/vibe-deploy/vibe/frontend/.env
```

Change:
```env
VITE_BASE_URL=/api
```

> `VITE_BASE_URL=/api` stays the same — Nginx handles the HTTPS termination and the
> internal proxy still works on HTTP between Nginx and Docker.

Also update Firebase Authorized Domains:
1. Firebase Console → Authentication → Settings → Authorized Domains
2. Add `vibe.yourcollege.edu`

Rebuild the frontend (HTTPS URL is baked in at build time):

```bash
cd ~/vibe-deploy/vibe
docker compose build frontend
docker compose up -d
```

### Step 8.8 — Verify HTTPS

```bash
curl https://vibe.yourcollege.edu/api/health
```

Expected: `{"status":"ok"}`

Open in browser: `https://vibe.yourcollege.edu`
You should see a padlock (🔒) in the address bar — this means HTTPS is working.

### Step 8.9 — Auto-Renew SSL Certificates

Let's Encrypt certificates expire every 90 days. Certbot automatically renews them:

```bash
# Test the renewal process
sudo certbot renew --dry-run
```

If you see `Congratulations, all renewals succeeded`, auto-renewal is already configured.
Certbot added a cron job automatically.

---

## Phase 9 — Keep Everything Running After Reboot

The server may restart due to maintenance. Set everything to start automatically.

### Step 9.1 — Docker Auto-Start (Already Configured)

Docker Compose containers set `restart: unless-stopped` in docker-compose.yml.
This means Docker starts all containers automatically when the server reboots.

But Docker Compose itself needs to be started first. Create a systemd service:

```bash
sudo nano /etc/systemd/system/vibe.service
```

Paste:

```ini
[Unit]
Description=ViBe Application (Docker Compose)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/YOUR_USERNAME/vibe-deploy/vibe
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

> Replace `YOUR_USERNAME` with your actual Linux username.

Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable vibe.service

# Test it
sudo systemctl start vibe.service
sudo systemctl status vibe.service
```

### Step 9.2 — Test After Reboot

Simulate a reboot to confirm everything starts:

```bash
# Stop all containers
sudo systemctl stop vibe.service

# Start them all via the service
sudo systemctl start vibe.service

# Wait 60 seconds, then check
sleep 60
docker compose -f ~/vibe-deploy/vibe/docker-compose.yml ps
```

All 6 containers should be `Up`.

---

## Phase 10 — GPU Upgrade (When Access Is Granted)

When your college IT department gives you GPU access on the DGX server, you can switch
from slow CPU inference to fast GPU inference. This takes about 10 minutes.

### Step 10.1 — Verify GPU is Available

```bash
# Check if NVIDIA GPU is visible
nvidia-smi
```

Expected output shows your GPU name, memory, and driver version.
If you see `command not found`, the NVIDIA driver is not installed yet (see below).

### Step 10.2 — Install NVIDIA Container Toolkit (if not already done)

This lets Docker containers use the GPU:

```bash
# Add NVIDIA repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure Docker to use NVIDIA runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify:
```bash
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

If this shows your GPU, Docker can use it.

### Step 10.3 — Add GPU Support to Ollama

Update the `docker-compose.yml` Ollama service to use the GPU:

```bash
nano ~/vibe-deploy/vibe/docker-compose.yml
```

Find the `ollama:` service block and add `deploy:` section:

```yaml
  ollama:
    image: ollama/ollama
    container_name: vibe-ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
    environment:
      - OLLAMA_PRELOAD_MODEL=qwen2.5:14b   # upgrade to a larger, better model
    # ADD THESE LINES:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    networks:
      - vibe-network
```

### Step 10.4 — Pull a Better Model (GPU can handle larger models)

With GPU, you can use much better models:

| Model | GPU VRAM Needed | Quality |
|-------|----------------|---------|
| `qwen2.5:14b` | 10 GB VRAM | Very good |
| `llama3.1:70b` | 40+ GB VRAM | Excellent |
| `qwen2.5:32b` | 20 GB VRAM | Excellent |

For DGX A100 GPU (80 GB VRAM):
```bash
docker exec vibe-ollama ollama pull llama3.1:70b
```

For DGX with 40 GB VRAM:
```bash
docker exec vibe-ollama ollama pull qwen2.5:32b
```

Update `docker-compose.yml` to set `OLLAMA_PRELOAD_MODEL` to your new model.

### Step 10.5 — Restart Ollama with GPU

```bash
cd ~/vibe-deploy/vibe
docker compose up -d ollama
```

Verify GPU is being used:
```bash
# Watch GPU usage
watch -n 1 nvidia-smi

# In another terminal, run a test
docker exec vibe-ollama ollama run qwen2.5:14b "Say hello in one sentence"
```

You should see GPU memory usage go up in the `nvidia-smi` output.

### Step 10.6 — No Other Changes Needed

Everything else (vibe-ai, LiteLLM, backend) stays the same.
The `VLLM_BASE_URL=http://ollama:11434/v1` env var still points to the same Ollama container.
Ollama automatically uses the GPU once the Docker GPU access is configured.

---

## Maintenance and Updates

### Check System Health Daily

```bash
# Are all containers running?
docker compose -f ~/vibe-deploy/vibe/docker-compose.yml ps

# How much disk space is left?
df -h /

# How much RAM is free?
free -h

# Are there any errors in the logs?
docker compose -f ~/vibe-deploy/vibe/docker-compose.yml logs --tail=50
```

### Update ViBe to New Version

```bash
cd ~/vibe-deploy

# Update main ViBe repo
cd vibe
git pull origin main

# Update vibe-ai repo
cd ../vibe-ai
git pull origin main

# Rebuild changed containers
cd ../vibe

# Rebuild backend if backend code changed
docker compose build backend

# Rebuild vibe-ai if vibe-ai code changed
docker compose build vibe-aiserver

# Rebuild frontend if frontend code changed
docker compose build frontend

# Restart everything
docker compose up -d
```

### View Live Logs

```bash
# All containers at once
docker compose -f ~/vibe-deploy/vibe/docker-compose.yml logs -f

# Only one container (e.g., backend)
docker logs vibe-backend --follow

# Only vibe-ai (watch pipeline stages)
docker logs vibe-aiserver --follow
```

### Clear Disk Space

Docker keeps old images and build cache. Clean them periodically:

```bash
# Remove stopped containers and unused images (safe)
docker system prune -f

# Also remove build cache (safe but next build will be slower)
docker builder prune -f
```

---

## Troubleshooting

### Container won't start

```bash
# Check why
docker logs CONTAINER_NAME
```

Replace `CONTAINER_NAME` with one of:
`vibe-backend`, `vibe-frontend`, `vibe-aiserver`, `vibe-ollama`, `vibe-litellm`, `vibe-fake-gcs`

---

### "Cannot connect to MongoDB" in backend logs

```bash
docker logs vibe-backend | grep -i mongo
```

1. Check `DB_URL` in `backend.env` — make sure password has no `<` `>` brackets
2. In MongoDB Atlas → Network Access → add your server's public IP
3. Test the connection:
   ```bash
   docker exec vibe-backend wget -qO- http://localhost:8080/health
   ```

---

### "Transcribing content..." stuck for more than 10 minutes

```bash
docker logs vibe-aiserver --follow
```

Look for:
- `Model size 'large' capped to 'small' for local deployment` — good, the cap is working
- `Generating transcript from audio...` with a progress bar — Whisper is running
- Percentage progress — if it's stuck at 0%, check disk space: `df -h /`

If the small Whisper model (~461 MB) needs to download on first use, it may take 2-5 minutes before progress shows.

---

### Question generation returns JSON error

```bash
docker logs vibe-aiserver | grep -i "error\|json\|question"
```

If you see `Expecting ',' delimiter` — the model response was cut off.
Check `max_tokens=4096` is set in `question_generation.py`.

If questions are wrong format — try a larger Ollama model.

---

### Nginx shows 502 Bad Gateway

```bash
sudo nginx -t              # Check Nginx config syntax
docker compose ps          # Check all containers are running
sudo systemctl status nginx
```

502 means Nginx can't reach the container. Usually the container has crashed.
Check `docker logs vibe-backend` or `docker logs vibe-frontend`.

---

### SSL certificate renewal fails

```bash
sudo certbot renew --dry-run
```

Common cause: port 80 blocked. Check:
```bash
sudo ufw status
curl http://vibe.yourcollege.edu   # Should not time out
```

---

### Disk full

```bash
df -h /
docker system prune -f      # Remove unused Docker objects
docker builder prune -f     # Remove build cache
```

If the AI model files are taking too much space:
```bash
docker exec vibe-ollama ollama list    # See downloaded models
docker exec vibe-ollama ollama rm MODEL_NAME   # Remove a model
```

---

### How to restart a single service

```bash
docker compose -f ~/vibe-deploy/vibe/docker-compose.yml restart vibe-backend
docker compose -f ~/vibe-deploy/vibe/docker-compose.yml restart vibe-ollama
# etc.
```

---

## Quick Command Reference

Run all commands from `~/vibe-deploy/vibe/` directory.

| Task | Command |
|------|---------|
| Start everything | `docker compose up -d` |
| Stop everything | `docker compose down` |
| Check status | `docker compose ps` |
| View all logs | `docker compose logs --tail=100` |
| View live logs | `docker compose logs -f` |
| Restart one service | `docker compose restart SERVICE_NAME` |
| Rebuild backend | `docker compose build backend && docker compose up -d backend` |
| Rebuild frontend | `docker compose build frontend && docker compose up -d frontend` |
| Rebuild vibe-ai | `docker compose build vibe-aiserver && docker compose up -d vibe-aiserver` |
| Pull Ollama model | `docker exec vibe-ollama ollama pull MODEL_NAME` |
| List Ollama models | `docker exec vibe-ollama ollama list` |
| Check GPU (when available) | `nvidia-smi` |
| Check disk space | `df -h /` |
| Check RAM | `free -h` |
| Clean Docker cache | `docker system prune -f` |
| Test backend health | `curl http://localhost:8080/health` |
| Test vibe-ai health | `curl http://localhost:9017/health` |
| Test Ollama | `curl http://localhost:11434/api/tags` |
| Test HTTPS | `curl https://vibe.yourcollege.edu/api/health` |

---

## Deployment Checklist

Use this checklist to confirm everything is done:

**Infrastructure:**
- [ ] SSH access to KVM VM confirmed
- [ ] Ubuntu 22.04 updated (`sudo apt update && sudo apt upgrade`)
- [ ] Git, curl, nano, htop installed
- [ ] Firewall configured (ports 22, 80, 443, 8080, 3000 open)
- [ ] Docker and Docker Compose installed
- [ ] Docker starts on boot (`systemctl enable docker`)

**External Services:**
- [ ] MongoDB Atlas cluster created and connection string saved
- [ ] Firebase project created and service account key downloaded
- [ ] Firebase Email/Password authentication enabled
- [ ] Firebase authorized domains include server IP and domain
- [ ] reCAPTCHA keys obtained (site key + secret key)

**Code and Configuration:**
- [ ] `vibe` repo cloned to `~/vibe-deploy/vibe/`
- [ ] `vibe-ai` repo cloned to `~/vibe-deploy/vibe-ai/`
- [ ] `firebase-service-account.json` uploaded to server
- [ ] `backend.env` created and all values filled in
- [ ] `frontend/.env` created and all values filled in
- [ ] `vibe-ai/.env` created
- [ ] `litellm_config.yaml` created
- [ ] `vibe-ai/Dockerfile` created
- [ ] vibe-ai source code fixes applied

**AI Setup:**
- [ ] `docker-compose.yml` updated with Ollama, LiteLLM, fake-gcs services
- [ ] Ollama model pulled (`docker exec vibe-ollama ollama pull MODEL_NAME`)

**Build and Launch:**
- [ ] Backend built (`docker compose build backend`)
- [ ] vibe-ai built (`docker compose build vibe-aiserver`)
- [ ] Frontend built (`docker compose build frontend`)
- [ ] All 6 containers running (`docker compose ps`)
- [ ] Backend health check passes (`curl localhost:8080/health`)
- [ ] vibe-ai health check passes (`curl localhost:9017/health`)
- [ ] Website loads at `http://SERVER_IP:3000`

**Domain and HTTPS:**
- [ ] DNS A record points domain to server IP
- [ ] Nginx installed and configured
- [ ] SSL certificate obtained via Certbot
- [ ] HTTPS works at `https://vibe.yourcollege.edu`
- [ ] Firebase authorized domains updated with HTTPS domain
- [ ] `backend.env` updated with HTTPS URLs
- [ ] Frontend rebuilt after URL change
- [ ] Certificate auto-renewal tested

**Persistence:**
- [ ] `vibe.service` systemd service created and enabled
- [ ] Tested: services restart after `systemctl stop vibe.service && systemctl start vibe.service`

---

*For questions about this deployment, contact the ViBe team or open a GitHub issue.*
