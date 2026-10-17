# Omnikeys

Predictive text for every Mac text field, on-device. A Cotypist-style clone with the full Pro feature set. Runs on Apple's built-in foundation model (macOS 26, Apple Silicon, Apple Intelligence on) or on the open-weight models Cotypist ships, Gemma 4 E2B/E4B and Qwen, pulled from Hugging Face on first use and run by MLX.

- Ghost text a few words ahead of the cursor in any text field (Accessibility API), drawn in the field's own font and colour at 40% opacity.
- Tab completes the next word, ` accepts the full completion, Esc dismisses, Ctrl+` force-activates, Ctrl+Opt+Cmd+` toggles the current app. All shortcuts configurable.
- Typo fix with Tab, emoji by `:shortcode`, mid-line completion, clipboard awareness (off by default: it measurably derails the small models).
- Model picker in Settings: Apple, Gemma 4 E2B (Cotypist's default), Gemma 4 E4B, Qwen2.5 1.5B, Qwen3 1.7B. Weights cache in `~/.cache/huggingface/hub` (1 to 3 GB each).
- Global and per-app custom instructions, personalization from your own typing history (6-stop slider), delete all data.
- Form fill, ported from Form Filler: an encrypted vault of your details (names, contact, address, IDs, work, emergency, medical, insurance, custom fields, several people). An empty field whose label matches shows the answer as ghost text, Tab fills it. ⌃⌥F fills every empty field in the front window. Sensitive fields are masked and skipped by whole-form fill unless enabled. Imports the iPhone and web Form Filler encrypted backups unchanged, and fills itself from your macOS Contacts card. It also learns: what you type into a labelled field or textarea is remembered in the vault, so the next form with that label fills itself (search, password, card and chat fields excluded).
- Labs: British English, right-to-left.

## Build

    ./build.sh --run        # xcodebuild (swift build cannot compile MLX's Metal shaders), signs, installs to ~/Applications, launches
    ./scripts/e2e.sh        # self-test + 4 live loops in TextEdit: completion/Tab/backtick, typo fix, emoji, Esc
    OMNIKEYS_MODEL=mlx-community/gemma-4-e2b-it-4bit ~/Applications/Omnikeys.app/Contents/MacOS/Omnikeys --selftest   # same check on an MLX model

The e2e script launches the app with `--e2e`, which enables an `omnikeys://type` / `omnikeys://key` URL driver so the AX-trusted app types for the (untrusted) shell. The driver is off in normal launches.

Context comes from the Accessibility API, never from screenshots: the text around the caret, the rest of the focused window (an email thread above the reply box, a chat history) and up to three other windows visible beside it, limited to elements actually on screen. Toggle in Settings. Grant Accessibility to Omnikeys once (System Settings → Privacy & Security → Accessibility). Log: `~/Library/Logs/Omnikeys.log`.

CWT_STENGW9_2609

## App notes
- **Google Docs** draws the document on a canvas. Turn on Tools › Accessibility › screen reader support (⌘⌥Z) in Docs; the hidden edit target then carries the current paragraph, and the caret is read from Docs' own `kix-cursor` element. Without it the context is one character and the log says `skip: short context`.
- **Terminals** complete from the agent prompt line (`>`, `›`, `❯`); the AX caret sits below the status bar. Knife Terminal pads empty cells with NUL, mapped to spaces.

## How a suggestion is made (MLX models)
The instructions, writer notes, samples and screen text go in the user turn; the model's own turn is prefilled with the text being typed, so the next tokens are plain continuation of it rather than an answer about it. The end-of-turn tokens are masked for the first three tokens so a finished sentence still gets a next one. A trailing fragment that is not a word (`sto`) is left off the prefill and must come back in the output (token healing). `Engine.clean` then strips overlap, drops copies of text already on screen, and trims the word cap back to a clause break. Bench: `OMNIKEYS_BENCH=1 OMNIKEYS_MODEL=mlx-community/gemma-4-e2b-it-4bit ~/Applications/Omnikeys.app/Contents/MacOS/Omnikeys --selftest`.
