# Livekeet

Live transcription for Apple Silicon, with a native Mac app and a command-line interface. Both capture microphone and system audio, write timestamped Markdown, and share the same transcription pipeline.

Speech recognition runs locally using MLX or an optional Python speech helper. Optional Claude cleanup sends transcript text to Claude; it is off by default. Speaker analysis runs locally with native Sortformer or optional Python WeSpeaker/pyannote engines.

## Build and run

Requires macOS 14+, Apple Silicon, Xcode's command-line/Metal tools, and Swift **6.2 or newer**. `scripts/swift.sh` uses a locally installed Swift 6.2.3 toolchain when available, otherwise Xcode's Swift. Set `LIVEKEET_SWIFT=/path/to/swift` to override it.

```sh
make build
.build/debug/livekeet --help
.build/debug/livekeet record --help

make build-app                      # local app with a persistent signing identity
open .build/debug/Livekeet.app

./deploy-locally.sh                  # build, install in /Applications, open

make test
python3 -m unittest discover -s Tests/Python -v
```

Local builds use a persistent signing certificate without hardened runtime. If
there is exactly one valid Code Signing identity in your keychain, the first
successful build selects it. Otherwise set `SIGNING_IDENTITY` to the certificate
name or SHA-1 reported by `security find-identity -v -p codesigning`. An Apple
Development certificate or a local Code Signing certificate works for development.
The selected fingerprint is saved in `~/.config/livekeet/signing-identity` (under
`XDG_CONFIG_HOME` when set), so updates keep the same identity. Builds fail if that
certificate becomes unavailable instead of silently changing identity. To change
it deliberately, set `SIGNING_IDENTITY` again. Release builds use
`RELEASE_SIGNING_IDENTITY` and hardened runtime.

Ad-hoc signing (`SIGNING_IDENTITY=- make build-app`) is available explicitly for
disposable builds, but its identity changes with the app binary and macOS can
reject previously granted permissions. Switching from an old ad-hoc build to a
certificate requires granting permissions once again. If Screen Recording is
already enabled but capture is denied, toggle Livekeet off and on in System
Settings → Privacy & Security → Screen & System Audio Recording, then quit and
reopen Livekeet. Microphone permission is listed separately under Microphone.
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
livekeet --model mlx-community/parakeet-tdt-0.6b-v3 # Parakeet v3
livekeet --model mlx-community/parakeet-tdt-0.6b-v2
livekeet --diarize --engine sortformer # Streaming Sortformer v2.1 (default)
livekeet --engine wespeaker
livekeet --engine pyannote
livekeet --cleanup                     # optional Claude correction
livekeet --no-cleanup --no-diarize      # override config defaults
livekeet --dump-audio --no-relabel      # save WAV segments; skip final prompt

livekeet init                          # also --init
livekeet config                        # also --config; prints path, not secrets
livekeet devices                       # also --devices
livekeet models
livekeet diarizers                      # speaker models, strengths, DER and sources
livekeet relabel meeting.md
livekeet relabel meeting.md --rename 'Alice=Bob' --rename 'Bob=Alice'
livekeet update --check
livekeet update                        # fetch, fast-forward, rebuild, reinstall
```

All recording flags can also follow `livekeet record`. `-w` aliases `--with`, `-m` aliases `--mic-only`, and `-d` aliases `--device`. Device selection accepts the index printed by `devices`, an exact or unambiguous partial name, or a persistent UID. Indices can change after devices reconnect. Unlike the Python CLI, a selected microphone works alongside system capture too.

The model selected with `--model` is the model used; otherwise `[defaults].model` applies. Multiple `--with` names, `--diarize`, or an explicit `--engine` enable speaker identification; `--no-diarize` wins over all of them. `--no-cleanup` wins over `--cleanup` and the config. Microphone-only mode ignores remote speaker names. `--mic-only` and `--system-only` are mutually exclusive.

Ctrl+C finishes queued transcription, speaker analysis, and remaining cleanup before saving. In an interactive terminal, recordings with system audio offer speaker renaming afterward. `--no-relabel` disables the prompt; redirected input never prompts. Relabeling supports collision-safe swaps, touches only speaker labels, and writes atomically. EOF or Ctrl+C during the prompt leaves the original intact.

`update` follows the source checkout's tracked branch, refuses dirty or diverged checkouts, and never resets local changes. For a development binary, supply `--source /path/to/livekeet-mlx`. `--check` fetches Git history without installing. The Mac app updates separately through its Sparkle menu.

## Speaker models

Settings → Models → Speaker identification has the same curated picker as speech recognition: release information, strengths, tradeoffs, speaker limits, DER with its dataset/scoring conditions, and primary sources. `livekeet diarizers` shows the same catalog. Scores describe the original published evaluations, not measured Livekeet accuracy; a lower number from a different benchmark is not a direct comparison.

| CLI engine | Model | Local implementation |
| --- | --- | --- |
| `sortformer` | Streaming Sortformer v2.1 (default) | Native Core ML, balanced 1.04-second input buffer, 4 speakers/channel |
| `community-1` | pyannote Community-1 | Python batch pipeline, flexible speaker count |
| `ls-eend` | LS-EEND DIHARD III | Native Core ML streaming, 10 speaker slots/channel |
| `diarizen` | DiariZen Large-s80-v2 | Python batch pipeline, up to 20 speakers/channel |
| `suplime` | SUPlime | Python batch pipeline |
| `suplime-large` | SUPlime-L | Python batch pipeline, larger encoder |
| `sortformer-v1` | Original Sortformer v1 | Legacy native MLX, 4 speakers/channel |
| `pyannote` | pyannote 3.1 | Legacy Python batch pipeline |
| `wespeaker` | WeSpeaker ResNet34 | Legacy Python/MLX chunk matching, 5 speakers/channel |

Microphone and system audio keep independent speaker state. Native streaming engines update labels during recording and flush their final buffered audio at stop. Batch engines analyze the accumulated recording periodically and at stop; processing may take longer than live engines, especially on CPU. The transcript still uses speech/sentence segments, so word-perfect attribution during interruptions is not guaranteed.

Use **Set up local speaker support** under the selected model, or `scripts/setup-python.sh speakers` to install all optional speaker environments. A single engine can be installed with `/usr/bin/python3 Sources/LivekeetCore/Resources/Python/setup_diarization.py ENGINE`. They live in `~/.local/share/livekeet/diarization/ENGINE` and are chosen automatically when present; otherwise the configured Python executable is used. Isolated environments keep DiariZen’s older pyannote fork separate from Community-1 and SUPlime. Speech and correction environments are unchanged.

pyannote 3.1 and Community-1 require accepting their Hugging Face access conditions and setting `HF_TOKEN` or `[pyannote].token` in the CLI configuration. Audio inference stays local. The native Core ML models cache under `~/Library/Application Support/FluidAudio/Models`; Python and legacy MLX weights normally use the Hugging Face cache. DiariZen, SUPlime/SUPlime-L, and legacy Sortformer v1 have noncommercial model weights; the picker links their terms.

To check real native inference with a supplied mono 16 kHz PCM WAV, run `scripts/smoke-diarization.sh sortformer sample.wav` or `scripts/smoke-diarization.sh ls-eend sample.wav`. These opt-in checks download the model when needed and verify nonempty speaker output, timestamp bounds, channel isolation, and final flushing. They are integration tests, not DER benchmarks.

## Configuration and Mac app settings

`livekeet init` creates `~/.config/livekeet/config.toml` without overwriting an existing file. Python Livekeet's config keys are supported:

```toml
[output]
directory = "~/meetings"
filename = "{datetime}-{names}.md"
save_audio = false

[speaker]
name = "Me"

[defaults]
model = "mlx-community/parakeet-tdt-0.6b-v3"
diarize = false
engine = "sortformer"
# language = "es" # required for Cohere and Canary
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

Audio-source controls, speaker identification, and the AI correction switch live in **Settings → General → Recording defaults**. Engine and correction details remain in Advanced.

Enter other speakers' names in the main recording window. They apply only to that recording and clear after it is saved; your own name remains a persistent preference in General settings.

The Mac app keeps its own persistent preferences. **Settings → General → Import settings from CLI config** copies CLI preferences into the app. Microphone selection and all three speaker engines are available in Settings. The app reads the TOML replacement dictionary and pyannote token at the start of each recording. Use an absolute Python path for launching from Finder.

## Recordings and local storage

The app and CLI save Markdown recordings in **`~/meetings`** by default, creating the folder when needed. Set a different default in General settings or `[output].directory`. Empty directory settings also use `~/meetings`. A CLI output argument overrides the default; `livekeet ./` explicitly uses the current directory. In the app, **Choose folder…** applies only to the next recording. Existing files are left where they are.

The main window lists one entry per recording, including recordings saved by the CLI or in other folders. Select an entry to read its transcript, see its location, or open it in Finder. The app discovers existing Livekeet transcripts in the default output folder; **Import transcripts…** adds older transcripts from elsewhere without copying them. File bookmarks follow moves and renames when macOS can resolve them. Disconnected drives and missing files stay in the list; **Locate transcript…** reconnects an entry to its file.

- **Library index:** `~/Library/Application Support/Livekeet/recordings.json`. Stores identifiers, dates, model, participant names, and file paths/bookmarks; transcript files remain in their chosen folders. App and CLI share this index. Incomplete sessions remain marked Unfinished.
- **Markdown files:** `~/meetings/<timestamp>.md` by default, or a chosen recording name/folder. Duplicate filenames get numeric suffixes.
- **Optional full audio:** enable **Save full audio** for a recording, CLI `--save-audio`, or `[output].save_audio = true`. Saves `microphone.wav` and/or `system.wav` in `<transcript-stem>.audio` alongside the Markdown, depending on the captured sources. It is off by default. Advanced **Dump audio** separately retains individual speech clips in that folder. Temporary processing audio is removed when the session finishes normally.
- **App preferences:** macOS UserDefaults, domain `com.livekeet.app` (normally `~/Library/Preferences/com.livekeet.app.plist`).
- **CLI preferences:** `~/.config/livekeet/config.toml`.
- **Downloaded models:** Hugging Face cache under `~/.cache/huggingface/hub` by default; the optional Python environment is under `~/.local/share/livekeet/python`.

## Projects

A project is a named group of recordings in one folder. Create one with the folder-plus button beside **Projects** in the sidebar. The suggested folder is `<default recordings folder>/<project name>`; **Choose folder…** can use an existing folder anywhere. Existing Livekeet Markdown transcripts directly inside that folder join the project automatically. Subfolders are separate.

Select a project to see its recordings and start a new recording there. The recording form also has a **Project** picker. Every recording in a project saves to its shared folder; choosing **No project** restores the usual default or per-recording folder controls. **All recordings** includes every recording across all projects and other folders.

Right-click a saved recording and use **Move to project** to move its Markdown and associated audio together. Names get numeric suffixes when needed, and the library keeps the same recording entry. Finish active recordings before moving them. Project names can be changed from their context menu; removing a project removes its grouping while retaining the folder and all recordings.

The app and CLI share projects in the local library index. The existing recordings library upgrades automatically. Folder bookmarks follow project folders moved or renamed on the same disk when macOS can resolve them; a disconnected folder stays listed and cannot be used for new recordings until available again.

```sh
livekeet projects create Research                         # ~/meetings/Research by default
livekeet projects create Meetings --folder ~/meetings     # group existing recordings
livekeet projects list
livekeet --project Research                               # timestamped Markdown in its folder
livekeet Weekly.md --project Research                     # named recording in its folder
livekeet projects rename Research Studies                # keeps the same folder
```

Project names are unique (ignoring case), and a folder can belong to one project. The CLI accepts a project name or its ID from `projects list`. With `--project`, output paths outside the project's folder are rejected.

## Speech models

Parakeet TDT 0.6B v3 is the default for new app preferences and CLI configurations. Existing explicit model selections are preserved.

**Settings → Models** selects the actual transcription model and shows its release date, strengths, tradeoffs, published WER, and source. There is no separate multilingual switch. The CLI uses `--model` or `[defaults].model`; `livekeet models` prints the same catalog.

| Choice | Local runtime | Language selection |
| --- | --- | --- |
| Parakeet TDT 0.6B v2 | Native MLX | English only |
| Parakeet TDT 0.6B v3 | Native MLX | Automatic, 25 languages |
| Qwen3-ASR 0.6B 4-bit; 1.7B 4-bit or 8-bit | Native MLX | Automatic, 30 languages |
| Voxtral Mini 4B Realtime 4-bit | Native MLX | Automatic, 13 languages |
| Cohere Transcribe 2B FP16 | Native MLX | Required, 14 languages |
| Granite Speech 4.0 1B 5-bit | Native MLX | Automatic, 6 input languages |
| Canary 1B v2 8-bit | Native MLX | Required, 25 languages |
| Moonshine Streaming Small Spanish | Python / CPU | Spanish only |
| Whisper large-v3 and large-v3 Turbo | Native MLX | Automatic |
| Voxtral Mini 3B (2025) | Python / Metal when available | Automatic |

Apple SpeechAnalyzer is shown as unavailable with an explanation: it requires macOS 26, and this build does not include its integration.

Cohere and Canary need **Transcription language** in Settings, or `--language es` / `[defaults].language = "es"` in the CLI. Language hints are only passed to those models; Granite's separate translation mode is not enabled. Speaker identification is independent of the speech model.

For Moonshine and the original Voxtral, click **Set up local speech support** in Models, or run `scripts/setup-python.sh speech` and choose the printed path under Advanced → Speech Python. The speech setup button preserves the existing speaker/cleanup Python setting. CLI users can set `[python].speech_executable` separately or leave it unset to use `[python].executable`. Model weights download on first use. Unsupported custom architectures produce a startup error rather than falling back to another model.

WER is lower-is-better word error rate. Catalog figures describe the publishers' original models and named datasets, not benchmarks of these quantized builds or this Mac. Different languages and evaluation sets are not directly comparable. Livekeet transcribes completed speech segments, so a model's published streaming delay is not the app's latency.

To check an actual checkpoint against a local Spanish audio file (downloads weights when needed):

```sh
scripts/smoke-speech-model.sh mlx-community/Qwen3-ASR-0.6B-4bit /absolute/path/spanish.wav
# For Python speech models, also set LIVEKEET_SMOKE_PYTHON to the helper executable.
```

This smoke test checks loading and nonempty transcription; it is not a WER benchmark.

## Optional Python engines and cleanup

The native Sortformer path needs no Python. Install only the helpers you want with [uv](https://docs.astral.sh/uv/):

```sh
scripts/setup-python.sh wespeaker  # or pyannote, speech, cleanup, all
```

The script creates `~/.local/share/livekeet/python` and prints the executable path to use in `[python] executable` and the app's Advanced settings. Set `LIVEKEET_PYTHON_ENV` to choose another environment.

- **Sortformer:** native streaming identification plus periodic/final speaker-label refinement.
- **WeSpeaker:** one persistent Python helper extracts speaker embeddings per speech segment and tracks speakers independently per channel. The implementation is ported from Python Livekeet, retaining its MIT license.
- **pyannote:** periodically analyzes captured audio, with a final pass at stop. Requires a Hugging Face token and acceptance of the `pyannote/speaker-diarization-3.1` and `pyannote/segmentation-3.0` model terms. Audio stays local.
- **Claude cleanup:** uses `claude-runner` and existing Claude Code authentication. Corrections run in the background in batches, with remaining batches drained on stop. This preserves the Swift app's correction workflow rather than blocking each utterance as the Python CLI does. Cleanup failure preserves the original transcript.

Model weights download on first use. Missing Python dependencies or credentials produce a startup error before recording. A speaker-helper failure during a recording is reported while transcription continues. A speech-helper failure stops capture and saves the text already transcribed.

## Compatibility notes

The CLI ports the controls from Python Livekeet 0.1.18, plus the local relabel fixes. Native capture replaces Python's separate downloaded `audiocapture` binary. Sortformer is the default engine; existing configs explicitly selecting WeSpeaker/pyannote keep that selection. CLI speaker identification is opt-in unless enabled by config, multiple names, or `--engine`; the Mac app retains its existing default. Swift source installs use `make install` and the source-aware updater instead of `uv tool install`.
