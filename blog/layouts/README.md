# Theme overrides

These files are copies of PaperMod templates with one change each: they call
Hugo's current language API instead of the API deprecated in Hugo 0.158.

| File | Change |
| --- | --- |
| `baseof.html` | `.Language.LanguageDirection` → `.Language.Direction` |
| `rss.xml` | `site.Language.LanguageCode` → `site.Language.Locale` |
| `_partials/templates/opengraph.html` | `site.Language.LanguageCode` → `site.Language.Locale` |

Upstream still uses the deprecated calls as of `d376885` (2026-08-02), so
updating the theme does not remove the warnings. No site configuration can
silence them either — the theme calls the deprecated API directly.

Rendered output is unchanged: `lang="en" dir="auto"`, RSS `<language>en-us</language>`.

**These are copies and will not pick up upstream fixes.** When bumping the
hugo-papermod input, diff each file against the new theme revision and either
re-apply the substitution or delete the override if upstream has fixed it:

    T=$(nix eval --raw --impure --expr \
      'let f = builtins.getFlake (toString ../.); in f.inputs.hugo-papermod.outPath')
    diff "$T/layouts/baseof.html" layouts/baseof.html
