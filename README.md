# Omnikeys

Predictive text for every Mac text field, on-device. A Cotypist-style clone with the full Pro feature set, on Apple's built-in foundation model (macOS 26, Apple Silicon, Apple Intelligence on).

- Ghost text a few words ahead of the cursor in any text field (Accessibility API), drawn in the field's own font and colour at 40% opacity.
- Tab completes the next word, ` accepts the full completion, Esc dismisses, Ctrl+` force-activates, Ctrl+Opt+Cmd+` toggles the current app. All shortcuts configurable.
- Typo fix with Tab, emoji by `:shortcode`, mid-line completion, clipboard awareness.
- Global and per-app custom instructions, personalization from your own typing history (6-stop slider), delete all data.
- Labs: numbered word alternatives, synonyms for a selected word, British English, right-to-left.

## Build

    ./build.sh --run        # builds, signs, installs to ~/Applications, launches
    ./scripts/e2e.sh        # self-test + 4 live loops in TextEdit: completion/Tab/backtick, typo fix, emoji, Esc

The e2e script launches the app with `--e2e`, which enables an `omnikeys://type` / `omnikeys://key` URL driver so the AX-trusted app types for the (untrusted) shell. The driver is off in normal launches.

Grant Accessibility to Omnikeys once (System Settings → Privacy & Security → Accessibility). Log: `~/Library/Logs/Omnikeys.log`.

CWT_STENGW9_2609
