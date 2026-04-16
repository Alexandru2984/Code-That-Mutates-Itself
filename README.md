# Evolving Minds: Code That Mutates Itself

An experimental distributed system built with **Elixir** and **Phoenix LiveView**, simulating digital consciousness with runtime self-mutating behavior.

## 🧠 Core Concept

The system simulates multiple "entities" (digital minds), each running as an independent Erlang/Elixir process (GenServer). These entities interact, learn, and evolve by rewriting their own behavior logic at runtime.

### Key Features
- **Dynamic Behavior Mutation**: Entities modify their own logic using Elixir's `Code.eval_string/1`, generating new functions based on traits like curiosity and aggression.
- **Emergent Social Graph**: Entities send native BEAM messages to each other (greet, attack, share knowledge) based on their evolving personality.
- **Energy & Decay**: Actions consume energy. When an entity dies of exhaustion, the Evolution Engine spawns a new generation with inherited/mutated traits.
- **Real-time Visualization**: A high-performance Phoenix LiveView dashboard showing the population's status, internal traits, recent memories, and the literal source code currently "running" inside their minds.

## 🚀 Recent Updates (v2.0 Wide-Spectrum)

- **Ultra-Wide UI**: Completely redesigned interface that scales from mobile to 4K displays.
- **Responsive Full-Screen Grid**: Optimized visualization of large populations using a dynamic grid system.
- **Production-Ready Deployment**: Configured with Nginx as a reverse proxy and secured via **Let's Encrypt (Certbot)** for automatic HTTPS.
- **Improved Performance**: Minimal BEAM footprint with optimized memory streams using ETS and efficient LiveView diffs.

## 🛠️ Architecture

- **`EvolvingMinds.Entity`**: The core actor representing a single mind.
- **`EvolvingMinds.MutationEngine`**: The logic factory that generates and compiles dynamic Elixir code.
- **`EvolvingMinds.Memory`**: An ETS-backed storage system for interaction history with automatic decay.
- **`EvolvingMinds.EvolutionEngine`**: Manages population size, reproduction, and periodic evaluation.
- **`EvolvingMindsWeb.WorldLive`**: The observer UI that monitors the distributed state of the BEAM processes in real-time.

## ⚙️ Development & Deployment

### Prerequisites
- Elixir 1.14+
- Erlang/OTP 25+
- Nginx (for production reverse proxy)

### Local Setup
1. Clone the repository
2. Install dependencies:
   ```bash
   mix deps.get
   ```
3. Start the Phoenix server:
   ```bash
   mix phx.server
   ```
4. Access at `http://localhost:4000`

### Production Configuration
The app is designed to run behind Nginx with the following features:
- **WebSocket Support**: Proxying for Phoenix Channels and LiveView.
- **SSL/TLS**: Automated certificate management via Certbot.
- **Zero-Downtime Hot Code Reloading**: Leveraging BEAM's native capabilities.

## 🧪 Experiments
This is a playground for exploring emergent behavior in a concurrent, functional environment. The "intelligence" of the entities is procedural and randomized, designed to test the limits of self-modifying code within the safety of the BEAM virtual machine.

---
Built with 💚, Elixir, and Phoenix.
