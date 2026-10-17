# Omnikeys

Predictive text for every Mac text field, on-device. A Cotypist-style clone with the full Pro feature set. Runs on Apple's built-in foundation model (macOS 26, Apple Silicon, Apple Intelligence on) or on the open-weight models Cotypist ships, Gemma 4 E2B/E4B and Qwen, pulled from Hugging Face on first use and run by MLX.

- Ghost text a few words ahead of the cursor in any text field (Accessibility API), drawn in the field's own font and colour at 40% opacity.
- Tab completes the next word, ` accepts the full completion, Esc dismisses, Ctrl+` force-activates, Ctrl+Opt+Cmd+` toggles the current app. All shortcuts configurable.
- Typo fix with Tab, emoji by `:shortcode`, mid-line completion, clipboard awareness (off by default: it measurably derails the small models).
- Model picker in Settings: Apple, Gemma 4 E2B (Cotypist's default), Gemma 4 E4B, Qwen2.5 1.5B, Qwen3 1.7B. Weights cache in `~/.cache/huggingface/hub` (1 to 3 GB each).
- Global and per-app custom instructions, personalization from your own typing history (6-stop slider), delete all data.
- Labs: numbered word alternatives, synonyms for a selected word, British English, right-to-left.

## Build

    ./build.sh --run        # xcodebuild (swift build cannot compile MLX's Metal shaders), signs, installs to ~/Applications, launches
    ./scripts/e2e.sh        # self-test + 4 live loops in TextEdit: completion/Tab/backtick, typo fix, emoji, Esc
    OMNIKEYS_MODEL=mlx-community/gemma-4-e2b-it-4bit ~/Applications/Omnikeys.app/Contents/MacOS/Omnikeys --selftest   # same check on an MLX model

The e2e script launches the app with `--e2e`, which enables an `omnikeys://type` / `omnikeys://key` URL driver so the AX-trusted app types for the (untrusted) shell. The driver is off in normal launches.

Context comes from the Accessibility API (the text around the caret in the focused field), never from screenshots. Grant Accessibility to Omnikeys once (System Settings → Privacy & Security → Accessibility). Log: `~/Library/Logs/Omnikeys.log`.

CWT_STENGW9_2609
