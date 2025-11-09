### Component #3: OCI Data Artifacts with CSI Image Driver

**Content-Addressed Data Packaging**

#### Why CSI Image Driver?

- **Stateless**: No PVC management, cleanup jobs, or golden PVC coordination
- **Implicit Performance**: Node-level caching provides 5-15s startup automatically
- **Simpler**: Kubernetes treats data images like compute images
- **Immutable**: Each content hash is a unique, reproducible artifact

#### How It Works

The CSI (Container Storage Interface) Image Driver allows Kubernetes to mount OCI (Docker/container) images directly as volumes. Instead of managing PVCs and DataVolumes, we simply reference the data image in the pod spec:

```yaml
volumes:
- name: chapter-data
  csi:
    driver: csi-image.k8s.io
    volumeAttributes:
      image: "ghcr.io/fao-eostat/handbook-data:ct_chile-sha256-abcdef123"
    readOnly: true
```

When the pod starts:

1. Kubernetes pulls the data image to the node (just like a compute image)
2. The CSI driver mounts the image contents as a read-only filesystem
3. The container sees the data at `/home/jovyan/handbook-chapter/`
4. Node-level caching means subsequent launches are instant (<15s)

#### Benefits

- **No state management**: No PVCs to create, clone, or clean up
- **Automatic caching**: Kubernetes image cache handles performance
- **Content-addressed**: Each SHA256 hash guarantees exact reproducibility
- **Garbage collection**: Standard Kubernetes image GC removes unused data

#### Data Artifact Structure

Each chapter's data directory is packaged as a minimal OCI artifact:

```dockerfile
FROM scratch
COPY data/ct_chile /data/ct_chile
```

The Dagger pipeline (see [Portable CI/CD Pipeline](#component-1-portable-cicd-pipeline-dagger-sdk)) automatically:

1. Detects changed data directories via `git diff`
2. Builds minimal `scratch` containers with chapter data
3. Calculates content-addressed digest using `artifact.digest()`
4. Pushes to registry with tag: `ct_chile-sha256-abcdef123`
5. Auto-commits the hash back to chapter frontmatter

#### Content-Addressed Naming

**Example tag format**: `ghcr.io/fao-eostat/handbook-data:ct_chile-sha256-abcdef123`

- **Repository**: `ghcr.io/fao-eostat/handbook-data`
- **Chapter**: `ct_chile`
- **Hash**: `sha256-abcdef123` (first 12 chars of SHA256 digest)

The hash is calculated from the exact content of the data directory. Identical data always produces identical hashes, guaranteeing bit-for-bit reproducibility.

#### Implementation in Helm Chart

**File**: `handbook-catalog/chapter-session/templates/deployment.yaml`

```yaml
volumes:
- name: chapter-data
  csi:
    driver: csi-image.k8s.io
    volumeAttributes:
      image: "{{ .Values.chapter.ociImage }}"
    readOnly: true

volumeMounts:
- name: chapter-data
  mountPath: /home/jovyan/handbook-chapter
  readOnly: true
```

The `chapter.ociImage` value is passed via the Onyxia deep-link (see [Onyxia Deep-Link Mechanism](#onyxia-deep-link-mechanism)) and sourced from the chapter's YAML frontmatter:

```yaml
reproducible:
  data-snapshot: "sha256-abcdef123"
```

The Quarto extension (see ["Reproduce" Button](#component-4-reproduce-button-quarto-extension)) automatically constructs the full OCI reference from this hash.
