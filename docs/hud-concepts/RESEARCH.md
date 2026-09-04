# HUD direction — research notes

## Biomechanical ≠ wetware / gore
- **Means**: organic *geometry* fused with machine logic — articulated joints, tendon-like cable looms, insect-shell panels, oil-droplet / braille glyphs, hydraulic silhouettes.
- **Does not mean**: exposed flesh, blood, wet membranes, cysts, pulsing meat frames.
- Materials: bone-ceramic, anodized aluminum, smoked polycarbonate, brushed titanium, matte polymer. Sterile + exotic, not visceral.
- References: clean industrial biotech product design; Cryo-era diegetic consoles; Dune/Harkonnen insect-anatomy UI language (not horror makeup).

## Blob-tracking visual grammar (real CV / VFX tools)
Drawn from OpenCV connected-components + TouchDesigner / AE-style track overlays:

| Element | What it communicates |
|--------|----------------------|
| Corner brackets / L-frames | Selection lock (prefer over full boxes) |
| Silhouette contour / convex hull | Occupancy footprint of a mutant |
| Fitted ellipse | Orientation + extent |
| Centroid cross + stable ID (`M-03`) | Track identity |
| Velocity vector / trail polyline | Last moves / predicted path |
| Plexus / Delaunay / MST links | Relation graph (stack organs, threat links) |
| Marching-ants border | Active / scanning |
| Tiny data chip | Area, confidence, organ count |
| Soft confidence field | Optional secondary layer (low opacity) |

Color: phosphor amber or clinical cyan on dark board — high signal, low gore.

## Diegetic fiction
Player operates a **biostrategic analysis console**: AI tracks mutant “blobs” as connected components; gene offers are **specimen cartridges / slides** (hard goods), not bleeding tissue.

## Screen budget (hard constraint)
- **Board first**: voxel field should own ~80–90% of the viewport.
- Chrome is **edge-thin** (hairline lip / micro plaques), not a CRT housing that eats the frame.
- Gene tray + action keys: compact dock; offer tray can be **temporary** (only during gene phase).
- Mutant inspect / analysis: prefer **on-blob chips + track overlays**; no persistent sidebars.
- Skeuomorphism lives in materials and micro-widgets, not in large physical console mass.
