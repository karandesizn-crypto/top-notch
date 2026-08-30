# Provider Marks

Each provider is drawn as a vector in `DesignSystem/ProviderMark.swift` — Claude's radiating
asterisk, Codex's scalloped blob with a `>_` prompt, Cursor's isometric cube with a wedge.

Vectors rather than bundled bitmaps: the same mark renders at 13pt in a card title and 18pt
inside a ring, and a path stays crisp at both without shipping several raster sizes.

They are drawn **monochrome white** on a dark disc, matching the product's visual reference,
rather than in brand colour.

## These are approximations

They are drawn from the marks' geometry, not from official artwork. They read correctly at
ring size, but they are not the real trademarks and should not be presented as such.

## Supplying exact artwork

Drop files here and they override the drawn marks with no code change:

```
~/Library/Application Support/Top Notch/Logos/<provider-id>.png
```

`png`, `pdf`, and `svg` are all accepted, in that order of preference. Filenames use the
provider identifier, so:

```
claude.png    codex.png    cursor.png    antigravity.png
```

The same mechanism covers user-added tools, which otherwise fall back to a neutral SF
Symbol. Results are cached per launch, so a newly dropped file appears after a restart.

## Trademarks

These marks belong to Anthropic, OpenAI, and Anysphere. `docs/TECH_STACK.md` says custom
provider marks are allowed "only where licensing/branding rules allow", and that review has
not happened.

Using them locally is one thing; **shipping them publicly is a trademark question that needs
answering before release.** Most vendors permit accurate, unmodified marks for nominative
identification and prohibit implying endorsement. The practical checklist:

- Use each vendor's official artwork rather than an approximation.
- Do not modify proportions or colour beyond what a monochrome treatment requires.
- Do not imply the vendors endorse or are affiliated with Top Notch.
- Read each brand guideline — Anthropic, OpenAI, and Anysphere each publish one.

Falling back to the SF Symbols this replaced is a one-line change if the answer is no.
