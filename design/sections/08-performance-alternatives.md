#### Performance & Alternatives

###### Performance Comparison: CSI Image Driver vs. PVC Cloning

| Metric | Old Approach (PVC Cloning) | New Approach (CSI Image Driver) | Improvement |
|--------|----------------------------|----------------------------------|-------------|
| First user startup | 60s (create golden PVC) | 15-30s (node pulls image) | **2-4× faster** |
| Second user startup | 5-15s (clone PVC) | **5-15s** (node cache hit) | **Same performance** |
| State management | Golden PVCs + cleanup jobs | **Stateless** (K8s image cache) | **Zero management** |
| Storage overhead | 1 golden PVC per chapter | **None** (standard image cache) | **Infrastructure simplified** |
| Reproducibility | Version tags | **Content hashes** (SHA256) | **Immutable artifacts** |
| Author workflow | Manual script execution | **Fully automated CI** | **Zero friction** |

**Key Insights:**

- **Stateless Architecture**: The CSI Image Driver approach eliminates the need for PVC management, cleanup jobs, and golden PVC coordination. Kubernetes treats data artifacts the same way it treats compute images - pulling, caching, and garbage collecting them automatically.

- **Performance Parity**: While first-run performance is significantly better (2-4× faster), subsequent launches achieve the same 5-15 second startup time as PVC cloning, thanks to node-level image caching.

- **Operational Simplicity**: Infrastructure teams no longer need to manage stateful data layers. The Kubernetes image cache handles all lifecycle management automatically.

---

###### Rejected Alternatives & Design Rationale

This section documents alternatives considered during the design process and explains why they were rejected in favor of the current architecture.

####### Alternative 1: KubeVirt DataVolumes

**What it is**: KubeVirt's Containerized Data Importer (CDI) provides DataVolumes that can import OCI images into PVCs at pod creation time.

**Why we considered it**:
- Native Kubernetes resource (CRD)
- Automatic import from container registries
- Handles conversion from OCI image to PVC

**Why we rejected it**:

1. **Statefulness**: DataVolumes create PVCs that persist after pod deletion, requiring manual cleanup or additional controllers
2. **Storage overhead**: Each session creates a new PVC, consuming cluster storage even after the session ends
3. **Complexity**: Requires installing KubeVirt CDI operator and managing CRD lifecycle
4. **Performance**: Import process adds 30-60s to first startup (must extract OCI layers to PVC)
5. **Not truly immutable**: PVCs are writable by default, allowing session data corruption

**Verdict**: CSI Image Driver provides the same OCI-to-volume functionality but with a stateless, read-only, cacheable approach.

---

####### Alternative 2: Manually Managed PVCs per Chapter

**What it is**: Infrastructure team manually creates one PVC per chapter, mounting it read-only into user sessions.

**Why we considered it**:
- Simple Kubernetes primitive (no additional tools required)
- Read-only mounts prevent data corruption
- Centralized data management

**Why we rejected it**:

1. **Manual versioning**: Every chapter data update requires manual PVC recreation and session restarts
2. **No content addressing**: Can't guarantee which version of data is mounted without complex naming schemes
3. **Storage waste**: Old chapter data versions require keeping old PVCs or losing reproducibility
4. **Operational burden**: Infrastructure team becomes bottleneck for data updates
5. **No garbage collection**: Unused PVCs accumulate, consuming cluster storage indefinitely

**Verdict**: OCI artifacts with CSI Image Driver provide automatic versioning, content addressing, and garbage collection via standard Kubernetes mechanisms.

---

####### Alternative 3: Kubeflow Notebooks

**What it is**: Kubeflow's notebook server custom resources with built-in JupyterHub integration.

**Why we considered it**:
- Mature ecosystem for data science notebooks
- Built-in authentication and multi-user support
- Integrates with Kubeflow Pipelines

**Why we rejected it**:

1. **Heavy infrastructure dependency**: Requires full Kubeflow installation (Istio, Knative, multiple operators)
2. **Opinionated architecture**: Assumes Kubeflow Pipelines workflow, which doesn't match our "reproducible handbook chapter" use case
3. **Limited customization**: Notebook CRD is tightly coupled to Kubeflow's authentication and resource management
4. **No content-addressed data**: No built-in mechanism for mounting versioned, immutable datasets
5. **Complexity overhead**: Kubeflow's power comes from ML workflow orchestration, which we don't need

**Verdict**: Onyxia + Helm provides equivalent notebook deployment with far less infrastructure complexity and better alignment with our content-addressed data model.

---

####### Alternative 4: Git LFS for Data Versioning

**What it is**: Store chapter data in Git using Git Large File Storage (LFS), clone repositories at session startup.

**Why we considered it**:
- Familiar Git workflow for version control
- Native GitHub/GitLab integration
- Simple mental model (data lives with code)

**Why we rejected it**:

1. **Slow clones**: Git LFS clones are slow for large datasets (10+ GB), adding 2-5 minutes to startup
2. **Authentication complexity**: Requires managing Git credentials in user sessions
3. **Not content-addressed**: Git LFS uses SHA256 pointers, but doesn't provide fast, read-only mounting
4. **No caching**: Every session clones data from scratch (no node-level caching like container images)
5. **Storage costs**: Git LFS hosting is expensive compared to container registries (GitHub charges per GB/month)

**Verdict**: OCI artifacts provide faster access (5-15s vs. 2-5 minutes), automatic caching, and cheaper storage via standard container registries.

---

####### Alternative 5: Platform-Specific CI (GitHub Actions Only)

**What it is**: Implement all build-time logic (image builds, data hashing, auto-commits) directly in GitHub Actions YAML.

**Why we considered it**:
- No additional dependencies (GitHub Actions is already required)
- Simpler for teams already familiar with GitHub
- Native GitHub ecosystem integration

**Why we rejected it**:

1. **Lock-in**: Organizations using GitLab, Bitbucket, or Azure DevOps would need to rewrite all logic
2. **No local testing**: Developers can't run CI pipeline locally (must push to GitHub to test)
3. **YAML complexity**: Complex logic (content hashing, Git operations, conditional builds) becomes unreadable in YAML
4. **Poor debugging**: GitHub Actions logs are difficult to debug compared to local Dagger execution
5. **Limited portability**: Can't reuse pipeline for on-premise or air-gapped environments

**Verdict**: Dagger SDK abstracts the pipeline into portable Python code, reducing platform-specific YAML to simple one-line wrappers.

---

###### Design Rationale Summary

The final architecture (CSI Image Driver + Dagger + Onyxia + IRSA) was chosen based on these core principles:

**1. Statelessness Over State Management**
- CSI Image Driver eliminates PVC lifecycle management
- Kubernetes image cache handles all data layer operations
- No cleanup jobs, no orphaned resources

**2. Portability Over Lock-In**
- Dagger SDK runs identically on any CI platform
- Helm chart works on any Kubernetes cluster with OIDC
- IRSA/Workload Identity is a standard cloud-native pattern

**3. Content Addressing Over Version Tags**
- SHA256 content hashes guarantee bit-for-bit reproducibility
- Impossible to accidentally reference wrong data version
- Automatic deduplication and caching

**4. Automation Over Manual Processes**
- Authors commit data, CI automatically packages and versions
- No manual PVC creation, no manual hash calculation
- Zero infrastructure work required for data updates

**5. Standards Over Custom Solutions**
- OCI artifacts are industry-standard container images
- Helm is the de facto Kubernetes package manager
- IRSA is the AWS-endorsed credential mechanism

**Result**: A reproducible analysis system that is simple to operate, easy to adopt, and guaranteed to work consistently across different organizations, cloud providers, and CI platforms.
