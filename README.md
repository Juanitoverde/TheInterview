# TheInterview

An immersive job-interview practice app for Apple Vision Pro. You check in at a virtual reception desk, follow the receptionist through the office to an interview room, and answer questions out loud from an interviewer. Afterwards you get a detailed feedback report on your answers, your eye contact and your delivery.

The original product vision is in [`temp_info_placeholder.txt`](temp_info_placeholder.txt).

## What happens in a session

1. **Reception.** The office fades in around you. Ava, the receptionist, waves and greets you by name: *"What position are you applying for today, Ms. Rivera?"* You answer out loud, for example *"I'm applying for a Technical Mechanic."*
2. **The walk.** *"Oh, I see your appointment right here. Follow me this way."* She leads you down the corridor past colleagues at their desks and into the interview room. Turn on **Comfort mode** for a fade instead of the walk.
3. **The interview.** Daniel Park stands to greet you, sits, and asks *"Are you ready to begin?"* He then asks questions written for the role you named. While you answer he listens attentively, nodding now and then. When an answer is vague, lacks an example or leaves out the outcome, he follows up (*"And what was the outcome?"*), up to twice per interview. Say *"that's my answer"*, pause, or tap **Done** to finish an answer. You can also ask him to repeat a question, or type instead of speaking.
4. **The report.** You get an overall score, eye-contact percentage, speaking pace, filler words and speaking time. There's a list of strengths and things to work on. Every question gets a score, feedback, a concrete tip and, with OpenAI, an example of how a stronger answer might sound. Reports are saved and can be shared as text.

## Requirements

- Xcode 16 or later with the visionOS 2 SDK (the project uses Xcode 16's synchronized folders)
- Apple Vision Pro running visionOS 2 or later, or the visionOS simulator
- Optional: an OpenAI API key

## Getting started

1. Open `TheInterview.xcodeproj`.
2. Select the **TheInterview** target, then **Signing & Capabilities**. Choose your team and, if needed, change the bundle identifier (`com.theinterview.TheInterview`).
3. Choose a Vision Pro device or the visionOS simulator and press **Run**.
4. Optional: in the app, open **Settings**, paste your OpenAI API key and tap **Test connection**. For simulator runs you can also set an `OPENAI_API_KEY` environment variable in your own (unshared) scheme.

Without a key the app still works end to end, using its built-in question bank and on-device scoring.

### Running the tests

The interview logic lives in a Swift package with no Apple-only dependencies, so its tests run anywhere Swift does:

```sh
cd Packages/InterviewCore
swift test
```

In Xcode, **Product > Test** (⌘U) runs the same tests from the shared scheme.

## How it works

```
TheInterview/                 visionOS app (SwiftUI, RealityKit, ARKit, AVFoundation, Speech)
  App/                        App entry point, AppModel (state and flow), settings
  Immersive/                  The 3D office, characters and their animation, stage choreography
  Services/                   Speech in and out, head-pose tracking, Keychain
  Views/                      Home, settings, in-office control panel, feedback report
Packages/InterviewCore/       Platform-independent logic (unit tested)
  Engine/                     InterviewEngine: the scripted flow from reception to report
  AI/                         OpenAI client, prompts, question/reaction/evaluation services
  Analysis/                   Reply parsing, speech metrics, attention maths, on-device evaluator
  Questions/                  Built-in question bank
  Persistence/                Report storage
```

`InterviewEngine` owns the order of events and the script. Speech, the 3D stage, head tracking and the network are injected through small protocols (`VoiceOutput`, `VoiceInput`, `StageDirecting`, `AttentionTracking`, `QuestionGenerating`, `InterviewEvaluating`). This lets the whole interview run in tests with scripted replies.

### The office

The office, its furniture and the seven-person cast are built procedurally from RealityKit primitives, so the project has no 3D asset dependencies.

- **Surfaces** use textures drawn in code at real-world scale: wood-plank and stone-tile floors, carpet tiles, ceiling tiles, wood grain and patterned rugs.
- **Characters** are jointed figures with eyes that blink, lips that move as they talk, and hands that gesture. They breathe, shift their weight, walk, type and wave, and they turn their heads to look at you. While you speak they listen attentively, with small nods and a tilt of the head.
- **Voices** are rendered with the system speech synthesizer and played from each character's mouth with spatial audio, so they come from where the person is standing.
- **Movement:** when you're led to the interview room, it is the office that moves around you, not you; you stay where you are.
- **Ambience** (room tone, distant voices, keyboards) is a generated loop in `TheInterview/Resources`.

### Questions and feedback

- **With an OpenAI key**, questions are generated for the exact position you name, at your chosen level and focus. After each answer the model writes the interviewer's brief reaction and decides whether a follow-up question is warranted. After the interview the transcript and measurements are sent for evaluation; the model writes the scores, the feedback, and an example stronger answer for each question. Requests use the Chat Completions API in JSON mode. The model is configurable in Settings (default `gpt-4.1-mini`).
- **Measured numbers always come from the device**: words per minute, filler words, speaking time and eye contact. The AI's feedback is layered on top of these.
- **If there's no key, or a request fails or times out**, the app falls back to its built-in question bank and an on-device evaluator. The evaluator scores relevance, clarity and structure, including STAR structure for behavioral questions. On-device rules also decide follow-ups: answers that are very brief, have no concrete example, or tell a story without its outcome get probed.
- **Follow-up replies** count toward the answer's score, as they would in a real interview. Follow-ups can be turned off in Settings.

### Eye contact

visionOS doesn't give apps access to eye-tracking data; where you look stays private to the system. The Vision framework can't see your eyes either. So TheInterview estimates eye contact from **head pose**, which ARKit's world tracking does provide. You count as engaged while your head faces the interviewer's eyes, within about 20° horizontally and 18° vertically. Glances shorter than a second lower the percentage but aren't counted as separate look-aways. This is a reasonable stand-in, since people turn their heads toward whoever they're looking at, but it can't detect eyes moving while the head stays still. Head tracking needs a real device; in the simulator the report notes that eye contact wasn't tracked.

### Privacy

- Speech is recognised on device where supported.
- Transcripts leave the device only when you've saved an OpenAI API key; the key is kept in the Keychain.
- Reports are stored locally in Application Support.

## Customising

- **Company name**: in Settings; it appears on the lobby wall and in the receptionist's greeting.
- **Characters' names and script**: `InterviewConfiguration` and `InterviewScript` in the core package.
- **Office layout**: `OfficeBuilder.swift`. The layout diagram is in its header comment.
- **Built-in questions**: `QuestionBank.swift`.
