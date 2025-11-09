## Reproducible Analysis System for UN Handbook - Design Document

### Executive Summary

{{< include design/sections/01-executive-summary.md >}}

---

### Current State & Design Goals

{{< include design/sections/02-current-state.md >}}

---

### Architecture Overview

{{< include design/sections/04-architecture-overview.md >}}

---

### Component Deep-Dive: Build-Time (CI/CD)

{{< include design/sections/05-00-component-build-time.md >}}

{{< include design/sections/05-1-dagger-pipeline.md >}}

{{< include design/sections/05-2-compute-images.md >}}

{{< include design/sections/05-3-oci-artifacts.md >}}

{{< include design/sections/05-4-repository-structure.md >}}

---

### Component Deep-Dive: Run-Time (User Session)

{{< include design/sections/06-00-component-run-time.md >}}

{{< include design/sections/06-1-reproduce-button.md >}}

{{< include design/sections/06-2-onyxia-deep-link.md >}}

{{< include design/sections/06-3-0-cloud-data-access.md >}}

{{< include design/sections/06-3-1-irsa.md >}}

{{< include design/sections/06-3-2-xonyxia-fallback.md >}}

{{< include design/sections/06-3-3-usage-examples.md >}}

{{< include design/sections/06-4-helm-chart.md >}}

---

### Implementation Roadmap

{{< include design/sections/07-implementation-roadmap.md >}}

---

### Performance & Alternatives

{{< include design/sections/08-performance-alternatives.md >}}
