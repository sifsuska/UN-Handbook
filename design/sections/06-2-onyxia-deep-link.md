##### Onyxia Deep-Link Mechanism

###### Overview

Onyxia provides a "deep-link" URL format that allows pre-populating Helm chart values via URL query parameters. This eliminates manual configuration and enables one-click session launches.

###### URL Structure

**Format**:
```
https://{onyxia-instance}/launcher/{catalog}/{chart}?{parameters}
```

**Example**:
```
https://datalab.officialstatistics.org/launcher/handbook/chapter-session
  ?autoLaunch=true
  &name=«chapter-ct_chile»
  &tier=«medium»
  &imageFlavor=«base»
  &chapter.name=«ct_chile»
  &chapter.version=«sha256-abcdef123»
  &chapter.storageSize=«20Gi»
```

###### Parameter Encoding

Onyxia uses a special encoding scheme for Helm values in URLs:

- **Numbers**: Pass as-is (e.g., `tier=5`)
- **Booleans**: Pass as-is (e.g., `autoLaunch=true`)
- **Strings**: URL-encode and wrap in `«»` delimiters (e.g., `name=«chapter-ct_chile»`)

The Quarto extension's `encode_helm_value()` function (Section 6.1) handles this encoding automatically.

###### Parameter Mapping to Helm Values

URL parameters map directly to Helm chart `values.yaml` structure using dot notation:

| URL Parameter | Helm Value Path | Example |
|---------------|----------------|---------|
| `tier=«medium»` | `.Values.tier` | `"medium"` |
| `imageFlavor=«base»` | `.Values.imageFlavor` | `"base"` |
| `chapter.name=«ct_chile»` | `.Values.chapter.name` | `"ct_chile"` |
| `chapter.version=«v1-2-3»` | `.Values.chapter.version` | `"v1-2-3"` |
| `chapter.storageSize=«20Gi»` | `.Values.chapter.storageSize` | `"20Gi"` |

###### Auto-Launch Behavior

When `autoLaunch=true` is included in the URL:

1. User clicks "Reproduce this analysis" button
2. Browser navigates to Onyxia launcher
3. Onyxia pre-fills all form fields with URL parameters
4. **Automatically submits** the deployment (no user interaction needed)
5. Kubernetes session starts immediately

Without `autoLaunch`, users would see a pre-filled form but need to click "Launch" manually.

###### Catalog and Chart Selection

The URL path identifies which Helm chart to deploy:

```
/launcher/{catalog-id}/{chart-name}
```

- **Catalog ID**: `handbook` (the Onyxia catalog containing our chart)
- **Chart Name**: `chapter-session` (our reproducible session chart)

Onyxia catalogs are Helm chart repositories that Onyxia instances are configured to reference. The `handbook` catalog would be hosted at a URL like:

```
https://fao-eostat.github.io/UN-Handbook/handbook-catalog/
```

And configured in Onyxia's platform settings:

```yaml
# Onyxia platform configuration
catalogs:
  - id: handbook
    name: "UN Handbook Sessions"
    location: https://fao-eostat.github.io/UN-Handbook/handbook-catalog/
    type: helm
```

###### Integration with Helm Chart

The Helm chart's `values.schema.json` can specify which fields should be overwritable via deep-links:

```json
{
  "tier": {
    "type": "string",
    "default": "medium",
    "enum": ["light", "medium", "heavy", "gpu"],
    "x-onyxia": {
      "overwriteDefaultWith": null
    }
  },
  "chapter": {
    "type": "object",
    "properties": {
      "name": {
        "type": "string",
        "x-onyxia": {
          "overwriteDefaultWith": null
        }
      }
    }
  }
}
```

Setting `"overwriteDefaultWith": null` indicates the value should come from the deep-link URL rather than platform defaults or `region.customValues`.

###### Security Considerations

Deep-link parameters are validated against the chart's `values.schema.json`:

- **Type checking**: `tier` must be a string, `autoLaunch` must be boolean
- **Enum validation**: `tier` must be one of `["light", "medium", "heavy", "gpu"]`
- **Injection prevention**: Helm template escaping prevents malicious values from executing arbitrary code

Invalid parameters are rejected with user-friendly error messages.
