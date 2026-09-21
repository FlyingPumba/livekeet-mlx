# Livekeet

Live transcription for Apple Silicon, with a native Mac app and a command-line interface. Both capture microphone and system audio, write timestamped Markdown, and share the same transcription pipeline.

Speech recognition runs locally using MLX. Optional Claude cleanup sends transcript text to Claude; it is off by default. Speaker analysis runs locally with native Sortformer or optional Python WeSpeaker/pyannote engines.

## Build and run

Requires macOS 14+, Apple Silicon, Xcode's command-line/Metal tools, and Swift **6.2 or newer**. `scripts/swift.sh` uses a locally installed Swift 6.2.3 toolchain when available, otherwise Xcode's Swift. Set `LIVEKEET_SWIFT=/path/to/swift` to override it.

```sh
make build
.build/debug/livekeet --help
.build/debug/livekeet record --help

make build-app                      # local, ad-hoc signed app
open .build/debug/Livekeet.app

./deploy-locally.sh                  # build, install in /Applications, open

make test
python3 -m unittest discover -s Tests/Python -v
```

Local builds use ad-hoc signing without hardened runtime, matching the Set app's
local setup. Release builds use `RELEASE_SIGNING_IDENTITY` and hardened runtime.
`deploy-locally.sh` asks you to quit a running Livekeet before replacing it so it
cannot interrupt a recording. Set `LIVEKEET_APP_DESTINATION` to install elsewhere.

Give the app or terminal Microphone and Screen Recording permissions when prompted. Microphone-only recording does not require Screen Recording.

Install the CLI and its model/helper resources into `~/.local`:

```sh
make install
# Add ~/.local/bin to PATH if necessary.
livekeet --version
```

Use `make install PREFIX=/your/prefix` for a different location. The installation records its source checkout; keep that checkout to use `livekeet update`. Installing into an existing prefix replaces that prefix's `livekeet` command.

## CLI

```sh
livekeet                               # microphone + system audio
livekeet meeting.md --with "Alice,Bob" # names enable speaker identification
livekeet meetings/ --status            # output directory, including a new one
livekeet -m -d "USB"                    # microphone only, selected device
livekeet --system-only                 # system audio only
livekeet --multilingual                # Parakeet v3
livekeet --model mlx-community/parakeet-tdt-0.6b-v2
livekeet --diarize --engine sortformer
livekeet --engine wespeaker
livekeet --engine pyannote
livekeet --cleanup                     # optional Claude correction
livekeet --no-cleanup --no-diarize      # override config defaults
livekeet --dump-audio --no-relabel      # save WAV segments; skip final prompt

livekeet init                          # also --init
livekeet config                        # also --config; prints path, not secrets
livekeet devices                       # also --devices
livekeet models
livekeet relabel meeting.md
livekeet relabel meeting.md --rename 'Alice=Bob' --rename 'Bob=Alice'
livekeet update --check
livekeet update                        # fetch, fast-forward, rebuild, reinstall
```

All recording flags can also follow `livekeet record`. `-w` aliases `--with`, `-m` aliases `--mic-only`, and `-d` aliases `--device`. Device selection accepts the index printed by `devices`, an exact or unambiguous partial name, or a persistent UID. Indices can change after devices reconnect. Unlike the Python CLI, a selected microphone works alongside system capture too.

`--multilingual` overrides `--model`. Multiple `--with` names, `--diarize`, or an explicit `--engine` enable speaker identification; `--no-diarize` wins over all of them. `--no-cleanup` wins over `--cleanup` and the config. Microphone-only mode ignores remote speaker names. `--mic-only` and `--system-only` are mutually exclusive.

Ctrl+C finishes queued transcription, speaker analysis, and remaining cleanup before saving. In an interactive terminal, recordings with system audio offer speaker renaming afterward. `--no-relabel` disables the prompt; redirected input never prompts. Relabeling supports collision-safe swaps, touches only speaker labels, and writes atomically. EOF or Ctrl+C during the prompt leaves the original intact.

`update` follows the source checkout's tracked branch, refuses dirty or diverged checkouts, and never resets local changes. For a development binary, supply `--source /path/to/livekeet-mlx`. `--check` fetches Git history without installing. The Mac app updates separately through its Sparkle menu.

## Configuration and Mac app settings

`livekeet init` creates `~/.config/livekeet/config.toml` without overwriting an existing file. Python Livekeet's config keys are supported:

```toml
[output]
directory = "~/Documents/Transcripts"
filename = "{datetime}-{names}.md"

[speaker]
name = "Me"

[defaults]
model = "mlx-community/parakeet-tdt-0.6b-v2"
diarize = false
engine = "sortformer"
# device = "USB" # microphone name, UID, or index

[cleanup]
enabled = false
model = "claude-haiku-4-5-20251001"
timeout_s = 120.0
# system_prompt = "Preserve technical terms."
# prompt = "Custom batch correction prompt returning indexed JSON corrections."

[cleanup.corrections]
"chat gbt" = "ChatGPT"

[python]
executable = "python3"

[pyannote]
# token = "hf_..." # alternatively set HF_TOKEN
```

Filename placeholders: `{date}`, `{time}`, `{datetime}`, `{names}`. Names join with dashes and path separators are sanitized. Existing files receive numeric suffixes. Deterministic word corrections apply even when Claude cleanup is disabled.

The Mac app keeps its own persistent preferences. **Settings → General → Import settings from CLI config** copies CLI preferences into the app. Microphone selection and all three speaker engines are available in Settings. The app reads the TOML replacement dictionary and pyannote token at the start of each recording. Use an absolute Python path for launching from Finder.

## Optional Python engines and cleanup

The native Sortformer path needs no Python. Install only the helpers you want with [uv](https://docs.astral.sh/uv/):

```sh
scripts/setup-python.sh wespeaker  # or pyannote, cleanup, all
```

The script creates `~/.local/share/livekeet/python` and prints the executable path to use in `[python] executable` and the app's Advanced settings. Set `LIVEKEET_PYTHON_ENV` to choose another environment.

- **Sortformer:** native streaming identification plus periodic/final speaker-label refinement.
- **WeSpeaker:** one persistent Python helper extracts speaker embeddings per speech segment and tracks speakers independently per channel. The implementation is ported from Python Livekeet, retaining its MIT license.
- **pyannote:** periodically analyzes captured audio, with a final pass at stop. Requires a Hugging Face token and acceptance of the `pyannote/speaker-diarization-3.1` and `pyannote/segmentation-3.0` model terms. Audio stays local.
- **Claude cleanup:** uses `claude-runner` and existing Claude Code authentication. Corrections run in the background in batches, with remaining batches drained on stop. This preserves the Swift app's correction workflow rather than blocking each utterance as the Python CLI does. Cleanup failure preserves the original transcript.

Model weights download on first use. Missing Python dependencies or credentials produce a startup error before recording. A helper failure during a recording is reported while transcription continues.

## Compatibility notes

The CLI ports the controls from Python Livekeet 0.1.18, plus the local relabel fixes. Native capture replaces Python's separate downloaded `audiocapture` binary. Sortformer is the default engine; existing configs explicitly selecting WeSpeaker/pyannote keep that selection. CLI speaker identification is opt-in unless enabled by config, multiple names, or `--engine`; the Mac app retains its existing default. Swift source installs use `make install` and the source-aware updater instead of `uv tool install`.
