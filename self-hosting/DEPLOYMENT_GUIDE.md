# ViBe — Complete Self-Hosting & Deployment Guide

> **Who is this guide for?**
> This guide is written for anyone — even if you have never deployed software before. Every step is explained from scratch. If you already know what MongoDB Atlas or Firebase is, feel free to skip those sections.

---

## Table of Contents

1. [What Is ViBe and How It Works](#1-what-is-vibe-and-how-it-works)
2. [Architecture — The Big Picture](#2-architecture--the-big-picture)
3. [What You Will Need Before Starting](#3-what-you-will-need-before-starting)
4. [Phase 1 — Create Your External Service Accounts](#phase-1--create-your-external-service-accounts)
   - [1.1 MongoDB Atlas — Your Database (Free)](#11-mongodb-atlas--your-database-free)
   - [1.2 Firebase — Authentication System](#12-firebase--authentication-system)
   - [1.3 Anthropic — AI Question Generation (Cloud API)](#13-anthropic--ai-question-generation-cloud-api)
   - [1.3 Alternative — Local LLM with LM Studio (Free, No API Costs)](#13-alternative--local-llm-with-lm-studio-free-no-api-costs)
   - [1.4 Google reCAPTCHA — Spam Protection](#14-google-recaptcha--spam-protection)
   - [1.5 Sentry — Error Monitoring (Optional)](#15-sentry--error-monitoring-optional)
5. [Phase 2 — Prepare Your Server / Computer](#phase-2--prepare-your-server--computer)
   - [2.1 System Requirements](#21-system-requirements)
   - [2.2 Install Git](#22-install-git)
   - [2.3 Install Docker and Docker Compose](#23-install-docker-and-docker-compose)
6. [Phase 3 — Clone the Repository](#phase-3--clone-the-repository)
7. [Phase 4 — Configure the Backend](#phase-4--configure-the-backend)
8. [Phase 5 — Configure the Frontend](#phase-5--configure-the-frontend)
9. [Phase 6 — Build and Launch with Docker](#phase-6--build-and-launch-with-docker)
10. [Phase 7 — Verify Everything Works](#phase-7--verify-everything-works)
11. [Phase 8 — Set Up a Domain and HTTPS (Recommended)](#phase-8--set-up-a-domain-and-https-recommended)
12. [Phase 9 — AI Server Setup](#phase-9--ai-server-setup)
    - [System 1 — Full Video Pipeline (vibe-ai + LM Studio)](#system-1--full-video-pipeline-vibe-ai--lm-studio)
    - [System 2 — Manual Transcript Path (Anthropic or LM Studio)](#system-2--manual-transcript-path-anthropic-or-lm-studio)
13. [Database Reference](#database-reference)
14. [Updating ViBe to a New Version](#updating-vibe-to-a-new-version)
    - [What Kind of Change Needs What Action?](#what-kind-of-change-needs-what-action)
    - [Update the Backend](#step-5a--update-the-backend)
    - [Update the Frontend](#step-5b--update-the-frontend)
    - [Roll Back If Something Breaks](#how-to-roll-back-if-something-breaks)
    - [Automated Update Script](#automated-one-command-update-script)
15. [Troubleshooting](#troubleshooting)
16. [Quick Command Reference](#quick-command-reference)

---

## 1. What Is ViBe and How It Works

ViBe is an **educational platform** that helps teachers create courses and automatically challenges students with AI-generated questions. If a student gets something wrong, ViBe sends them back to review the material — similar to the Indian tale of Vikram and Betaal.

**Key capabilities:**
- Teachers create courses with video, text, and quizzes
- Students take AI-generated quizzes that adapt to their performance
- The platform monitors engagement and tracks emotional state during learning
- Built-in proctoring ensures academic integrity

ViBe has **two parts** that you deploy:

| Part | What it is | How users access it |
|---|---|---|
| **Frontend** | The website (what users see in their browser) | Opens at `http://your-server:3000` |
| **Backend** | The API server (handles data, logic, AI) | Runs at `http://your-server:8080` |

The frontend and backend talk to each other automatically once configured.

---

## 2. Architecture — The Big Picture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Your Server                              │
│                                                                   │
│  ┌─────────────────────┐        ┌──────────────────────────────┐ │
│  │   Frontend (Port 3000) │──────▶│  Backend API (Port 8080)    │ │
│  │   React app in Nginx   │       │  Node.js + Express           │ │
│  └─────────────────────┘        └──────────────┬───────────────┘ │
│                                                  │                 │
└──────────────────────────────────────────────────┼─────────────────┘
                                                   │
                           ┌───────────────────────┼────────────────┐
                           │    External Services   │                │
                           │                        ▼                │
                           │  ┌─────────────────────────────────┐   │
                           │  │ MongoDB Atlas (Database)        │   │
                           │  │ Stores all courses, users, etc. │   │
                           │  └─────────────────────────────────┘   │
                           │                                         │
                           │  ┌─────────────────────────────────┐   │
                           │  │ Firebase (Authentication)       │   │
                           │  │ Handles login / sign-up         │   │
                           │  └─────────────────────────────────┘   │
                           │                                         │
                           │  ┌─────────────────────────────────┐   │
                           │  │ Anthropic Claude (AI)           │   │
                           │  │ Generates quiz questions        │   │
                           │  └─────────────────────────────────┘   │
                           └─────────────────────────────────────────┘
```

**The flow:**
1. A user opens their browser and goes to your server's address
2. The browser loads the ViBe web app (frontend)
3. When the user logs in, Firebase handles authentication
4. When data is needed (courses, quizzes), the frontend calls the backend API
5. The backend reads/writes data to MongoDB Atlas
6. When AI question generation is triggered, the backend calls Anthropic Claude

---

## 3. What You Will Need Before Starting

Before you begin, prepare the following. Each item will be explained in detail in Phase 1.

### Accounts to Create (all free tiers available)

| Service | Purpose | Cost | Sign-up |
|---|---|---|---|
| **MongoDB Atlas** | Database to store all app data | Free (512 MB) | [mongodb.com/atlas](https://www.mongodb.com/atlas) |
| **Firebase** | User authentication (login/sign-up) | Free (Spark plan) | [firebase.google.com](https://firebase.google.com) |
| **Anthropic** | AI-powered question generation | Pay-per-use (very cheap) | [console.anthropic.com](https://console.anthropic.com) |
| **Google Cloud** | reCAPTCHA (spam protection) | Free | [console.cloud.google.com](https://console.cloud.google.com) |

### Information to Collect

As you go through Phase 1, you will collect these values. Keep a notepad open.

```
MongoDB:
  DB_URL = _______________________________________________

Firebase:
  VITE_FIREBASE_API_KEY              = ___________________
  VITE_FIREBASE_AUTH_DOMAIN          = ___________________
  VITE_FIREBASE_PROJECT_ID           = ___________________
  VITE_FIREBASE_STORAGE_BUCKET       = ___________________
  VITE_FIREBASE_MESSAGING_SENDER_ID  = ___________________
  VITE_FIREBASE_APP_ID               = ___________________

Anthropic:
  ANTHROPIC_CRED = sk-ant-api03-_____________________________

reCAPTCHA:
  RECAPTCHA_SECRET_KEY   = ___________________________________
  VITE_RECAPTCHA_SITE_KEY = __________________________________
```

---

## Phase 1 — Create Your External Service Accounts

---

### 1.1 MongoDB Atlas — Your Database (Free)

MongoDB Atlas is the cloud-hosted database where ViBe stores everything: users, courses, quizzes, enrollments, and more. The free tier (512 MB) is enough for hundreds of users.

> **What is a database?** Think of it as a very organized filing cabinet in the cloud. ViBe stores and retrieves data from it every time someone does anything on the platform.

#### Step 1 — Create a MongoDB Atlas Account

1. Go to [https://www.mongodb.com/atlas](https://www.mongodb.com/atlas)
2. Click **Try Free** and sign up with your email
3. After verifying your email, you will land on the Atlas dashboard

#### Step 2 — Create a Free Cluster

A "cluster" is the actual database server. You get one free cluster.

1. Click **Build a Database**
2. Choose **M0 — Free** (the free tier)
3. Select a cloud provider (any — AWS, Google Cloud, or Azure all work)
4. Choose the region closest to your server
5. Give your cluster a name (example: `vibe-cluster`)
6. Click **Create Deployment**

#### Step 3 — Create a Database User

This is the username and password your application uses to connect to MongoDB.

1. In the popup that appears, you will see **Username and Password** fields
2. Enter a username (example: `vibe_user`)
3. Enter a strong password (or click **Autogenerate Secure Password** and copy it)
4. **Write this down** — you will need it in the connection string
5. Click **Create Database User**

#### Step 4 — Allow Network Access

By default, MongoDB Atlas blocks all connections. You need to allow your server to connect.

1. Click **Add My Current IP Address** if you want only your IP, OR
2. Click **Allow Access from Anywhere** and enter `0.0.0.0/0` to allow from any IP

   > For production with a known server IP, enter only your server's IP for better security.

3. Click **Finish and Close**

#### Step 5 — Get Your Connection String

1. On the Atlas dashboard, click **Connect** on your cluster
2. Choose **Drivers**
3. Select **Node.js** as the driver
4. Copy the connection string — it looks like this:
   ```
   mongodb+srv://vibe_user:<password>@vibe-cluster.abc123.mongodb.net/?retryWrites=true&w=majority&appName=vibe-cluster
   ```
5. Replace `<password>` with the actual password you created in Step 3
6. **Save this complete string** — this is your `DB_URL`

> **Note:** ViBe will automatically create all the required database collections (tables) on first run. You do NOT need to manually create any tables or collections. See the [Database Reference](#database-reference) section for what gets created.

---

### 1.2 Firebase — Authentication System

Firebase handles user registration, login, and session tokens. ViBe uses Firebase Auth so you don't have to build your own login system.

> **What is Firebase?** It's Google's backend platform. ViBe uses only the **Authentication** feature (login/sign-up).

#### Step 1 — Create a Firebase Project

1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Click **Add Project** (or **Create a project**)
3. Enter a project name (example: `vibe-myschool`)
4. Choose whether to enable Google Analytics (optional — you can skip it)
5. Click **Create Project**
6. Wait for it to finish, then click **Continue**

#### Step 2 — Enable Email/Password Authentication

1. In the left sidebar, click **Authentication**
2. Click **Get Started**
3. Under **Sign-in providers**, click **Email/Password**
4. Toggle **Enable** to ON
5. Click **Save**

#### Step 3 — Register a Web App

1. On the Firebase project overview page (home icon), click the **Web** icon (`</>`)
2. Enter an app nickname (example: `vibe-web`)
3. Do NOT check "Firebase Hosting" unless you plan to use it
4. Click **Register App**
5. You will see a block of JavaScript code that looks like this:

   ```javascript
   const firebaseConfig = {
     apiKey: "AIzaSyABCDEFGHIJKLMNOP...",
     authDomain: "vibe-myschool.firebaseapp.com",
     projectId: "vibe-myschool",
     storageBucket: "vibe-myschool.appspot.com",
     messagingSenderId: "123456789012",
     appId: "1:123456789012:web:abcdef1234567890",
     measurementId: "G-XXXXXXXXXX"
   };
   ```

6. **Copy each value** — these are your `VITE_FIREBASE_*` variables:

   | Firebase config key | Your .env variable |
   |---|---|
   | `apiKey` | `VITE_FIREBASE_API_KEY` |
   | `authDomain` | `VITE_FIREBASE_AUTH_DOMAIN` |
   | `projectId` | `VITE_FIREBASE_PROJECT_ID` |
   | `storageBucket` | `VITE_FIREBASE_STORAGE_BUCKET` |
   | `messagingSenderId` | `VITE_FIREBASE_MESSAGING_SENDER_ID` |
   | `appId` | `VITE_FIREBASE_APP_ID` |
   | `measurementId` | `VITE_FIREBASE_MEASUREMENT_ID` |

7. Click **Continue to Console**

#### Step 4 — Add Your Domain to Authorized Domains

This step prevents other websites from using your Firebase project.

1. In Firebase Console, go to **Authentication** → **Settings** → **Authorized Domains**
2. You will see `localhost` already there
3. Click **Add Domain** and add your server's domain or IP (example: `192.168.1.100` or `yourdomain.com`)
4. Click **Add**

#### Step 5 — Generate a Service Account Key (Required for Self-Hosting)

The backend needs Firebase Admin SDK credentials to verify user tokens.

1. In Firebase Console → click the gear icon → **Project Settings**
2. Click the **Service accounts** tab
3. Click **Generate new private key** → confirm → a JSON file downloads
4. **Save this file** as `firebase-service-account.json` in the root of your `vibe/` directory
5. This file contains `client_email` and `private_key` — you will need these values

---

### 1.3 Anthropic — AI Question Generation (Cloud API)

Anthropic's Claude AI generates quiz questions from course content. You pay only for what you use (typically fractions of a cent per question generated).

#### Step 1 — Create an Anthropic Account

1. Go to [https://console.anthropic.com](https://console.anthropic.com)
2. Sign up and verify your email
3. You may need to add a payment method (no charge until you use the API)

#### Step 2 — Create an API Key

1. Click your account name in the top right → **API Keys**
2. Click **Create Key**
3. Give it a name (example: `vibe-production`)
4. Copy the key immediately — it starts with `sk-ant-api03-...`

   > **Important:** This key is shown only once. Copy it now and store it safely. If you lose it, you must create a new one.

5. This is your `ANTHROPIC_CRED`

---

### 1.3 Alternative — Local LLM with LM Studio (Free, No API Costs)

> **Skip this section** if you chose to use the Anthropic Cloud API above. Only follow this if you want AI to run entirely on your own server — no internet required, no API charges, and all data stays private.

#### Cloud API vs Local LLM — Which Should You Choose?

| | Anthropic Cloud API | LM Studio (Local) |
|---|---|---|
| Cost | Pay per use (~$0.01 per quiz) | Free forever |
| Setup time | 5 minutes | 15–30 minutes |
| Speed | Fast (runs on Anthropic's servers) | Depends on your hardware |
| Internet needed | Yes | No (fully offline) |
| Data privacy | Data sent to Anthropic | Stays only on your server |
| AI quality | Excellent (Claude) | Good (depends on model chosen) |

#### How It Works

ViBe's backend uses the Anthropic SDK. The Anthropic SDK has a feature where if you set an environment variable called `ANTHROPIC_BASE_URL`, it sends all AI requests to **that URL instead** of Anthropic's servers. You use a free tool called **LiteLLM** as a translator in the middle:

```
ViBe Backend
  (uses Anthropic SDK)
       │
       ▼  ANTHROPIC_BASE_URL=http://litellm:4000
LiteLLM Proxy  ◄─── translates Anthropic format → OpenAI format
       │
       ▼  http://host:1234/v1
LM Studio Local Server  ◄─── runs the AI model on your GPU/CPU
       │
       ▼
Local LLM Model (Llama, Mistral, Qwen, etc.)
```

You do not need to change any ViBe source code. Only two environment variables in `backend.env` need to be updated.

#### Hardware Requirements

| Setup | Minimum RAM | Recommended RAM | Speed |
|---|---|---|---|
| CPU only (no GPU) | 16 GB | 32 GB | Slow: 30–120 sec per quiz |
| NVIDIA GPU | 8 GB VRAM | 16+ GB VRAM | Fast: 5–15 sec per quiz |
| Apple Silicon (M1/M2/M3) | 8 GB unified memory | 16+ GB | Fast: 10–20 sec per quiz |

> If your server has less than 8 GB RAM total, use the Anthropic Cloud API instead — it is more reliable on low-resource machines.

#### Recommended Models for Question Generation

ViBe requires the AI model to return **strictly formatted JSON**. These models handle that well:

| Model Name | Size on Disk | RAM Needed | Quality | Best For |
|---|---|---|---|---|
| Llama 3.2 3B Instruct | ~2 GB | 4 GB RAM | Decent | Very low-resource servers |
| Llama 3.1 8B Instruct | ~5 GB | 8 GB RAM | Good | General use, balanced |
| Mistral Nemo 12B | ~7 GB | 12 GB RAM | Very good | Strong JSON output |
| Qwen 2.5 14B Instruct | ~9 GB | 16 GB RAM | Excellent | Best quality without GPU |
| Llama 3.3 70B Instruct | ~43 GB | 48 GB RAM | Near Claude quality | High-end servers |

**Recommended for most users:** Start with **Llama 3.1 8B Instruct** (`Q4_K_M` quantization).

---

#### Step 1 — Install LM Studio

**Option A — Desktop (macOS or Windows with GUI)**

1. Go to [https://lmstudio.ai](https://lmstudio.ai)
2. Click **Download** for your operating system
3. Install and open the application

**Option B — Headless Server (Linux without a desktop)**

LM Studio provides a command-line tool for servers:

```bash
# Download and install the LM Studio CLI
curl -fsSL https://files.lmstudio.ai/install.sh | bash

# Apply the installation to your current shell session
source ~/.bashrc

# Confirm it installed correctly
lms version
```

---

#### Step 2 — Download a Model

**Using the Desktop GUI (Option A):**

1. Open LM Studio
2. Click the **Search** icon (magnifying glass) in the left sidebar
3. Type `llama-3.1-8b-instruct` in the search box
4. Find the result from **lmstudio-community**
5. Click the version labeled **Q4_K_M** (this is a compressed format — good quality, reasonable size)
6. Click **Download** and wait for it to finish (5 GB download)

**Using the CLI (Option B — Linux):**

```bash
# Search for the model
lms search llama-3.1-8b-instruct

# Download it (copy the exact model ID shown in the search results)
lms get "lmstudio-community/Meta-Llama-3.1-8B-Instruct-GGUF/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
```

> To browse all available models, visit [huggingface.co](https://huggingface.co) and search for "GGUF" models.

---

#### Step 3 — Start the LM Studio Server

**Using the Desktop GUI:**

1. Click the **Local Server** icon in the left sidebar (looks like `⇌`)
2. From the model dropdown at the top, select the model you downloaded
3. Click **Start Server**
4. You should see: `Server running at http://localhost:1234`

**Using the CLI (Linux):**

```bash
# Load the model into memory, using GPU if available
lms load "Meta-Llama-3.1-8B-Instruct-Q4_K_M" --gpu max

# Start the server on port 1234
lms server start --port 1234
```

**Verify LM Studio is accepting requests:**

```bash
curl http://localhost:1234/v1/models
```

You should see a JSON object listing the loaded model name. If you see `Connection refused`, the server is not running yet.

---

#### Step 4 — Set Up LiteLLM Proxy

LiteLLM is a free, open-source proxy that translates the Anthropic API format into the OpenAI format that LM Studio understands.

**Create the LiteLLM config file:**

```bash
# Run this from the root of the vibe/ project
nano litellm_config.yaml
```

Paste this exact content:

```yaml
model_list:
  - model_name: claude-sonnet-4-20250514
    litellm_params:
      model: openai/lm_studio_local
      api_base: http://host.docker.internal:1234/v1
      api_key: not-needed

litellm_settings:
  drop_params: true
  set_verbose: false
```

> `host.docker.internal` is a special hostname that Docker containers use to reach services running on the host machine (where LM Studio is running). This is configured to work on macOS, Windows, and Linux via the `extra_hosts` setting in `docker-compose.yml`.

Save and exit (`Ctrl + X`, `Y`, `Enter`).

**Add LiteLLM to your Docker Compose:**

Open `docker-compose.yml` and uncomment the `litellm` service block. The section looks like this — remove the `#` from each line:

```yaml
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: vibe-litellm
    volumes:
      - ./litellm_config.yaml:/app/config.yaml
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    ports:
      - "4000:4000"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    restart: unless-stopped
    networks:
      - vibe-network
```

**Start the LiteLLM container:**

```bash
docker compose up -d litellm

# Check it started without errors
docker compose logs litellm
```

**Expected output in litellm logs:**
```
LiteLLM: Proxy initialized
LiteLLM: Starting server on port 4000
```

**Verify LiteLLM is healthy:**

```bash
curl http://localhost:4000/health
```

Expected: `{"status":"healthy"}`

---

#### Step 5 — Update backend.env

Open `backend.env` and update the AI section:

```dotenv
# ── AI / ANTHROPIC ────────────────────────────────────────────────

# Set the model name — must match the model_name in litellm_config.yaml exactly
ANTHROPIC_MODEL=claude-sonnet-4-20250514

# Set any non-empty string as the key — LiteLLM does not check this
ANTHROPIC_CRED=local-llm-no-key-needed

# NEW: Point the Anthropic SDK to LiteLLM instead of Anthropic's cloud servers
# Use the Docker service name "litellm" since both run in the same docker-compose network
ANTHROPIC_BASE_URL=http://litellm:4000
```

> If LiteLLM is running outside Docker (not in docker-compose), use `ANTHROPIC_BASE_URL=http://localhost:4000` instead.

---

#### Step 6 — Restart Backend

```bash
# Restart the backend to pick up the new environment variable
docker compose up -d backend

# Watch the logs to confirm it connects properly
docker compose logs -f backend
```

---

#### Step 7 — Test End-to-End

1. Open the ViBe frontend in your browser
2. Log in as a teacher
3. Open a course and go to a video item that has a transcript
4. Click **Generate Questions with AI**

While it's generating, open two terminal windows and watch the logs:

**Terminal 1 — Backend logs:**
```bash
docker compose logs -f backend
```

**Terminal 2 — LiteLLM logs:**
```bash
docker compose logs -f litellm
```

**What you should see in LiteLLM logs (success):**
```
POST /v1/messages → 200 OK
Forwarded to: http://host.docker.internal:1234/v1/chat/completions
```

If questions appear in ViBe, your local LLM setup is working.

---

#### Keeping LM Studio Running After Reboot (Linux Server)

To ensure LM Studio starts automatically when your server reboots, create a systemd service:

```bash
sudo nano /etc/systemd/system/lmstudio.service
```

Paste this content (replace `YOUR_USERNAME` with your actual Linux username):

```ini
[Unit]
Description=LM Studio Local Server
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
ExecStart=/home/YOUR_USERNAME/.lmstudio/bin/lms server start --port 1234
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable lmstudio
sudo systemctl start lmstudio

# Check it is running
sudo systemctl status lmstudio
```

---

#### Troubleshooting Local LLM Setup

**LM Studio server not reachable from LiteLLM container**

Symptom: LiteLLM logs show `Connection refused` when trying to reach `host.docker.internal:1234`

Fix: Make sure the `extra_hosts` line is present in your `docker-compose.yml` under the `litellm` service:
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```
Then run `docker compose up -d litellm`.

---

**LiteLLM returns model not found error**

Symptom: `LiteLLM: No model found for 'claude-sonnet-4-20250514'`

Fix: The model name in `ANTHROPIC_MODEL` (in `backend.env`) must exactly match the `model_name` in `litellm_config.yaml`. Both must be `claude-sonnet-4-20250514`.

---

**Questions generated are malformed or missing fields**

Symptom: AI question generation returns an error about invalid JSON

This means the local model is not following the JSON format instructions well enough. Try these in order:
1. Switch to a larger model (e.g., from 8B to 14B parameters)
2. Use a Mistral or Qwen model — they follow instructions more reliably
3. Reduce the transcript size (send shorter text chunks)
4. As a last resort, switch to the Anthropic Cloud API which guarantees correct JSON output

---

**Question generation is very slow**

- On CPU-only: Expect 1–5 minutes per generation. This is normal.
- Enable GPU offloading in LM Studio: In the GUI, go to server settings and increase the **GPU Layers** slider to maximum
- Try a smaller model (3B instead of 8B)

---

### 1.4 Google reCAPTCHA — Spam Protection

reCAPTCHA prevents bots from creating fake accounts on your platform.

#### Step 1 — Go to reCAPTCHA Admin Console

1. Go to [https://www.google.com/recaptcha/admin/create](https://www.google.com/recaptcha/admin/create)
2. Sign in with a Google account

#### Step 2 — Register Your Site

1. **Label**: Enter a name (example: `ViBe Platform`)
2. **reCAPTCHA type**: Select **reCAPTCHA v2** → **"I'm not a robot" Checkbox**
3. **Domains**: Enter your server's domain or IP address
   - For local testing, add `localhost`
   - For production, add your actual domain (example: `yourdomain.com`)
4. Accept the Terms of Service
5. Click **Submit**

#### Step 3 — Copy Your Keys

You will see two keys:
- **Site Key** (public) → This is your `VITE_RECAPTCHA_SITE_KEY`
- **Secret Key** (private) → This is your `RECAPTCHA_SECRET_KEY`

> The site key goes in the frontend. The secret key goes in the backend.

---

### 1.5 Sentry — Error Monitoring (Optional)

Sentry automatically captures and reports errors so you know when something breaks. This is optional but recommended for production.

1. Go to [https://sentry.io](https://sentry.io) and sign up for free
2. Create a new project → choose **Node.js** as the platform
3. Copy the **DSN** (it looks like `https://abc123@o12345.ingest.sentry.io/789`)
4. This is your `SENTRY_DSN`

If you skip this, leave `SENTRY_DSN=` empty in your config.

---

## Phase 2 — Prepare Your Server / Computer

---

### 2.1 System Requirements

ViBe can be self-hosted on:
- A cloud server (AWS EC2, DigitalOcean Droplet, Google Cloud VM, etc.)
- A VPS (Virtual Private Server)
- Your own physical server or desktop computer

**Minimum requirements:**

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 2 cores | 4 cores |
| RAM | 2 GB | 4 GB |
| Disk Space | 20 GB | 40 GB |
| OS | Ubuntu 20.04+ / Debian 11+ / macOS / Windows with WSL2 | Ubuntu 22.04 LTS |

**The instructions below are written for Ubuntu/Debian Linux.** macOS and Windows (via WSL2) also work — Docker commands are the same.

---

### 2.2 Install Git

Git is used to download (clone) the ViBe source code.

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install git -y
git --version    # Should print: git version 2.x.x
```

**macOS:**
```bash
# Git comes with Xcode Command Line Tools
git --version
# If not installed, macOS will prompt you to install it
```

---

### 2.3 Install Docker and Docker Compose

Docker is the system that packages and runs ViBe in isolated containers. Docker Compose is the tool that coordinates multiple containers at once.

**Ubuntu/Debian — run these commands one by one:**

```bash
# Step 1: Update the package list
sudo apt update

# Step 2: Install required packages
sudo apt install ca-certificates curl gnupg -y

# Step 3: Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Step 4: Add Docker's repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Step 5: Install Docker
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Step 6: Allow your user to run Docker without sudo
sudo usermod -aG docker $USER

# Step 7: Log out and back in (or run this to apply group change without logout)
newgrp docker

# Step 8: Verify installation
docker --version          # Should print: Docker version 24.x.x or higher
docker compose version    # Should print: Docker Compose version v2.x.x
```

**macOS:**
1. Download and install **Docker Desktop** from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
2. Open Docker Desktop and wait for it to start (whale icon in menu bar turns solid)
3. Open Terminal and verify:
   ```bash
   docker --version
   docker compose version
   ```

**Windows (WSL2):**
1. Install WSL2 by opening PowerShell as Administrator and running:
   ```powershell
   wsl --install
   ```
2. Restart your computer
3. Install Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/) and enable the WSL2 backend
4. Open Ubuntu (WSL) terminal and proceed as Ubuntu above

---

## Phase 3 — Clone the Repository

Now download the ViBe source code to your server.

```bash
# Navigate to where you want to store ViBe (home directory is fine)
cd ~

# Clone the repository
git clone https://github.com/continuousactivelearning/vibe.git

# Enter the project directory
cd vibe

# Confirm you are in the right place — you should see these folders
ls
# Expected output includes: frontend/  backend/  self-hosting/  docker-compose.yml
```

Your project is now at `~/vibe/`.

---

## Phase 4 — Configure the Backend

The backend needs a configuration file that tells it your database URL, API keys, and other settings.

### Step 1 — Create the Backend Environment File

```bash
# You should be inside the vibe/ directory
cd ~/vibe

# Copy the example file to create your real config file
cp self-hosting/backend.env.example backend.env
```

### Step 2 — Edit the Backend Configuration

Open the file in a text editor:

```bash
# Using nano (simple terminal editor):
nano backend.env

# OR using vim:
# vi backend.env
```

Fill in the values using what you collected in Phase 1.

Here is a complete explanation of every setting:

```
# ─────────────────────────────────────────────────────────────────
# SERVER SETTINGS
# ─────────────────────────────────────────────────────────────────

NODE_ENV=production
```
> Leave this as `production`. This tells the app it's running in a live environment.

```
APP_PORT=8080
```
> The internal port the backend listens on. Do not change this.

```
APP_URL=http://YOUR_SERVER_IP:8080
```
> Replace `YOUR_SERVER_IP` with your actual server IP address.
> Example: `APP_URL=http://203.0.113.10:8080`
> If you have a domain: `APP_URL=https://api.yourdomain.com`

```
APP_ORIGINS=http://YOUR_SERVER_IP:3000
```
> This tells the backend which website is allowed to call it (CORS security).
> Replace with your frontend's address.
> Example: `APP_ORIGINS=http://203.0.113.10:3000`
> For multiple origins: `APP_ORIGINS=http://203.0.113.10:3000,https://yourdomain.com`

```
APP_ROUTE_PREFIX=/api
```
> All API endpoints start with `/api`. Do not change this.

```
APP_MODULE=all
```
> Loads all features. Do not change this.

```
FRONTEND_URL=http://YOUR_SERVER_IP:3000/teacher
```
> Used in emails sent to teachers. Replace with your frontend address + `/teacher`.
> Example: `FRONTEND_URL=http://203.0.113.10:3000/teacher`

```
ADMIN_PASSWORD=change_this_to_a_strong_password
```
> Choose a strong, unique password for the admin area.

```
# ─────────────────────────────────────────────────────────────────
# DATABASE
# ─────────────────────────────────────────────────────────────────

DB_URL=mongodb+srv://vibe_user:YOUR_PASSWORD@vibe-cluster.abc123.mongodb.net/?retryWrites=true&w=majority&appName=vibe-cluster
```
> Paste the full MongoDB Atlas connection string from Phase 1, Step 5.
> Make sure you replaced `<password>` with your actual database password.

```
DB_NAME=vibe
```
> The name of the database inside MongoDB. Keep as `vibe`.

```
# ─────────────────────────────────────────────────────────────────
# FIREBASE ADMIN SDK (Required for self-hosting)
# ─────────────────────────────────────────────────────────────────

GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json
```
> Points the Firebase Admin SDK to your service account JSON file (mounted into the container). Required because the production Docker image uses `applicationDefault()` which only works on Google Cloud without this.

```
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_API_KEY=your-api-key
FIREBASE_STORAGE_BUCKET=your-project.firebasestorage.app
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nYOUR_KEY_HERE\n-----END PRIVATE KEY-----\n"
```
> Copy `client_email` and `private_key` from the downloaded service account JSON. The `private_key` value must be on one line with `\n` (not real newlines).

```
# ─────────────────────────────────────────────────────────────────
# AI (ANTHROPIC CLAUDE)
# ─────────────────────────────────────────────────────────────────

ANTHROPIC_MODEL=claude-sonnet-4-20250514
```
> The AI model used for question generation. Keep this as-is unless advised to upgrade.

```
ANTHROPIC_CRED=sk-ant-api03-YOUR_KEY_HERE
```
> Paste your Anthropic API key from Phase 1.3.

```
# ─────────────────────────────────────────────────────────────────
# RECAPTCHA
# ─────────────────────────────────────────────────────────────────

RECAPTCHA_SECRET_KEY=YOUR_SECRET_KEY_HERE
IS_RECAPTCHA_ENABLED=true
```
> Paste your reCAPTCHA **Secret Key** (not the site key) from Phase 1.4.
> Set `IS_RECAPTCHA_ENABLED=false` if you want to skip reCAPTCHA for testing.
```

### Save and Exit

- In **nano**: Press `Ctrl + X`, then `Y`, then `Enter`
- In **vim**: Press `Esc`, type `:wq`, press `Enter`

### Verify the File

```bash
cat backend.env
```

Check that every `REQUIRED` field has a real value (no empty `=` signs for required fields).

---

## Phase 5 — Configure the Frontend

The frontend also needs a configuration file. This is slightly different because these values are **baked into the app at build time** — when Docker builds the frontend image, it reads this file and permanently embeds the values into the app's code.

> **Important:** If you ever change the frontend's `.env` file, you must rebuild the frontend Docker image with `docker-compose build frontend`.

### Step 1 — Create the Frontend Environment File

```bash
# The frontend config must be placed inside the frontend/ directory
cp self-hosting/frontend.env.example frontend/.env
```

### Step 2 — Edit the Frontend Configuration

```bash
nano frontend/.env
```

Fill in the values:

```
VITE_FIREBASE_API_KEY=AIzaSyABCDEF...
```
> Paste from Firebase Console (from Phase 1.2, Step 3).

```
VITE_FIREBASE_AUTH_DOMAIN=vibe-myschool.firebaseapp.com
```
> Your Firebase project ID followed by `.firebaseapp.com`.

```
VITE_FIREBASE_PROJECT_ID=vibe-myschool
```
> Your Firebase project ID (same as what you named the project).

```
VITE_FIREBASE_STORAGE_BUCKET=vibe-myschool.appspot.com
```
> Your Firebase project ID followed by `.appspot.com`.

```
VITE_FIREBASE_MESSAGING_SENDER_ID=123456789012
```
> A numeric value from the Firebase config block.

```
VITE_FIREBASE_APP_ID=1:123456789012:web:abcdef1234567890
```
> Starts with `1:` — from the Firebase config block.

```
VITE_FIREBASE_MEASUREMENT_ID=G-XXXXXXXXXX
```
> Optional Google Analytics ID. Leave empty if you don't use Analytics.

```
VITE_BASE_URL=/api
```
> **This is the most important setting.**
> This tells the frontend where to send API requests. Use `/api` — the nginx server proxies these requests to the backend internally. Do NOT use a full URL like `http://...` unless you have a custom setup.

```
VITE_RECAPTCHA_SITE_KEY=6Lc...
```
> Paste your reCAPTCHA **Site Key** (the public one) from Phase 1.4.

```
VITE_IS_RECAPTCHA_ENABLED=true
```
> Set to `true` to show the reCAPTCHA widget on sign-up. Set to `false` to hide it during testing.

Save and exit (`Ctrl + X`, `Y`, `Enter` in nano).

---

## Phase 6 — Build and Launch with Docker

You now have everything configured. This phase runs the entire application.

### Step 1 — Make Sure You Are in the Project Root

```bash
cd ~/vibe
ls   # You should see: docker-compose.yml, backend.env, frontend/, backend/, etc.
```

### Step 2 — Pull the Backend Image

The backend uses a pre-built Docker image, so you don't need to compile it yourself.

```bash
docker pull vicharanashala/vibe-backend:staging
```

This downloads the backend image from Docker Hub. It may take a few minutes.

### Step 2B — Set Up the Firebase Service Account File

Place the service account JSON file you downloaded in Phase 1.2 Step 5 in the project root:

```bash
# The file must be named exactly firebase-service-account.json
# and placed in the vibe/ directory (same folder as docker-compose.yml)
ls firebase-service-account.json  # Should exist
```

Then add it to `.gitignore` (it contains private keys — never commit it):
```bash
echo "firebase-service-account.json" >> .gitignore
```

Docker Compose mounts this file into the backend container automatically. The path `/app/firebase-service-account.json` inside the container is already configured by `GOOGLE_APPLICATION_CREDENTIALS`.

### Step 3 — Build the Frontend

The frontend must be built from source (because your Firebase and backend URL values get embedded into it).

```bash
docker compose build frontend
```

This will:
1. Download Node.js 20 (once, takes a minute)
2. Install all frontend dependencies (`pnpm install`)
3. Compile and bundle the React app with your configuration baked in
4. Package the result into a lightweight Nginx web server image

**Expected time:** 3–10 minutes depending on your server speed.

If you see warnings about peer dependencies — that is normal. Look only for errors (lines starting with `ERROR`).

### Step 4 — Start Everything

```bash
docker compose up -d
```

The `-d` flag runs everything in the background. You will see:

```
[+] Running 2/2
 ✔ Container vibe-backend   Started
 ✔ Container vibe-frontend  Started
```

### Step 5 — Check the Logs

Verify both services started successfully:

```bash
# Check backend logs
docker compose logs backend

# Check frontend logs
docker compose logs frontend

# Stream live logs (Ctrl+C to stop)
docker compose logs -f
```

**What to look for in backend logs:**

```
✅ Good:
  "Server started on port 8080"
  "Connected to MongoDB"
  "Loaded module: auth"
  "Loaded module: courses"
  ...

❌ Problems:
  "MongoNetworkError" → Check your DB_URL
  "Invalid API Key"   → Check ANTHROPIC_CRED
  "EADDRINUSE"        → Port 8080 is already in use
```

---

## Phase 7 — Verify Everything Works

### Check the Backend Health Endpoint

```bash
curl http://localhost:8080/health
```

Expected response:
```json
{"status":"ok"}
```

### Open the Frontend in Your Browser

Open a web browser and go to:

```
http://YOUR_SERVER_IP:3000
```

Replace `YOUR_SERVER_IP` with your actual server IP address.

You should see the ViBe login page.

### Test the Sign-Up Flow

1. Click **Sign Up** or **Register**
2. Enter an email and password
3. If reCAPTCHA is enabled, complete the challenge
4. You should be redirected to the dashboard

If sign-up succeeds, your entire setup is working correctly — Firebase authentication, the backend API, and MongoDB are all connected.

### Check Running Containers

```bash
docker compose ps
```

Expected output:
```
NAME             IMAGE                                    STATUS
vibe-backend     vicharanashala/vibe-backend:staging      Up X minutes (healthy)
vibe-frontend    vibe-frontend                            Up X minutes
```

The backend should show `(healthy)` after about 1 minute.

### View the API Documentation

The backend exposes an interactive API reference at:

```
http://YOUR_SERVER_IP:8080/reference
```

This shows all available API endpoints and lets you test them directly.

---

## Phase 8 — Set Up a Domain and HTTPS (Recommended)

For production use, you should:
1. Point a domain name to your server's IP
2. Install SSL/TLS certificates for HTTPS

This is optional for testing but strongly recommended for real users because:
- Browsers may block HTTP connections to mixed content
- Login pages should always use HTTPS
- reCAPTCHA requires HTTPS for production keys

### Option A — Using Nginx + Certbot (Let's Encrypt, Free SSL)

**Step 1: Install Nginx**

```bash
sudo apt install nginx -y
```

**Step 2: Create Nginx Configuration**

```bash
sudo nano /etc/nginx/sites-available/vibe
```

Paste the following (replace `yourdomain.com` with your actual domain):

```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    # Frontend — serve the React app
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # Backend API — route /api requests to the backend
    location /api {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

**Step 3: Enable the Site**

```bash
sudo ln -s /etc/nginx/sites-available/vibe /etc/nginx/sites-enabled/
sudo nginx -t          # Test config — should print "test is successful"
sudo systemctl reload nginx
```

**Step 4: Install Certbot and Get SSL**

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

Follow the prompts. Certbot will automatically modify your Nginx config to use HTTPS.

**Step 5: Update Your Configuration**

Once HTTPS is set up, update your config files:

In `backend.env`:
```
APP_URL=https://yourdomain.com
APP_ORIGINS=https://yourdomain.com
FRONTEND_URL=https://yourdomain.com/teacher
```

In `frontend/.env`:
```
VITE_BASE_URL=https://yourdomain.com/api
```

Then rebuild and restart:
```bash
docker compose build frontend
docker compose up -d
```

### Option B — Cloudflare Tunnel (No Port Opening Required)

If you cannot open ports on your server, use a Cloudflare Tunnel which provides HTTPS automatically without any certificate setup.

1. Sign up at [cloudflare.com](https://cloudflare.com)
2. Add your domain to Cloudflare
3. Follow the [Cloudflare Tunnel setup guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)

---

## Phase 9 — AI Server Setup

> **Is this phase required?**
> Only if you want ViBe to process **video URLs automatically** (full pipeline: video → audio → transcript → quiz). If you only need the simple "paste a transcript, generate questions" feature, skip this phase — that is handled by Phase 1.3 (Anthropic API or LM Studio via LiteLLM).

---

### Understanding ViBe's Two AI Systems

ViBe has **two completely separate AI systems**. They serve different purposes and can be set up independently.

| | System 1 — Video Pipeline | System 2 — Manual Transcript |
|---|---|---|
| **What it does** | Takes a video URL → extracts audio → transcribes → segments → generates quiz | Teacher pastes a transcript → AI generates questions directly |
| **Who triggers it** | Teacher provides a video URL in ViBe | Teacher clicks "Generate Questions" on a text transcript |
| **Components needed** | vibe-ai Python server + LM Studio | Anthropic API **or** LM Studio + LiteLLM |
| **Where it runs** | Separate server (can be same machine) | Inside ViBe's backend container |
| **env variables used** | `AI_SERVER_IP`, `AI_SERVER_PORT` | `ANTHROPIC_CRED`, `ANTHROPIC_MODEL` |
| **Setup complexity** | Advanced | Simple |
| **Optional?** | Yes — skip if you don't need video processing | No — needed for AI quiz generation |

---

### Architecture — Both Systems Together

```
┌───────────────────────────────────────────────────────────────────┐
│                      ViBe Backend (Docker)                         │
│                                                                     │
│  Teacher uploads video URL                                          │
│        │                                                            │
│        ▼  HTTP POST to AI_SERVER_IP:8017                           │
│  ┌─────────────────┐         Teacher pastes transcript             │
│  │  genAI module   │                 │                             │
│  │  (System 1)     │                 ▼                             │
│  └────────┬────────┘         ┌───────────────┐                    │
│           │                  │  QuestionSvc  │                     │
│           │                  │  (System 2)   │                     │
│           │                  └───────┬───────┘                     │
└───────────┼──────────────────────────┼─────────────────────────────┘
            │                          │
            ▼                          ▼
  ┌──────────────────┐       ┌──────────────────────┐
  │  vibe-ai Server  │       │  Option A:            │
  │  (Python)        │       │  Anthropic Cloud API  │
  │  port 8017       │       │  (claude-sonnet)      │
  │                  │       └──────────────────────┘
  │  ┌─────────────┐ │       ┌──────────────────────┐
  │  │   Whisper   │ │       │  Option B:            │
  │  │  (ONNX)     │ │       │  LiteLLM Proxy        │
  │  └─────────────┘ │       │  → LM Studio          │
  │  ┌─────────────┐ │       │  → Local LLM Model    │
  │  │   SEGBOT    │ │       └──────────────────────┘
  │  │  (ONNX)     │ │
  │  └─────────────┘ │
  │  ┌─────────────┐ │
  │  │  LLM call   │─┼──────→  LM Studio (port 1234)
  │  │  (questions)│ │          Local Model
  │  └─────────────┘ │          (DeepSeek R1, Llama, etc.)
  └──────────────────┘
```

---

### System 1 — Full Video Pipeline (vibe-ai + LM Studio)

This is the advanced setup. The vibe-ai server processes a video through a 5-step pipeline:

```
Step 1 — Audio Extraction        Pulls audio track from the video URL
Step 2 — Transcript Generation   Whisper (ONNX) converts audio → text
Step 3 — Segmentation            SEGBOT (ONNX) splits transcript into topics
Step 4 — Question Generation     LLM (LM Studio) generates quiz questions
Step 5 — Upload Content          Creates course items + quizzes in ViBe
```

> **Note:** Steps 1–3 use ONNX models that run locally inside vibe-ai (no LM Studio needed for those). Only Step 4 (Question Generation) uses LM Studio.

#### Hardware Requirements for System 1

| Component | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 8 cores |
| RAM | 16 GB | 32 GB |
| GPU (for LLM) | 8 GB VRAM | 16+ GB VRAM |
| Disk | 30 GB | 60 GB |
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |

> System 1 can run on the **same machine as ViBe** or on a **completely separate server**. A separate GPU-equipped server gives the best performance.

#### Recommended Models for Video Question Generation

Question generation from video transcripts requires models that follow complex JSON output instructions reliably:

| Model | Size | RAM/VRAM Needed | Quality | Notes |
|---|---|---|---|---|
| DeepSeek R1 Distill Qwen 7B | ~5 GB | 8 GB | Very Good | Best small model for structured output |
| DeepSeek R1 Distill Llama 8B | ~5 GB | 8 GB | Very Good | Strong reasoning |
| Mistral Nemo 12B | ~7 GB | 12 GB | Excellent | Great JSON adherence |
| Qwen 2.5 14B Instruct | ~9 GB | 16 GB | Excellent | Best quality mid-size |
| DeepSeek R1 70B | ~43 GB | 48 GB VRAM | Near-Claude | For high-end servers |
| Llama 3.3 70B Instruct | ~43 GB | 48 GB VRAM | Near-Claude | Best overall |

**Recommended starting point:** `DeepSeek R1 Distill Qwen 7B` — small enough for most servers, strong enough for structured JSON quiz generation.

---

#### Step 1 — Install LM Studio on the AI Server Machine

**Linux Server (Headless — no desktop required):**

```bash
# Download and install the LM Studio CLI
curl -fsSL https://files.lmstudio.ai/install.sh | bash

# Apply to current session
source ~/.bashrc

# Confirm installation
lms version
```

**macOS or Windows (Desktop GUI):**

Download and install from [https://lmstudio.ai](https://lmstudio.ai).

---

#### Step 2 — Download a Model in LM Studio

**Linux CLI:**

```bash
# Search available models
lms search deepseek-r1-distill-qwen-7b

# Download (copy the exact model ID from search results)
lms get "lmstudio-community/DeepSeek-R1-Distill-Qwen-7B-GGUF/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf"
```

**macOS/Windows GUI:**

1. Open LM Studio → click Search (magnifying glass)
2. Search `deepseek-r1-distill-qwen-7b`
3. Download the `Q4_K_M` GGUF version

---

#### Step 3 — Start LM Studio Server

LM Studio exposes an **OpenAI-compatible API** on port 1234. The vibe-ai Python server uses this API to call the LLM for question generation.

**Linux CLI:**

```bash
# Load the model using GPU (remove --gpu max if no GPU)
lms load "DeepSeek-R1-Distill-Qwen-7B-Q4_K_M" --gpu max

# Start the server
lms server start --port 1234

# Confirm it is running
curl http://localhost:1234/v1/models
```

Expected response — a JSON object listing the loaded model.

**macOS/Windows GUI:**

1. Click the **Local Server** icon (`⇌`) in LM Studio
2. Select your model in the dropdown
3. Click **Start Server**
4. Confirm: `Server running at http://localhost:1234`

---

#### Step 4 — Clone and Set Up the vibe-ai Server

The vibe-ai server is a separate Python application. Clone it on the same machine where LM Studio is running.

```bash
# Clone the vibe-ai repository
git clone https://github.com/vicharanashala/vibe-ai.git
cd vibe-ai

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate        # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

---

#### Step 5 — Configure vibe-ai to Use LM Studio

vibe-ai uses an **OpenAI-compatible API endpoint** to call the LLM. Since LM Studio exposes exactly that on port 1234, you point vibe-ai at LM Studio.

In the vibe-ai project directory, create or edit its environment/config file. Look for a `.env` file or `config.yaml` — refer to the [vibe-ai README](https://github.com/vicharanashala/vibe-ai) for the exact file name. Set the LLM endpoint to LM Studio:

```dotenv
# vibe-ai configuration — point LLM calls to LM Studio
LLM_BASE_URL=http://localhost:1234/v1
LLM_API_KEY=not-needed

# Default model name — must match the loaded model in LM Studio
# Use the exact model identifier shown in: curl http://localhost:1234/v1/models
LLM_DEFAULT_MODEL=DeepSeek-R1-Distill-Qwen-7B-Q4_K_M
```

> The exact variable names (`LLM_BASE_URL`, `LLM_API_KEY`, etc.) depend on the vibe-ai codebase. Check the vibe-ai repository's `.env.example` or README for the correct names.

---

#### Step 6 — Start the vibe-ai Server

```bash
# Make sure virtual environment is active
source venv/bin/activate

# Start vibe-ai (default port 8017)
python main.py
# or
uvicorn main:app --host 0.0.0.0 --port 8017
```

Refer to the vibe-ai README for the exact start command.

**Verify vibe-ai is running:**

```bash
curl http://localhost:8017/health
```

Expected: a JSON response confirming the server is up.

---

#### Step 7 — Configure ViBe Backend to Connect to vibe-ai

Open `backend.env` and fill in the AI server variables:

```dotenv
# ── AI SERVER (System 1 — Video Pipeline) ─────────────────────────

# IP address of the machine running vibe-ai
# If vibe-ai runs on the SAME machine as ViBe:
AI_SERVER_IP=host.docker.internal
# If vibe-ai runs on a DIFFERENT server (replace with that server's IP):
# AI_SERVER_IP=192.168.1.50

# Port vibe-ai listens on (default 8017, do not change unless vibe-ai config changes)
AI_SERVER_PORT=8017

# SOCKS5 proxy — only needed if using Tailscale VPN to reach vibe-ai
# If vibe-ai is on the same machine or same network, leave this commented out
# AI_PROXY_ADDRESS=socks5h://localhost:1055

# Tailscale auth key — only needed if using Tailscale VPN
# TAILSCALE_AUTHKEY=tskey-auth-...
```

> **Same machine vs separate server:**
> - If vibe-ai runs on the **same machine** as ViBe's Docker containers, use `AI_SERVER_IP=host.docker.internal`
> - If vibe-ai runs on a **different server**, use that server's actual IP address

Then restart the ViBe backend:

```bash
docker compose up -d backend
```

---

#### Step 8 — Test the Full Video Pipeline

1. Log in to ViBe as a teacher
2. Create a course and go to **Add Content**
3. Choose **Video** and enter a YouTube or direct video URL
4. Click **Generate with AI**
5. The genAI job panel opens — you will see the pipeline steps

**Watch the logs while it runs:**

```bash
# ViBe backend logs (shows HTTP calls to vibe-ai)
docker compose logs -f backend

# vibe-ai server logs (shows each pipeline step)
# (on the vibe-ai machine)
tail -f vibe-ai.log
```

**Expected flow:**

| Step | Status shown in ViBe | Time |
|---|---|---|
| Audio Extraction | Processing… → Complete | 30–60 sec |
| Transcript Generation | Processing… → Complete | 1–5 min |
| Segmentation | Processing… → Complete | 10–30 sec |
| Question Generation | Processing… → Complete | 1–5 min (LM Studio) |
| Upload Content | Processing… → Complete | 10–30 sec |

When all steps are green, refresh the course — video items and quizzes are automatically created.

---

#### Keep LM Studio and vibe-ai Running Automatically (Linux)

**LM Studio as a systemd service:**

```bash
sudo nano /etc/systemd/system/lmstudio.service
```

```ini
[Unit]
Description=LM Studio Local Server
After=network.target

[Service]
Type=simple
User=YOUR_USERNAME
ExecStartPre=/home/YOUR_USERNAME/.lmstudio/bin/lms load "DeepSeek-R1-Distill-Qwen-7B-Q4_K_M" --gpu max
ExecStart=/home/YOUR_USERNAME/.lmstudio/bin/lms server start --port 1234
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**vibe-ai as a systemd service:**

```bash
sudo nano /etc/systemd/system/vibe-ai.service
```

```ini
[Unit]
Description=ViBe AI Pipeline Server
After=network.target lmstudio.service
Requires=lmstudio.service

[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME/vibe-ai
ExecStart=/home/YOUR_USERNAME/vibe-ai/venv/bin/python main.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable both:

```bash
sudo systemctl daemon-reload
sudo systemctl enable lmstudio vibe-ai
sudo systemctl start lmstudio vibe-ai

# Check status
sudo systemctl status lmstudio
sudo systemctl status vibe-ai
```

---

#### System 1 Troubleshooting

**ViBe backend shows "AI server unreachable"**

```bash
# Test from inside the backend container
docker exec -it vibe-backend wget -qO- http://host.docker.internal:8017/health
```

If this fails:
- Confirm vibe-ai is running: `curl http://localhost:8017/health` on the vibe-ai machine
- If using `host.docker.internal`, ensure docker-compose has `extra_hosts` configured on the backend service, or use the actual IP

Add this to the `backend` service in `docker-compose.yml` if needed:
```yaml
backend:
  extra_hosts:
    - "host.docker.internal:host-gateway"
```

---

**vibe-ai cannot reach LM Studio**

```bash
# Test on the vibe-ai machine
curl http://localhost:1234/v1/models
```

If no response: LM Studio server is not running. Start it with `lms server start --port 1234`.

---

**Question generation fails or returns empty**

- The model is not loaded in LM Studio → check `lms list` to see loaded models
- The model name in vibe-ai config does not match → verify with `curl http://localhost:1234/v1/models`
- The model is too small for the transcript length → try a larger model (14B+)
- Increase LM Studio timeout in its settings if transcripts are very long

---

**Transcription step fails**

This step uses Whisper (ONNX) — it does not use LM Studio. If it fails:
- Check vibe-ai logs for Whisper model errors
- Ensure the ONNX model files are present in the vibe-ai directory
- Check the vibe-ai README for Whisper model download instructions

---

### System 2 — Manual Transcript Path (Anthropic or LM Studio)

This is the simpler AI path. The teacher pastes a text transcript directly into ViBe and clicks **Generate Questions**. The backend calls an LLM once and returns structured quiz questions.

**Two options — choose one:**

**Option A — Anthropic Cloud API (Claude)**
Already documented in [Section 1.3](#13-anthropic--ai-question-generation-cloud-api).

Summary of what to set in `backend.env`:
```dotenv
ANTHROPIC_MODEL=claude-sonnet-4-20250514
ANTHROPIC_CRED=sk-ant-api03-YOUR_KEY
# Do NOT set ANTHROPIC_BASE_URL
```

---

**Option B — LM Studio (Free, Local)**
Already documented in [Section 1.3 Alternative](#13-alternative--local-llm-with-lm-studio-free-no-api-costs).

Summary of what to set in `backend.env`:
```dotenv
ANTHROPIC_MODEL=claude-sonnet-4-20250514
ANTHROPIC_CRED=local-llm-no-key-needed
ANTHROPIC_BASE_URL=http://litellm:4000     # Points to LiteLLM proxy
```

LiteLLM translates ViBe's Anthropic SDK calls into OpenAI-compatible calls that LM Studio understands. See Section 1.3 Alternative for the full setup with `litellm_config.yaml`.

---

### Quick Decision Guide — Which AI Setup Do You Need?

```
Do you want ViBe to process raw video URLs automatically?
  │
  ├── YES → Set up System 1 (Phase 9 above: vibe-ai + LM Studio)
  │          Also set up System 2 for manual transcript fallback
  │
  └── NO → Only set up System 2:
            │
            ├── Want free, local, private AI?
            │     → Use LM Studio + LiteLLM (Section 1.3 Alternative)
            │
            └── Want easiest setup, don't mind paying per-use?
                  → Use Anthropic Claude API (Section 1.3)
```

---

## Database Reference

### How the Database Works

ViBe uses **MongoDB**, a document database. Unlike traditional SQL databases:
- You do **not** need to create tables or schemas manually
- Collections (equivalent to tables) are created automatically when the app first writes data to them
- Each document (record) can have a flexible structure

When ViBe starts for the first time and someone signs up, it creates the first documents in each collection. All collections are created automatically.

### Collections (Auto-Created by ViBe)

| Collection Name | What It Stores | Created When |
|---|---|---|
| `users` | All user accounts (teachers, students, admins) | First sign-up |
| `courses` | Course definitions, titles, descriptions | First course created |
| `courseitems` | Individual items inside courses (videos, quizzes, text) | First item added |
| `enrollments` | Which students are enrolled in which courses | First enrollment |
| `quizzes` | Quiz definitions and question banks | First quiz created |
| `quizattempts` | Student answers and scores | First quiz taken |
| `emotions` | Student emotion data during learning sessions | First emotion recorded |
| `notifications` | Email notifications and invites | First notification sent |
| `anomalies` | Detected integrity violations | First anomaly detected |
| `reports` | Analytics and progress reports | First report generated |
| `audittrails` | Log of all system actions for compliance | First action logged |
| `announcements` | Course announcements from teachers | First announcement |
| `settings` | User and course settings | First settings saved |

### Viewing Your Database

You can view and manage your MongoDB data through:

1. **MongoDB Atlas Web UI** — Go to your Atlas cluster → Browse Collections
2. **MongoDB Compass** (desktop app) — Connect using your `DB_URL`
3. **mongosh** (command line) — `mongosh "YOUR_DB_URL"`

### Database Backups

**Manual backup using mongodump:**
```bash
# Install mongodump
sudo apt install mongodb-database-tools -y

# Create a backup
mongodump --uri="YOUR_DB_URL" --out=./backup-$(date +%Y%m%d)
```

**Automatic backups via ViBe:**

If you set `ENABLE_DB_BACKUP=true` in `backend.env` along with GCP bucket names, ViBe will automatically back up your database daily to Google Cloud Storage.

---

## Updating ViBe to a New Version

This section explains exactly what to do every time the ViBe codebase is updated — whether it is a bug fix, a new feature, a config change, or a new environment variable.

---

### How Updates Work in ViBe (Docker Flow)

When a developer pushes new code to the ViBe repository, this is what happens automatically:

```
Developer pushes code to GitHub
          │
          ▼
GitHub Actions CI/CD runs
          │
          ├── Backend changed?  → Builds new Docker image
          │                       Pushes to Docker Hub as:
          │                       vicharanashala/vibe-backend:staging
          │
          └── Frontend changed? → You rebuild locally
                                  (because your Firebase + API URLs
                                   are baked into YOUR build)
```

As a self-hoster, you need to:
- **Backend updates** → pull the new image from Docker Hub, restart container
- **Frontend updates** → pull new code, rebuild your Docker image, restart container
- **New env variable added** → add it to `backend.env` or `frontend/.env`, then restart

---

### What Kind of Change Needs What Action?

Use this table every time you update to know exactly what steps to run:

| What changed in the new version | Action needed |
|---|---|
| Backend code only (bug fix, new API) | Pull new Docker image → restart backend |
| Frontend code only (UI change, new page) | Pull code → rebuild frontend image → restart frontend |
| Both backend and frontend changed | Do both above |
| New env variable added to backend | Add variable to `backend.env` → restart backend (no rebuild) |
| New env variable added to frontend | Add variable to `frontend/.env` → rebuild frontend image → restart |
| `docker-compose.yml` changed | Pull code → `docker compose up -d` (Docker re-reads the file) |
| Database schema change | Nothing — MongoDB is schema-less, ViBe handles this automatically on startup |

---

### Step 1 — Read the Changelog Before Updating

Always check what changed before applying an update. This prevents surprises.

```bash
cd ~/vibe

# See what commits are new since your current version
git fetch origin
git log HEAD..origin/main --oneline
```

Or check the GitHub releases page for release notes.

**Look specifically for:**
- Lines mentioning `new env variable` or `add to .env` → you must add that variable before restarting
- Lines mentioning `breaking change` → read carefully before proceeding
- Lines mentioning `database migration` → check if any manual steps are needed

---

### Step 2 — Back Up Your Database First

Always take a backup before any update. If something goes wrong, you can restore.

```bash
# Install mongodump if not already installed
sudo apt install mongodb-database-tools -y

# Create a timestamped backup
mongodump --uri="YOUR_DB_URL_FROM_backend.env" --out=./backup-before-update-$(date +%Y%m%d-%H%M%S)

# Confirm backup was created
ls -lh ./backup-before-update-*/
```

---

### Step 3 — Pull the Latest Code

```bash
cd ~/vibe
git pull origin main
```

Check what files changed:

```bash
git diff HEAD~1 --name-only
```

This lists every file that was modified. Use the table above to decide what steps to run next.

---

### Step 4 — Check for New Environment Variables

Every time code is updated, check if new environment variables were added.

```bash
# Compare your current backend.env against the latest example
diff backend.env self-hosting/backend.env.example

# Compare your frontend .env against the latest example
diff frontend/.env self-hosting/frontend.env.example
```

Any line that exists in the `.example` file but NOT in your `.env` file is a **new variable you must add**.

Open your env file and add the missing variables:

```bash
nano backend.env
# or
nano frontend/.env
```

---

### Step 5A — Update the Backend

The backend uses a pre-built Docker image from Docker Hub. Updating it is just pulling the new image.

```bash
# Pull the latest backend image
docker pull vicharanashala/vibe-backend:staging

# Restart the backend container with the new image
docker compose up -d backend

# Confirm the new image is running
docker compose ps
docker compose logs --tail=30 backend
```

**What to look for in logs after update:**
```
✅ Good:  "Server started on port 8080"
✅ Good:  "Connected to MongoDB"
❌ Error: "Unknown config key: ..." → new required env variable missing, add it to backend.env
❌ Error: "MongoNetworkError"       → DB connection issue, unrelated to this update
```

---

### Step 5B — Update the Frontend

The frontend must be **rebuilt** every time the frontend code changes, because your Firebase and backend URL values are permanently baked into the compiled JavaScript.

```bash
# Rebuild the frontend Docker image with your current frontend/.env values
docker compose build frontend

# Restart the frontend container with the new image
docker compose up -d frontend

# Confirm it is running
docker compose logs --tail=20 frontend
```

> **Important:** If you also added new variables to `frontend/.env` in Step 4, this rebuild will pick them up automatically.

---

### Step 5C — Restart Everything (Simplest Option)

If you are unsure what changed, or if both frontend and backend changed, just restart everything at once:

```bash
# Pull new backend image
docker pull vicharanashala/vibe-backend:staging

# Rebuild frontend
docker compose build frontend

# Bring everything down and back up
docker compose down
docker compose up -d

# Watch startup logs
docker compose logs -f
```

---

### Step 6 — Verify the Update

```bash
# Check all containers are running
docker compose ps

# Test backend health
curl http://localhost:8080/health

# Check what image version the backend is running
docker inspect vibe-backend --format='{{.Config.Image}}'
```

Open the frontend in your browser and confirm the new features or fixes are present.

---

### How to Roll Back If Something Breaks

If the update causes problems, you can roll back to the previous version immediately.

**Roll back the backend to the previous image:**

```bash
# Docker keeps the previously pulled image cached locally
# Find the image ID of the previous version
docker images vicharanashala/vibe-backend

# Output example:
# REPOSITORY                      TAG       IMAGE ID       CREATED
# vicharanashala/vibe-backend     staging   a1b2c3d4e5f6   2 hours ago
# vicharanashala/vibe-backend     staging   9z8y7x6w5v4u   3 days ago

# Tag the previous image so docker compose can use it
docker tag 9z8y7x6w5v4u vicharanashala/vibe-backend:rollback

# Edit docker-compose.yml temporarily to use the rollback tag
# Change:  image: vicharanashala/vibe-backend:staging
# To:      image: vicharanashala/vibe-backend:rollback

# Restart with old image
docker compose up -d backend
```

**Roll back the frontend to the previous build:**

```bash
# Go back one commit in git
git checkout HEAD~1 -- frontend/

# Rebuild the previous frontend
docker compose build frontend
docker compose up -d frontend
```

**Restore the database from backup:**

```bash
# Find your backup directory
ls ./backup-before-update-*/

# Restore (replace BACKUP_DIR with the actual folder name)
mongorestore --uri="YOUR_DB_URL_FROM_backend.env" ./backup-before-update-YYYYMMDD-HHMMSS/
```

---

### Automated One-Command Update Script

Save this as `update.sh` in your project root for quick updates:

```bash
nano ~/vibe/update.sh
```

Paste:

```bash
#!/bin/bash
set -e

echo "=== ViBe Update Script ==="
echo ""

# Step 1: Pull latest code
echo "[1/5] Pulling latest code from git..."
git pull origin main

# Step 2: Check for new env variables
echo ""
echo "[2/5] Checking for new environment variables..."
echo "--- backend.env diff (lines in example but not in your file) ---"
diff <(grep -v '^#' self-hosting/backend.env.example | grep '=') \
     <(grep -v '^#' backend.env | grep '=') || true
echo "--- If you see lines above, add them to backend.env before continuing ---"
echo ""
read -p "Press ENTER when your env files are up to date..."

# Step 3: Pull new backend image
echo "[3/5] Pulling latest backend Docker image..."
docker pull vicharanashala/vibe-backend:staging

# Step 4: Rebuild frontend
echo "[4/5] Rebuilding frontend..."
docker compose build frontend

# Step 5: Restart all services
echo "[5/5] Restarting all services..."
docker compose down
docker compose up -d

echo ""
echo "=== Update complete! ==="
docker compose ps
```

Make it executable:

```bash
chmod +x ~/vibe/update.sh
```

Run it any time there is an update:

```bash
cd ~/vibe
./update.sh
```

---

### Keeping Track of Which Version You Are Running

```bash
# See the current git commit your code is on
git log -1 --oneline

# See when the currently running backend image was built
docker inspect vibe-backend --format='Built: {{.Created}}'

# See the full image details
docker inspect vibe-backend --format='{{.Config.Image}} — {{.Created}}'
```

---

## Troubleshooting

### Problem: The backend container keeps restarting

**Symptoms:** `docker compose ps` shows `Restarting` for `vibe-backend`

**Solution:**
```bash
docker compose logs backend
```
Look at the last few lines for the error. Most common causes:
- Missing or wrong `DB_URL` → check MongoDB connection string
- Wrong `ANTHROPIC_CRED` → verify your API key
- Port 8080 already in use → run `sudo lsof -i :8080` to find what's using it

---

### Problem: "Cannot connect to MongoDB" error in logs

**Symptoms:** Log shows `MongoNetworkError` or `MongoServerSelectionError`

**Solutions:**
1. Check that `DB_URL` in `backend.env` has the correct password (no `<` `>` brackets around it)
2. In MongoDB Atlas → Network Access → make sure your server IP or `0.0.0.0/0` is whitelisted
3. Test the connection string directly:
   ```bash
   docker run --rm -it mongo:7.0 mongosh "YOUR_DB_URL" --eval "db.adminCommand('ping')"
   ```

---

### Problem: The login page loads but sign-up fails

**Symptoms:** User submits the sign-up form but gets an error

**Solutions:**
1. Check that your Firebase project has **Email/Password** authentication enabled
2. Check that the domain or IP you're accessing the site from is in Firebase → Authentication → Settings → Authorized Domains
3. Check that all `VITE_FIREBASE_*` values in `frontend/.env` are correct
4. Rebuild the frontend if you made changes: `docker compose build frontend && docker compose up -d`

---

### Problem: "API not reachable" or blank page in the app

**Symptoms:** The frontend loads but no data appears, or the browser console shows CORS/network errors

**Solutions:**
1. Verify the backend is running: `curl http://localhost:8080/health`
2. Check that `VITE_BASE_URL` in `frontend/.env` matches the actual backend URL
3. Check that `APP_ORIGINS` in `backend.env` includes your frontend URL
4. Rebuild after any env changes: `docker compose build frontend && docker compose up -d`

---

### Problem: "Port already in use" error

**Symptoms:** `Error: bind: address already in use` when starting containers

**Solution:**
```bash
# Find what is using the port (replace 3000 with the conflicting port)
sudo lsof -i :3000

# Stop the process (replace PID with the actual process ID from above)
sudo kill -9 PID

# Or, change the ports in docker-compose.yml:
# "3000:80"  →  "8081:80"   (for frontend)
# "8080:8080" → "9090:8080" (for backend)
# Then update VITE_BASE_URL and APP_ORIGINS accordingly
```

---

### Problem: Build fails with "JavaScript heap out of memory"

**Symptoms:** `docker compose build frontend` fails with memory error

**Solution:** The frontend has many dependencies and needs extra memory. Increase Docker's memory limit:

On **macOS/Windows**: Open Docker Desktop → Settings → Resources → Memory → increase to 8 GB+

On **Linux**, add this to `docker-compose.yml` under the `frontend` build:
```yaml
frontend:
  build:
    context: .
    dockerfile: frontend/Dockerfile
    shm_size: '2gb'
```

Note: The Dockerfile already sets `NODE_OPTIONS=--max-old-space-size=8192`. If you still get OOM errors, increase Docker Desktop's memory limit to 8 GB+ in Settings → Resources → Memory.

---

### Problem: All API calls return 401 "Authorization is required"

**Symptoms:** After logging in, the app loads but shows "Failed to load courses" or "Authorization is required" on every page.

**Cause:** The backend cannot verify Firebase tokens because the Firebase Admin SDK credentials are missing or not mounted correctly.

**Solution:**
1. Confirm `firebase-service-account.json` exists in the project root: `ls firebase-service-account.json`
2. Confirm `GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json` is in `backend.env`
3. Confirm the volume mount exists in `docker-compose.yml` under the backend service:
   ```yaml
   volumes:
     - ./firebase-service-account.json:/app/firebase-service-account.json:ro
   ```
4. Restart the backend: `docker compose up -d backend`
5. Check backend logs for Firebase errors: `docker compose logs --tail=50 backend`

---

### Problem: Changes to environment variables have no effect

**Cause:** Frontend environment variables are embedded at build time, not runtime.

**Solution:** After any change to `frontend/.env`:
```bash
docker compose build frontend
docker compose up -d frontend
```

After any change to `backend.env`:
```bash
docker compose up -d backend
```

---

### Viewing Container Logs

```bash
# View last 100 lines of backend logs
docker compose logs --tail=100 backend

# Stream live logs from both containers
docker compose logs -f

# View all logs since a specific time
docker compose logs --since="2024-01-01T00:00:00" backend
```

---

### Restarting Individual Services

```bash
# Restart only the backend
docker compose restart backend

# Restart only the frontend
docker compose restart frontend

# Stop everything
docker compose down

# Start everything again
docker compose up -d
```

---

## Quick Command Reference

| What to do | Command |
|---|---|
| Start all services | `docker compose up -d` |
| Stop all services | `docker compose down` |
| Restart backend | `docker compose restart backend` |
| Rebuild frontend | `docker compose build frontend` |
| View backend logs | `docker compose logs backend` |
| View live logs | `docker compose logs -f` |
| Check container status | `docker compose ps` |
| Test backend health | `curl http://localhost:8080/health` |
| Pull latest backend image | `docker pull vicharanashala/vibe-backend:staging` |
| Update entire deployment | `git pull && docker pull vicharanashala/vibe-backend:staging && docker compose build frontend && docker compose up -d` |
| Enter backend container (debug) | `docker exec -it vibe-backend sh` |

---

## Default Ports Summary

| Service | Port | Accessible at |
|---|---|---|
| Frontend (web app) | 3000 | `http://YOUR_SERVER_IP:3000` |
| Backend API | 8080 | `http://YOUR_SERVER_IP:8080/api` |
| API Documentation | 8080 | `http://YOUR_SERVER_IP:8080/reference` |
| MongoDB (if local) | 27017 | Only accessible internally |

---

## File Structure After Setup

After completing this guide, your project directory should look like this:

```
vibe/
├── docker-compose.yml
├── backend.env                        ← Your backend secrets (DO NOT commit)
├── firebase-service-account.json      ← Firebase Admin key (DO NOT commit)
├── frontend/
│   ├── .env                           ← Your frontend config (DO NOT commit)
│   └── ... (source code)
├── backend/
│   └── ... (source code)
└── self-hosting/
    ├── DEPLOYMENT_GUIDE.md     ← This guide
    ├── backend.env.example     ← Template for backend.env
    └── frontend.env.example    ← Template for frontend/.env
```

> **Security reminder:** Never commit `backend.env` or `frontend/.env` to version control. They contain API keys and database passwords. Both files are already listed in `.gitignore`.

---

*For support, open an issue at the ViBe GitHub repository or contact [dled@iitrpr.ac.in](mailto:dled@iitrpr.ac.in).*
