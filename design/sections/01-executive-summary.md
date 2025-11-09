## Executive Summary

This document outlines the design for a "reproducible analysis" feature that allows readers to launch select chapters of the UN Handbook into a one-click, pre-configured Kubernetes environment.

**Scope**: This system is designed for chapters with local data dependencies (pre-computed models, training samples, cached results). Currently, 2 chapters are ready (ct_chile, ct_digital_earth_africa), with 2-5 additional chapters planned. Most handbook chapters (84%) are cloud-only or theoretical and access live satellite imagery via STAC catalogs without requiring reproducible containers.

- **For Readers**: A "Reproduce this analysis" button launches a JupyterLab session into Onyxia on the UN Global Platform with all code, data, and dependencies ready.
- **For Chapter Authors**: A zero-friction, git-native workflow. Authors push data to a tracked directory, and a CI pipeline automatically builds, versions, and deploys the data artifact. Minimal YAML configuration required (just `enabled: true` with smart defaults).
- **For Infrastructure**: The system leverages Onyxia to dynamically provision ephemeral sessions. This design is stateless, using a CSI image driver to mount OCI data artifacts directly as volumes, and pre-built images for the environment.

**Key Architectural Decisions**:

-  Onyxia-native Orchestration: Use Onyxia for UI, authentication, and service deployment.
-  Stateless Data Layer: Use a CSI Image Driver to mount OCI data artifacts directly as read-only volumes.
-  Implicit Performance: Startup speed (5-15s) is achieved via standard node-level container image caching, which is more robust than managed PVCs.
-  Automated Author Workflow: A fully CI-driven pipeline using Dagger SDK builds content-hashed (immutable) data artifacts and auto-commits the new hash back to the chapter, ensuring true reproducibility.
-  Portable & Decoupled Auth: Use standard Kubernetes Workload Identity (IRSA) as the primary mechanism for AWS credentials. This makes the core Helm chart portable and not dependent on Onyxia-specific injectors.
-  Curated & Isolated Environments: Start with a "base" Docker image, but the CI pipeline is designed to build chapter-specific compute images (from renv.lock) to prevent future dependency conflicts.

These architectural decisions are implemented through **five custom software components** that operate in two distinct phases: a **Build-Time Flow** (automated CI/CD for authors) and a **Run-Time Flow** (one-click session launching for readers). See the [Architecture Overview](#architecture-overview) section for a detailed breakdown of how these components interact with existing platforms (Kubernetes, Onyxia, AWS) to enable reproducible analysis.
