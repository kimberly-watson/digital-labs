# Sonatype Digital Lab — Customer Guide

Welcome to your Sonatype Digital Lab. This guide covers everything you need to get started.

---

## Getting Started

You will receive a welcome email from Sonatype with a single link to your **Lab Portal**. Click that link to open the portal in your browser. Everything you need is accessible from there — no VPN, no software installation required.

> **Allow up to 10 minutes after receiving your welcome email for all services to finish starting up.**

---

## The Lab Portal

The portal is your home base. It shows:

- **Countdown timer** — how much time remains before your lab is automatically shut down
- **Quick-launch buttons** for Nexus Repository and IQ Server
- **Lab Tutor** — an AI assistant you can ask questions at any time (chat bubble, bottom-right corner)

---

## Lab Services

### Nexus Repository

Click **Nexus Repository** on the portal to open it in a new tab.

Nexus Repository is Sonatype's artifact management platform. In your lab it comes pre-configured with:

| Repository | Type | Purpose |
|---|---|---|
| `maven-hosted-lab` | Maven hosted | Upload and store Maven artifacts |
| `npm-hosted-lab` | npm hosted | Upload and store npm packages |
| `maven-proxy-central` | Maven proxy | Proxy to Maven Central |

**To sign in:**
1. Click **Sign in** in the top-right corner
2. Username: `admin`
3. Password: `admin123`

### IQ Server (Lifecycle & Firewall)

Click **IQ Server** on the portal to open it in a new tab.

IQ Server provides software composition analysis, policy enforcement, and firewall capabilities. Your lab license covers all seven Sonatype products.

**To sign in:**
1. Username: `admin`
2. Password: `admin123`

---

## Lab Tutor

The **Lab Tutor** is an AI assistant powered by Claude. Click the chat bubble (&#129302;) in the bottom-right corner of the portal to open it.

You can ask the tutor:
- How to navigate Nexus or IQ Server
- What specific features do and how to use them
- Questions about your lab environment (URLs, credentials, time remaining)
- Sonatype product concepts and terminology

The tutor is context-aware — it knows your lab's URLs, credentials, and expiry time, so you do not need to look those up.

---

## Lab Expiry

Your lab will automatically shut down at the time shown on the portal countdown timer. You will receive a reminder email **48 hours before** your lab expires.

**Before your lab expires:**
- Export or download any work you want to keep
- Note any configurations you want to recreate
- Contact your Sonatype representative if you need more time

> Once the lab shuts down, all data is permanently deleted and cannot be recovered.

---

## Frequently Asked Questions

**The portal loaded but Nexus or IQ Server shows an error.**
Services can take up to 10 minutes to fully start after the lab is provisioned. Wait a few minutes and try again. You can also ask the Lab Tutor to check service status.

**I forgot my password.**
Default credentials are always `admin` / `admin123`. These are set automatically and do not change.

**The countdown timer shows "--".**
Refresh the page. If it continues, the timer service may still be starting up — wait 2–3 minutes.

**I need more time.**
Contact your Sonatype representative before your lab expires. Extensions must be arranged in advance.

**I have a question the Lab Tutor can't answer.**
Reach out to your Sonatype contact directly.

---

*Sonatype Customer Education*
