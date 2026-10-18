# Bullet Life — app icon

Concept: a hollow blue ball (event bullet) and a coral ball (task bullet) rolling up a teal ramp (note dash), on warm off-white. Same-size balls; the coral ball is in front, covering about half of the blue one, with a soft shadow. Colors match the bullet colors in CLAUDE.md section 3.3 (coral #E0533D, blue #3B82C4, teal #2A9D8F). Original artwork, no third-party marks.

| File | Use |
|---|---|
| `icon.svg` | Master (rounded corners). Edit this first. |
| `icon-fullbleed.svg` | Master without rounded corners (for stores that apply their own mask). |
| `icon-1024.png` | Marketing / store listing (rounded, transparent corners). |
| `icon-512.png`, `icon-192.png` | Web manifest, `purpose: "any"`. |
| `icon-maskable-512.png` | Web manifest, `purpose: "maskable"` (content inside the 80% safe zone, full-bleed). |
| `apple-touch-icon.png` | 180x180 full-bleed, no transparency. `<link rel="apple-touch-icon" href="/apple-touch-icon.png">` (iOS applies its own rounding). |
| `favicon-32.png`, `favicon-16.png` | Browser tab. |

Manifest snippet:

```json
"icons": [
  { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
  { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
  { "src": "/icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
]
```

The SVG uses `feDropShadow` filters; the PNGs were rendered from it with Chromium. Before commercial release, review the icon together with the trademark clearance (CLAUDE.md section 14).
