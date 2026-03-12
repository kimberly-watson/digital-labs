# Sonatype Digital Lab — Customer Guide

Welcome to your Sonatype Digital Lab. This guide covers everything you need to get started and make the most of your lab time.

---

## Getting Started

You will receive a welcome email from Sonatype with a single link to your **Lab Portal**. Click that link to open the portal in your browser. Everything you need is accessible from there — no VPN, no software installation, no license keys required.

> **Allow up to 10 minutes after receiving your welcome email for all services to finish starting up.**

---

## The Lab Portal

The portal is your home base. It shows:

- **Countdown timer** — how much time remains before your lab automatically shuts down
- **Quick-launch buttons** for Nexus Repository and IQ Server
- **🤖 Use Lab Tutor** — an AI learning assistant you can open at any time (bottom-right corner of the portal, or bottom-right corner of any Nexus or IQ Server page)

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

Sample artifacts are pre-loaded so you can explore the interface right away.

**To sign in:**
1. Click **Sign in** in the top-right corner
2. Username: `admin`
3. Password: `admin123`

### IQ Server (Lifecycle & Firewall)

Click **IQ Server** on the portal to open it in a new tab.

IQ Server provides software composition analysis, policy enforcement, and firewall capabilities. Your lab license covers all seven Sonatype products: Repository Firewall, Lifecycle, Auditor, Developer, Advanced Development Pack, Advanced Legal Pack, and Supply Chain Insights.

**To sign in:**
1. Username: `admin`
2. Password: `admin123`

---

## Lab Tutor

The **Lab Tutor** is an AI learning assistant powered by Claude. It opens as a small popup window positioned at the right edge of your screen so you can chat while keeping the product you're working in visible.

**To open it:** click the **🤖 Use Lab Tutor** button on the portal, or the **🤖 Lab Tutor** button in the bottom-right corner of any Nexus Repository or IQ Server page.

If the tutor is already open, clicking the button again simply brings the existing window to the front — it will not open a second one.

> **Tip:** Keep the tutor popup open as you navigate between the portal and product pages. It will stay open and retain your conversation.

### Learning Mode

The Lab Tutor is designed to help you *learn*, not just look things up. Instead of giving you answers directly, it will:

- Ask you guiding questions to help you discover the answer yourself
- Point you to the right area of the UI to explore
- Give hints when you're stuck
- Explain concepts once you've had a chance to explore

This approach is intentional — working through problems with guidance leads to better retention than reading answers.

### What to Ask

- "How do I create a new repository?"
- "What does the firewall do and how do I configure it?"
- "I'm trying to run a policy scan — where do I start?"
- "What's the difference between Lifecycle and Firewall?"
- "How do I see what components are in my repository?"
- "My lab expires in 2 days — what should I finish before then?"

The tutor knows your lab's URLs, credentials, and expiry time, so you do not need to look those up separately.

### Tips

- Type in the chat box and press **Enter** or click **Send**
- The tutor remembers the conversation as long as the popup window stays open
- If you close the popup and reopen it, the conversation history resets
- The tutor knows which product page you're currently on and can tailor its guidance accordingly
- The tutor stays focused on Nexus Repository, IQ Server, and Sonatype topics

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
Services can take up to 10 minutes to fully start after the lab is provisioned. Wait a few minutes and try again. You can also ask the Lab Tutor — it can tell you the current status of your services.

**I forgot my password.**
Default credentials are always `admin` / `admin123`. These are set automatically and do not change.

**The countdown timer shows "--".**
Refresh the page. If it continues, the timer service may still be starting up — wait 2–3 minutes and try again.

**The Lab Tutor isn't answering my questions directly.**
That's by design. The tutor uses Learning Mode, which guides you through problems rather than handing you the answer. Try following its questions and exploring the UI — the answer is usually one or two clicks away. If you're genuinely stuck, tell the tutor "I've tried X and Y, I still need help" and it will give you more direct guidance.

**The Lab Tutor says "the tutor is not available right now."**
This means the tutor service is temporarily unavailable. Wait 30 seconds and try again. If it persists, refresh the page.

**I need more time.**
Contact your Sonatype representative before your lab expires. Extensions must be arranged in advance and cannot be granted after the lab has terminated.

**I have a question the Lab Tutor can't answer.**
The tutor is scoped to Sonatype product topics. For anything outside that scope, reach out to your Sonatype contact directly.

---

*Sonatype Customer Education*
