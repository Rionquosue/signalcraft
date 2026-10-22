# Media protection — specification sheet

Specification 1.1 • 22 October 2026 • Proposed implementation contract

## Purpose

Let authors publish images they have already protected against AI training with a desktop tool such as Nightshade or Glaze, without the application weakening that protection. v1 does not run any protection tool itself; it only guarantees that a file the author marks as protected is published byte-for-byte as uploaded.

Depends on 02_Rails_Container_Design.md (media pipeline) and 08_Database_Schema_Specification.md (columns).

## Why the application does not protect images itself

These were checked against public sources on 22 October 2026.

| Finding | Consequence |
|---|---|
| Nightshade and Glaze are free but closed-source Windows and macOS desktop apps, with no Linux build, command-line interface, API or server-use terms. | They cannot run in the application's containers. Authors run them locally. |
| The open-source alternative Mist (GPL-3.0) needs a 8–32 GB GPU, documents output sizes up to 768 px, and has been shown removable by later research. | Not adopted for v1. Revisit if a tool emerges that runs at full resolution and survives platform recompression. |
| Neither class of tool protects video. | Video is out of scope. |

## The checkbox

When an author uploads an image, they may tick **"I protected this image against AI training"**. Optionally they name the tool used (free text with suggestions: Nightshade, Glaze, Mist, Other).

The declaration is the author's statement; the application does not detect or verify protection. It is recorded on the asset with who declared it and when, and appears in the audit log.

The checkbox is available only for still images. For videos it is not shown.

## Publishing rules for declared-protected images

1. **No transformation.** The host never resizes, crops, re-encodes or strips metadata from a declared-protected image. No provider variant is generated from it. `prepare_media` receives the original asset.
2. **Validation still runs.** The FFmpeg service still probes the file to confirm it is a supported, safe image. Validation reads the file; it does not change it.
3. **Provider limits are checked, not fixed.** If the file breaks a selected provider's constraints (for example Instagram requires JPEG; Bluesky caps image size), that target is blocked with reason `protected_media_incompatible` and the message "This protected image doesn't meet {provider}'s requirements ({detail}). Upload a protected version that does, or untick protection to let us adjust a copy." Other targets are unaffected.
4. **Unticking creates a choice, not a silent fix.** If the author unticks the box, normal variant generation applies from then on. Unticking after scheduling creates a new target revision.
5. **The provider may still recompress.** Platforms re-encode uploads after receipt; the application cannot prevent that and says so.

Plugins upload a declared-protected asset's bytes unchanged. If the provider rejects it, the plugin returns a ValidationError; it never adapts the file.

## UI

- Checkbox label: "I protected this image against AI training". Help text: "We'll publish this exact file without resizing or converting it. Protection tools aren't a guarantee, and platforms may still recompress images."
- Asset badge: "Protected (declared)", plus the tool name if given.
- Blocked targets show the `protected_media_incompatible` message and the two choices above.

## Acceptance criteria

- A declared-protected image is published with the same SHA-256 as the upload, recorded in the publish attempt.
- No variant row is ever created from a declared-protected asset.
- A provider-incompatible protected image blocks only that provider's target, with the defined message.
- The checkbox is not offered for video.
- Declaring and undeclaring protection are audited.

## References

- [Glaze and Nightshade project](https://glaze.cs.uchicago.edu/) and [Nightshade](https://nightshade.cs.uchicago.edu/).
- [Mist](https://github.com/psyker-team/mist) and [Mist device requirements](https://mist-documentation.readthedocs.io/en/latest/content/device.html).
- [MIT Technology Review on LightShed](https://www.technologyreview.com/2025/07/10/1119937/tool-strips-away-anti-ai-protections-from-digital-art/).

## Changes in 1.1

- Reduced to a manual declaration checkbox. Removed Automatic mode, the protection worker, adapter contract and protection tables.
